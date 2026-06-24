#!/usr/bin/env bash

set -e

KAFKA_CONTAINER_NAME="${KAFKA_CONTAINER_NAME:-log-analyzer-kafka}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"

LOG_EVENTS_TOPIC="${KAFKA_TOPIC_LOG_EVENTS:-log-events}"
LOG_EVENTS_DLQ_TOPIC="${KAFKA_TOPIC_LOG_EVENTS_DLQ:-log-events-dlq}"

PARTITIONS="${KAFKA_TOPIC_PARTITIONS:-3}"
REPLICATION_FACTOR="${KAFKA_TOPIC_REPLICATION_FACTOR:-1}"

echo "Creating Kafka topics..."
echo "Kafka container: ${KAFKA_CONTAINER_NAME}"
echo "Bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"

create_topic_if_not_exists() {
  local topic_name="$1"
  local partitions="$2"
  local replication_factor="$3"

  echo "Checking topic: ${topic_name}"

  if docker exec "${KAFKA_CONTAINER_NAME}" \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --list | grep -q "^${topic_name}$"; then

    echo "Topic already exists: ${topic_name}"
  else
    docker exec "${KAFKA_CONTAINER_NAME}" \
      /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
      --create \
      --topic "${topic_name}" \
      --partitions "${partitions}" \
      --replication-factor "${replication_factor}"

    echo "Topic created: ${topic_name}"
  fi
}

create_topic_if_not_exists "${LOG_EVENTS_TOPIC}" "${PARTITIONS}" "${REPLICATION_FACTOR}"
create_topic_if_not_exists "${LOG_EVENTS_DLQ_TOPIC}" "${PARTITIONS}" "${REPLICATION_FACTOR}"

echo "Kafka topic creation completed."