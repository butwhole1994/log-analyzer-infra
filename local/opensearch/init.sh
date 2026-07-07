#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenSearch initialization script
#
# Purpose:
# - Load local/.env variables
# - Create index template
# - Create ingest pipeline
# - Create initial index
# - Create read/write aliases
#
# Expected project structure:
# local/
#   .env
#   docker-compose.yml
#   opensearch/
#     init.sh
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
# 1. Connection settings
# ------------------------------------------------------------
# Existing .env variables reused:
# - LOCAL_BIND_ADDRESS
# - OPENSEARCH_HOST_PORT
# - OPENSEARCH_DISABLE_SECURITY_PLUGIN
#
# OPENSEARCH_URL can still be passed explicitly if needed.
# Example:
# OPENSEARCH_URL=http://localhost:19200 ./opensearch/init.sh

OPENSEARCH_CLIENT_HOST="${OPENSEARCH_CLIENT_HOST:-${LOCAL_BIND_ADDRESS:-localhost}}"

# 0.0.0.0 is a bind address, not a client access address.
if [ "${OPENSEARCH_CLIENT_HOST}" = "0.0.0.0" ]; then
  OPENSEARCH_CLIENT_HOST="localhost"
fi

OPENSEARCH_SCHEME="${OPENSEARCH_SCHEME:-http}"
OPENSEARCH_HOST_PORT="${OPENSEARCH_HOST_PORT:-9200}"
OPENSEARCH_URL="${OPENSEARCH_URL:-${OPENSEARCH_SCHEME}://${OPENSEARCH_CLIENT_HOST}:${OPENSEARCH_HOST_PORT}}"

# Optional authentication settings.
# Local default has OPENSEARCH_DISABLE_SECURITY_PLUGIN=true, so auth is not used.
OPENSEARCH_USERNAME="${OPENSEARCH_USERNAME:-admin}"
OPENSEARCH_PASSWORD="${OPENSEARCH_PASSWORD:-${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}}"
OPENSEARCH_CURL_INSECURE="${OPENSEARCH_CURL_INSECURE:-false}"

CURL_OPTIONS=(-fs)

if [ "${OPENSEARCH_CURL_INSECURE}" = "true" ]; then
  CURL_OPTIONS+=(-k)
fi

if [ "${OPENSEARCH_DISABLE_SECURITY_PLUGIN:-true}" != "true" ] && [ -n "${OPENSEARCH_PASSWORD}" ]; then
  CURL_OPTIONS+=(-u "${OPENSEARCH_USERNAME}:${OPENSEARCH_PASSWORD}")
fi

# ------------------------------------------------------------
# 2. OpenSearch initialization settings
# ------------------------------------------------------------
# These values are init-script specific defaults.
# Override them by exporting environment variables if needed.

INDEX_TEMPLATE_NAME="${INDEX_TEMPLATE_NAME:-logs-template}"
INDEX_PATTERN="${INDEX_PATTERN:-logs-*}"

INITIAL_INDEX="${INITIAL_INDEX:-logs-local-000001}"
READ_ALIAS="${READ_ALIAS:-logs-read}"
WRITE_ALIAS="${WRITE_ALIAS:-logs-write}"

PIPELINE_NAME="${PIPELINE_NAME:-logs-pipeline}"

NUMBER_OF_SHARDS="${NUMBER_OF_SHARDS:-1}"
NUMBER_OF_REPLICAS="${NUMBER_OF_REPLICAS:-0}"

# ------------------------------------------------------------
# 3. Print settings
# ------------------------------------------------------------
echo "OpenSearch URL: ${OPENSEARCH_URL}"
echo "Index template: ${INDEX_TEMPLATE_NAME}"
echo "Index pattern: ${INDEX_PATTERN}"
echo "Initial index: ${INITIAL_INDEX}"
echo "Read alias: ${READ_ALIAS}"
echo "Write alias: ${WRITE_ALIAS}"
echo "Pipeline: ${PIPELINE_NAME}"
echo "Shards: ${NUMBER_OF_SHARDS}"
echo "Replicas: ${NUMBER_OF_REPLICAS}"

