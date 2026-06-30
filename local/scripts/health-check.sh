#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Local infrastructure health check
#
# Purpose:
# - Load local/.env variables
# - Use docker compose to reach postgres, redis, kafka, and opensearch
# - Fail fast with clear output when any dependency is unhealthy
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${LOCAL_DIR}/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-${LOCAL_DIR}/docker-compose.yml}"

to_docker_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "${path}"
  else
    printf '%s' "${path}"
  fi
}

COMPOSE_ENV_FILE="$(to_docker_path "${ENV_FILE}")"
COMPOSE_FILE_PATH="$(to_docker_path "${COMPOSE_FILE}")"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker command not found." >&2
  exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: .env file not found: ${ENV_FILE}" >&2
  exit 1
fi

if [ ! -f "${COMPOSE_FILE}" ]; then
  echo "Error: docker compose file not found: ${COMPOSE_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

COMPOSE_CMD=(docker compose --env-file "${COMPOSE_ENV_FILE}" -f "${COMPOSE_FILE_PATH}")
if [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
  COMPOSE_CMD+=(--project-name "${COMPOSE_PROJECT_NAME}")
fi

run_compose_exec() {
  local service="$1"
  shift
  MSYS_NO_PATHCONV=1 "${COMPOSE_CMD[@]}" exec -T "${service}" "$@"
}

check_service() {
  local service="$1"
  shift
  printf 'Checking %-10s ... ' "${service}"
  if "$@" >/dev/null; then
    echo "OK"
  else
    echo "FAILED"
    return 1
  fi
}

echo "Using compose file: ${COMPOSE_FILE}"
echo "Using env file: ${ENV_FILE}"
echo "Compose project: ${COMPOSE_PROJECT_NAME:-default}"
echo

check_service "postgres" run_compose_exec "postgres" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
check_service "redis" run_compose_exec "redis" redis-cli ping

KAFKA_SERVICE="${KAFKA_SERVICE:-kafka}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-${KAFKA_SERVICE}:${KAFKA_INTERNAL_PORT}}"
check_service "kafka" run_compose_exec "${KAFKA_SERVICE}" sh -lc '/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server "$1"' sh "${KAFKA_BOOTSTRAP_SERVER}"

OPENSEARCH_CURL=(curl -fs)
if [ "${OPENSEARCH_CURL_INSECURE:-false}" = "true" ]; then
  OPENSEARCH_CURL+=(-k)
fi
if [ "${OPENSEARCH_DISABLE_SECURITY_PLUGIN:-true}" != "true" ] && [ -n "${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}" ]; then
  OPENSEARCH_USERNAME="${OPENSEARCH_USERNAME:-admin}"
  OPENSEARCH_CURL+=(-u "${OPENSEARCH_USERNAME}:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}")
fi
OPENSEARCH_CURL+=("http://localhost:${OPENSEARCH_CONTAINER_PORT}/_cluster/health")
check_service "opensearch" run_compose_exec "opensearch" "${OPENSEARCH_CURL[@]}"

echo
echo "All local infrastructure services are healthy."
