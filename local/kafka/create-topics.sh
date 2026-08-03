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

TOPIC_NAME="${TOPIC_NAME:-${KAFKA_TOPIC_LOG_EVENTS:-mvp.log-events}}"
DLQ_TOPIC_NAME="${DLQ_TOPIC_NAME:-${KAFKA_TOPIC_LOG_EVENTS_DLQ:-mvp.log-events-dlq}}"

PARTITIONS="${PARTITIONS:-3}"
REPLICATION_FACTOR="${REPLICATION_FACTOR:-1}"
RETENTION_MS="${RETENTION_MS:-604800000}"

KAFKA_INTERNAL_PORT="${KAFKA_INTERNAL_PORT:-9092}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-${KAFKA_SERVICE}:${KAFKA_INTERNAL_PORT}}"
KAFKA_TOPICS_CMD="${KAFKA_TOPICS_CMD:-/opt/kafka/bin/kafka-topics.sh}"

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

run_kafka_topics() {
  MSYS_NO_PATHCONV=1 docker "${COMPOSE_ARGS[@]}" exec -T "${KAFKA_SERVICE}" \
    sh -lc '"$@"' sh \
    "${KAFKA_TOPICS_CMD}" "$@"
}

create_topic() {
  local topic_name="$1"

  echo "Creating topic if not exists: ${topic_name}"

  run_kafka_topics \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --create \
    --if-not-exists \
    --topic "${topic_name}" \
    --partitions "${PARTITIONS}" \
    --replication-factor "${REPLICATION_FACTOR}" \
    --config "retention.ms=${RETENTION_MS}"
}

describe_topic() {
  local topic_name="$1"

  echo "Topic description: ${topic_name}"

  run_kafka_topics \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --describe \
    --topic "${topic_name}"
}

echo "Kafka service: ${KAFKA_SERVICE}"
echo "Bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"
echo "Main topic: ${TOPIC_NAME}"
echo "DLQ topic: ${DLQ_TOPIC_NAME}"
echo "Partitions: ${PARTITIONS}"
echo "Replication factor: ${REPLICATION_FACTOR}"
echo "Retention ms: ${RETENTION_MS}"

echo "Checking Kafka broker health..."

run_kafka_topics \
  --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
  --list >/dev/null

create_topic "${TOPIC_NAME}"
create_topic "${DLQ_TOPIC_NAME}"

describe_topic "${TOPIC_NAME}"
describe_topic "${DLQ_TOPIC_NAME}"

echo "Done."