# ------------------------------------------------------------
# 4. Wait for OpenSearch
# ------------------------------------------------------------
echo
echo "Waiting for OpenSearch..."

until curl "${CURL_OPTIONS[@]}" "${OPENSEARCH_URL}/_cluster/health" > /dev/null; do
  echo "OpenSearch is not ready yet..."
  sleep 3
done

echo "OpenSearch is ready."

# ------------------------------------------------------------
# 5. Create index template
# ------------------------------------------------------------
echo
echo "Creating index template..."

curl "${CURL_OPTIONS[@]}" -X PUT "${OPENSEARCH_URL}/_index_template/${INDEX_TEMPLATE_NAME}" \
  -H "Content-Type: application/json" \
  -d "{
    \"index_patterns\": [\"${INDEX_PATTERN}\"],
    \"template\": {
      \"settings\": {
        \"number_of_shards\": ${NUMBER_OF_SHARDS},
        \"number_of_replicas\": ${NUMBER_OF_REPLICAS}
      },
      \"mappings\": {
        \"properties\": {
          \"timestamp\": {
            \"type\": \"date\"
          },
          \"ingestedAt\": {
            \"type\": \"date\"
          },
          \"id\": {
            \"type\": \"keyword\"
          },
          \"service\": {
            \"type\": \"keyword\"
          },
          \"level\": {
            \"type\": \"keyword\"
          },
          \"loggerName\": {
            \"type\": \"keyword\"
          },
          \"threadName\": {
            \"type\": \"keyword\"
          },
          \"message\": {
            \"type\": \"text\"
          },
          \"traceId\": {
            \"type\": \"keyword\"
          },
          \"spanId\": {
            \"type\": \"keyword\"
          },
          \"host\": {
            \"type\": \"keyword\"
          },
          \"method\": {
            \"type\": \"keyword\"
          },
          \"path\": {
            \"type\": \"keyword\"
          },
          \"statusCode\": {
            \"type\": \"integer\"
          },
          \"durationMs\": {
            \"type\": \"long\"
          }
        }
      }
    }
  }"

echo "Index template created."

# ------------------------------------------------------------
# 6. Create ingest pipeline
# ------------------------------------------------------------
echo
echo "Creating ingest pipeline..."

curl "${CURL_OPTIONS[@]}" -X PUT "${OPENSEARCH_URL}/_ingest/pipeline/${PIPELINE_NAME}" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Default ingest pipeline for log events",
    "processors": [
      {
        "set": {
          "field": "ingestedAt",
          "value": "{{_ingest.timestamp}}"
        }
      }
    ]
  }'

echo "Ingest pipeline created."

# ------------------------------------------------------------
# 7. Create initial index with aliases
# ------------------------------------------------------------
echo
echo "Checking initial index..."

if curl "${CURL_OPTIONS[@]}" "${OPENSEARCH_URL}/${INITIAL_INDEX}" > /dev/null; then
  echo "Initial index already exists: ${INITIAL_INDEX}"
else
  echo "Creating initial index with aliases..."

  curl "${CURL_OPTIONS[@]}" -X PUT "${OPENSEARCH_URL}/${INITIAL_INDEX}" \
    -H "Content-Type: application/json" \
    -d "{
      \"aliases\": {
        \"${WRITE_ALIAS}\": {
          \"is_write_index\": true
        },
        \"${READ_ALIAS}\": {}
      }
    }"

  echo "Initial index created: ${INITIAL_INDEX}"
fi

# ------------------------------------------------------------
# 8. Verify result
# ------------------------------------------------------------
echo
echo "Verifying aliases..."

curl "${CURL_OPTIONS[@]}" "${OPENSEARCH_URL}/_cat/aliases?v"

echo
echo "Verifying indices..."

curl "${CURL_OPTIONS[@]}" "${OPENSEARCH_URL}/_cat/indices?v"

echo
echo "OpenSearch initialization completed."
