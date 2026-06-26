docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --create \
    --if-not-exists \
    --topic mvp.log-events \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000
'

docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --create \
    --if-not-exists \
    --topic mvp.log-events-dlq \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000
'