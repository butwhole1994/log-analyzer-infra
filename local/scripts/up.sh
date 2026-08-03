#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${LOCAL_DIR}/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-${LOCAL_DIR}/docker-compose.yml}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d "$@"
