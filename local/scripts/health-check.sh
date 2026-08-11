#!/usr/bin/env bash
set -uo pipefail

# ============================================================
# Local environment health check
#
# Purpose:
# - Load local/.env variables
# - Check local infrastructure readiness
# - Check MVP3 backend actuator endpoints
# - Check Kafka/OpenSearch resources required by backend services
# - Print a clear ready/not-ready result without validating business flows
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${LOCAL_DIR}/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-${LOCAL_DIR}/docker-compose.yml}"

FAILED=0

to_docker_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "${path}"
  else
    printf '%s' "${path}"
  fi
}

ok() {
  echo "[OK] $1"
}

fail() {
  echo "[FAIL] $1"
  FAILED=1
}

check_cmd() {
  local ok_message="$1"
  local fail_message="$2"
  shift 2

  if "$@" >/dev/null 2>&1; then
    ok "${ok_message}"
  else
    fail "${fail_message}"
  fi
}

check_http_success() {
  local name="$1"
  local url="$2"

  if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
    ok "${name} health check passed"
  else
    fail "${name} health check failed: ${url}"
  fi
}

check_http_reachable() {
  local ok_message="$1"
  local fail_message="$2"
  local url="$3"
  local status_code

  status_code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "${url}" 2>/dev/null || true)"

  case "${status_code}" in
    2*|3*)
      ok "${ok_message}"
      ;;
    4*)
      ok "${ok_message} (HTTP ${status_code})"
      ;;
    *)
      fail "${fail_message}: ${url}"
      ;;
  esac
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "Required command not found: ${command_name}"
    return 1
  fi
}

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  fail ".env file not found: ${ENV_FILE}"
fi

if [ ! -f "${COMPOSE_FILE}" ]; then
  fail "docker compose file not found: ${COMPOSE_FILE}"
fi

require_command docker
require_command curl

COMPOSE_ENV_FILE="$(to_docker_path "${ENV_FILE}")"
COMPOSE_FILE_PATH="$(to_docker_path "${COMPOSE_FILE}")"
COMPOSE_CMD=(docker compose --env-file "${COMPOSE_ENV_FILE}" -f "${COMPOSE_FILE_PATH}")

