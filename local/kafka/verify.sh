#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-${LOCAL_DIR}/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${LOCAL_DIR}/.env}"
KAFKA_SERVICE="${KAFKA_SERVICE:-kafka}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

TOPIC_NAME="${TOPIC_NAME:-${KAFKA_TOPIC_LOG_EVENTS:-log-analyzer.dev.log-events}}"
DLQ_TOPIC_NAME="${DLQ_TOPIC_NAME:-${KAFKA_TOPIC_LOG_EVENTS_DLQ:-log-analyzer.dev.log-events-dlq}}"
CONSUMER_GROUP="${CONSUMER_GROUP:-${KAFKA_CONSUMER_GROUP_ID:-event-consumer}}"

KAFKA_INTERNAL_PORT="${KAFKA_INTERNAL_PORT:-9092}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-${KAFKA_SERVICE}:${KAFKA_INTERNAL_PORT}}"
KAFKA_TOPICS_CMD="${KAFKA_TOPICS_CMD:-/opt/kafka/bin/kafka-topics.sh}"
KAFKA_CONSUMER_GROUPS_CMD="${KAFKA_CONSUMER_GROUPS_CMD:-/opt/kafka/bin/kafka-consumer-groups.sh}"
KAFKA_GET_OFFSETS_CMD="${KAFKA_GET_OFFSETS_CMD:-/opt/kafka/bin/kafka-get-offsets.sh}"
KAFKA_RUN_CLASS_CMD="${KAFKA_RUN_CLASS_CMD:-/opt/kafka/bin/kafka-run-class.sh}"

to_docker_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "${path}"
  else
    printf '%s' "${path}"
  fi
}

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "[ERROR] ${COMPOSE_FILE} not found." >&2
  exit 1
fi

COMPOSE_ARGS=(compose)

if [[ -f "${ENV_FILE}" ]]; then
  COMPOSE_ARGS+=(--env-file "$(to_docker_path "${ENV_FILE}")")
else
  echo "[WARN] ${ENV_FILE} not found. Running without --env-file."
fi

COMPOSE_ARGS+=(-f "$(to_docker_path "${COMPOSE_FILE}")")

if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
  COMPOSE_ARGS+=(--project-name "${COMPOSE_PROJECT_NAME}")
fi

run_in_kafka() {
  MSYS_NO_PATHCONV=1 docker "${COMPOSE_ARGS[@]}" exec -T "${KAFKA_SERVICE}" "$@"
}

run_kafka_topics() {
  run_in_kafka sh -lc '"$@"' sh "${KAFKA_TOPICS_CMD}" "$@"
}

run_kafka_consumer_groups() {
  run_in_kafka sh -lc '"$@"' sh "${KAFKA_CONSUMER_GROUPS_CMD}" "$@"
}

run_kafka_get_offsets() {
  if run_in_kafka sh -lc 'test -x "$1"' sh "${KAFKA_GET_OFFSETS_CMD}"; then
    run_in_kafka sh -lc '"$@"' sh "${KAFKA_GET_OFFSETS_CMD}" "$@"
  else
    run_in_kafka sh -lc '"$@"' sh "${KAFKA_RUN_CLASS_CMD}" kafka.tools.GetOffsetShell "$@"
  fi
}

print_section() {
  echo
  echo "== $1 =="
}

require_topic() {
  local topic_name="$1"
  local output

  if output="$(run_kafka_topics \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --describe \
    --topic "${topic_name}" 2>&1)"; then
    echo "${output}"
    echo "[OK] Topic exists: ${topic_name}"
  else
    echo "${output}" >&2
    echo "[ERROR] Topic not found or not describable: ${topic_name}" >&2
    return 1
  fi
}

show_topic_offsets() {
  local topic_name="$1"

  run_kafka_get_offsets \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --topic "${topic_name}"
}

show_consumer_group() {
  local group_name="$1"

  if run_kafka_consumer_groups \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --describe \
    --group "${group_name}"; then
    echo "[OK] Consumer group is describable: ${group_name}"
  else
    echo "[WARN] Consumer group is not available yet: ${group_name}" >&2
    echo "[WARN] Start event-consumer and consume at least one message, then run this script again." >&2
    return 2
  fi
}

echo "Kafka service: ${KAFKA_SERVICE}"
echo "Bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"
echo "Main topic: ${TOPIC_NAME}"
echo "DLQ topic: ${DLQ_TOPIC_NAME}"
echo "Consumer group: ${CONSUMER_GROUP}"

print_section "Broker Health"
run_kafka_topics \
  --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
  --list >/dev/null
echo "[OK] Kafka broker is reachable."

print_section "Topic List"
run_kafka_topics \
  --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
  --list

print_section "Topic Details: ${TOPIC_NAME}"
require_topic "${TOPIC_NAME}"

print_section "Topic Details: ${DLQ_TOPIC_NAME}"
require_topic "${DLQ_TOPIC_NAME}"

print_section "End Offsets: ${TOPIC_NAME}"
show_topic_offsets "${TOPIC_NAME}"

print_section "End Offsets: ${DLQ_TOPIC_NAME}"
show_topic_offsets "${DLQ_TOPIC_NAME}"

print_section "Consumer Groups"
run_kafka_consumer_groups \
  --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
  --list

print_section "Consumer Group Details: ${CONSUMER_GROUP}"
show_consumer_group "${CONSUMER_GROUP}" || true

echo
echo "Kafka local verification completed."
