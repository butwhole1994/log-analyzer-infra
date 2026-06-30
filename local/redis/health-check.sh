#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Redis health check script
#
# Purpose:
# - Load local/.env variables
# - Check Redis container connectivity
# - Verify Redis responds with PONG
#
# Expected project structure:
# local/
#   .env
#   docker-compose.yml
#   redis/
#     health-check.sh
# ============================================================

# ------------------------------------------------------------
# 0. Load .env
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${LOCAL_DIR}/.env}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "Warning: .env file not found: ${ENV_FILE}"
fi

# ------------------------------------------------------------
# 1. Redis settings
# ------------------------------------------------------------
REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-redis}"

echo "Checking Redis health..."
echo "Redis container: ${REDIS_CONTAINER_NAME}"

# ------------------------------------------------------------
# 2. Ping Redis
# ------------------------------------------------------------
RESPONSE="$(docker exec "${REDIS_CONTAINER_NAME}" redis-cli ping)"

if [ "${RESPONSE}" = "PONG" ]; then
  echo "Redis is healthy: PONG"
else
  echo "Redis health check failed. Response: ${RESPONSE}"
  exit 1
fi