if [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
  COMPOSE_CMD+=(--project-name "${COMPOSE_PROJECT_NAME}")
fi

run_compose_exec() {
  local service="$1"
  shift
  MSYS_NO_PATHCONV=1 "${COMPOSE_CMD[@]}" exec -T "${service}" "$@"
}

run_kafka_topics() {
  run_compose_exec "${KAFKA_SERVICE}" sh -lc '"$@"' sh "${KAFKA_TOPICS_CMD}" "$@"
}

run_kafka_consumer_groups() {
  run_compose_exec "${KAFKA_SERVICE}" sh -lc '"$@"' sh "${KAFKA_CONSUMER_GROUPS_CMD}" "$@"
}

topic_exists() {
  local topic_name="$1"
  run_kafka_topics --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" --describe --topic "${topic_name}"
}

consumer_group_exists() {
  local group_name="$1"
  run_kafka_consumer_groups --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" --list | grep -Fx "${group_name}"
}

opensearch_get() {
  local path="$1"
  curl "${OPENSEARCH_CURL_OPTIONS[@]}" "${OPENSEARCH_URL}${path}"
}

opensearch_index_pattern_exists() {
  local index_pattern="$1"
  local output

  output="$(opensearch_get "/_cat/indices/${index_pattern}?h=index" 2>/dev/null || true)"
  [ -n "${output}" ]
}

echo "Using compose file: ${COMPOSE_FILE}"
echo "Using env file: ${ENV_FILE}"
echo "Compose project: ${COMPOSE_PROJECT_NAME:-default}"
echo

KAFKA_SERVICE="${KAFKA_SERVICE:-kafka}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-${KAFKA_SERVICE}:${KAFKA_INTERNAL_PORT:-9092}}"
KAFKA_TOPICS_CMD="${KAFKA_TOPICS_CMD:-/opt/kafka/bin/kafka-topics.sh}"
KAFKA_CONSUMER_GROUPS_CMD="${KAFKA_CONSUMER_GROUPS_CMD:-/opt/kafka/bin/kafka-consumer-groups.sh}"
KAFKA_TOPIC_LOG_EVENTS="${KAFKA_TOPIC_LOG_EVENTS:-log-analyzer.dev.log-events}"
KAFKA_TOPIC_LOG_EVENTS_DLQ="${KAFKA_TOPIC_LOG_EVENTS_DLQ:-log-analyzer.dev.log-events-dlq}"
KAFKA_CONSUMER_GROUP_ID="${KAFKA_CONSUMER_GROUP_ID:-event-consumer}"

OPENSEARCH_CLIENT_HOST="${OPENSEARCH_CLIENT_HOST:-${LOCAL_BIND_ADDRESS:-localhost}}"
if [ "${OPENSEARCH_CLIENT_HOST}" = "0.0.0.0" ]; then
  OPENSEARCH_CLIENT_HOST="localhost"
fi

OPENSEARCH_SCHEME="${OPENSEARCH_SCHEME:-http}"
OPENSEARCH_HOST_PORT="${OPENSEARCH_HOST_PORT:-9200}"
OPENSEARCH_URL="${OPENSEARCH_URL:-${OPENSEARCH_SCHEME}://${OPENSEARCH_CLIENT_HOST}:${OPENSEARCH_HOST_PORT}}"
OPENSEARCH_INDEX_PATTERN="${OPENSEARCH_INDEX_PATTERN:-log-analyzer-dev-logs-*}"
OPENSEARCH_READ_ALIAS="${OPENSEARCH_READ_ALIAS:-log-analyzer-dev-logs-read}"
OPENSEARCH_WRITE_ALIAS="${OPENSEARCH_WRITE_ALIAS:-log-analyzer-dev-logs-write}"
OPENSEARCH_PIPELINE_NAME="${OPENSEARCH_PIPELINE_NAME:-log-analyzer-dev-logs-pipeline}"

OPENSEARCH_CURL_OPTIONS=(-fsS --max-time 5)
if [ "${OPENSEARCH_CURL_INSECURE:-false}" = "true" ]; then
  OPENSEARCH_CURL_OPTIONS+=(-k)
fi
if [ "${OPENSEARCH_DISABLE_SECURITY_PLUGIN:-true}" != "true" ] && [ -n "${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}" ]; then
  OPENSEARCH_USERNAME="${OPENSEARCH_USERNAME:-admin}"
  OPENSEARCH_CURL_OPTIONS+=(-u "${OPENSEARCH_USERNAME}:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}")
fi

LOCAL_CLIENT_HOST="${LOCAL_CLIENT_HOST:-localhost}"
GATEWAY_SERVICE_URL="${GATEWAY_SERVICE_URL:-http://${LOCAL_CLIENT_HOST}:7010}"
LOG_SERVICE_URL="${LOG_SERVICE_URL:-http://${LOCAL_CLIENT_HOST}:7020}"
EVENT_CONSUMER_URL="${EVENT_CONSUMER_URL:-http://${LOCAL_CLIENT_HOST}:7030}"
GATEWAY_LOG_SERVICE_ROUTE_PATH="${GATEWAY_LOG_SERVICE_ROUTE_PATH:-/api/logs/health}"

KAFKA_UI_URL="${KAFKA_UI_URL:-http://${LOCAL_CLIENT_HOST}:${KAFKA_UI_HOST_PORT:-18080}}"
OPENSEARCH_DASHBOARDS_URL="${OPENSEARCH_DASHBOARDS_URL:-http://${LOCAL_CLIENT_HOST}:${OPENSEARCH_DASHBOARDS_HOST_PORT:-15601}}"

echo "== Infra =="
check_cmd "PostgreSQL is ready" "PostgreSQL health check failed" \
  run_compose_exec "postgres" pg_isready -U "${POSTGRES_USER:-admin}" -d "${POSTGRES_DB:-log-analyzer-db}"
check_cmd "Redis is ready" "Redis health check failed" \
  run_compose_exec "redis" redis-cli ping
check_cmd "Kafka broker is ready" "Kafka broker health check failed" \
  run_compose_exec "${KAFKA_SERVICE}" sh -lc '/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server "$1"' sh "${KAFKA_BOOTSTRAP_SERVER}"
check_cmd "OpenSearch is ready" "OpenSearch health check failed: ${OPENSEARCH_URL}/_cluster/health" \
  opensearch_get "/_cluster/health"
check_http_success "Kafka UI" "${KAFKA_UI_URL}"
check_http_success "OpenSearch Dashboards" "${OPENSEARCH_DASHBOARDS_URL}"

echo
echo "== Kafka Resources =="
check_cmd "Kafka topic exists: ${KAFKA_TOPIC_LOG_EVENTS}" "Kafka topic does not exist: ${KAFKA_TOPIC_LOG_EVENTS}" \
  topic_exists "${KAFKA_TOPIC_LOG_EVENTS}"
check_cmd "Kafka topic exists: ${KAFKA_TOPIC_LOG_EVENTS_DLQ}" "Kafka topic does not exist: ${KAFKA_TOPIC_LOG_EVENTS_DLQ}" \
  topic_exists "${KAFKA_TOPIC_LOG_EVENTS_DLQ}"
check_cmd "Kafka consumer group exists: ${KAFKA_CONSUMER_GROUP_ID}" "Kafka consumer group does not exist: ${KAFKA_CONSUMER_GROUP_ID}" \
  consumer_group_exists "${KAFKA_CONSUMER_GROUP_ID}"

echo
echo "== OpenSearch Resources =="
check_cmd "OpenSearch index pattern exists: ${OPENSEARCH_INDEX_PATTERN}" "OpenSearch index pattern does not match any index: ${OPENSEARCH_INDEX_PATTERN}" \
  opensearch_index_pattern_exists "${OPENSEARCH_INDEX_PATTERN}"
check_cmd "OpenSearch alias exists: ${OPENSEARCH_READ_ALIAS}" "OpenSearch alias does not exist: ${OPENSEARCH_READ_ALIAS}" \
  opensearch_get "/_alias/${OPENSEARCH_READ_ALIAS}"
check_cmd "OpenSearch alias exists: ${OPENSEARCH_WRITE_ALIAS}" "OpenSearch alias does not exist: ${OPENSEARCH_WRITE_ALIAS}" \
  opensearch_get "/_alias/${OPENSEARCH_WRITE_ALIAS}"
check_cmd "OpenSearch ingest pipeline exists: ${OPENSEARCH_PIPELINE_NAME}" "OpenSearch ingest pipeline does not exist: ${OPENSEARCH_PIPELINE_NAME}" \
  opensearch_get "/_ingest/pipeline/${OPENSEARCH_PIPELINE_NAME}"

echo
echo "== Backend =="
check_http_success "gateway-service" "${GATEWAY_SERVICE_URL}/actuator/health"
check_http_success "log-service" "${LOG_SERVICE_URL}/actuator/health"
check_http_success "event-consumer" "${EVENT_CONSUMER_URL}/actuator/health"
check_http_reachable "gateway route check passed: ${GATEWAY_LOG_SERVICE_ROUTE_PATH}" \
  "gateway route check failed" \
  "${GATEWAY_SERVICE_URL}${GATEWAY_LOG_SERVICE_ROUTE_PATH}"

echo
if [ "${FAILED}" -eq 0 ]; then
  echo "Local environment is ready."
  exit 0
fi

echo "Local environment is not ready."
exit 1
