# Kafka Local Verification

## 목적

MVP3에서 사용하는 Kafka topic과 consumer group을 로컬 환경에서 검증하는 절차를 정리한다.

이 문서는 Kafka topic 생성 여부, 메시지 발행 여부, consumer group 상태, offset 변화를 확인하는 데 한정한다. Kafka producer 구현, consumer 구현, retry/DLQ 처리 로직 구현은 backend work item에서 다룬다.

## 기준 값

아래 값은 `log-analyzer-backend` local profile 기준이다.

### Topic

| Topic | 용도 |
| --- | --- |
| `log-analyzer.dev.log-events` | `log-service`가 로그 이벤트를 발행하는 기본 topic |
| `log-analyzer.dev.log-events-dlq` | `event-consumer` 처리 실패 메시지를 적재하는 DLQ topic |

### Consumer Group

| Consumer Group | 용도 |
| --- | --- |
| `event-consumer` | local profile 기준 `event-consumer` 기본 consumer group |

`event-consumer-local`은 기본값이 아니다. 해당 이름으로 검증하려면 backend 실행 시 `KAFKA_CONSUMER_GROUP_ID=event-consumer-local`을 명시한다.

## 사전 조건

아래 명령은 `local/` 디렉터리에서 실행하는 기준이다.

```bash
cd local
bash scripts/up.sh
bash scripts/create-kafka-topics.sh
```

Kafka UI는 `http://127.0.0.1:18080`에서 확인한다.

전체 Kafka 검증 명령:

```bash
bash scripts/verify-kafka.sh
```

이 스크립트는 topic 목록, topic 상세 정보, topic end offset, consumer group 목록, consumer group 상세 상태를 한 번에 출력한다.

## Topic 목록 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --list'
```

목록에 아래 topic이 모두 표시되어야 한다.

- `log-analyzer.dev.log-events`
- `log-analyzer.dev.log-events-dlq`

## Topic 상세 확인

`log-analyzer.dev.log-events` 상세 정보:

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --topic log-analyzer.dev.log-events'
```

`log-analyzer.dev.log-events-dlq` 상세 정보:

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --topic log-analyzer.dev.log-events-dlq'
```

기본 생성 기준은 partition `3`, replication factor `1`, retention `604800000ms`다.

## Topic End Offset 확인

`kafka-topics.sh --describe`는 partition 구성 확인용이다. 메시지 발행으로 offset이 증가했는지는 `kafka-get-offsets.sh`로 확인한다.

`log-analyzer.dev.log-events` end offset:

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-get-offsets.sh \
    --bootstrap-server kafka:9092 \
    --topic log-analyzer.dev.log-events'
```

`log-analyzer.dev.log-events-dlq` end offset:

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-get-offsets.sh \
    --bootstrap-server kafka:9092 \
    --topic log-analyzer.dev.log-events-dlq'
```

메시지가 발행되면 해당 topic의 partition별 end offset 합계가 증가한다.

## Consumer Group 목록 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server kafka:9092 \
    --list'
```

`event-consumer`가 보이지 않으면 `event-consumer` 애플리케이션이 아직 실행되지 않았거나 아직 메시지를 consume하지 않은 상태일 수 있다.

## Consumer Group 상세 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --group event-consumer'
```

확인 기준:

- `TOPIC`에 `log-analyzer.dev.log-events`가 표시된다.
- `CURRENT-OFFSET`이 consume 완료 offset이다.
- `LOG-END-OFFSET`이 topic의 최신 offset이다.
- `LAG`가 `0`이면 최신 메시지까지 consume한 상태다.

## Kafka UI 확인

Kafka UI 접속:

```text
http://127.0.0.1:18080
```

Topic 확인:

- `Topics` 메뉴에서 `log-analyzer.dev.log-events` topic이 존재하는지 확인한다.
- `Topics` 메뉴에서 `log-analyzer.dev.log-events-dlq` topic이 존재하는지 확인한다.
- topic 상세 화면에서 partition, message count, latest offset을 확인한다.

Message payload 확인:

- `Topics` 메뉴에서 `log-analyzer.dev.log-events`를 연다.
- `Messages` 또는 `Messages browser` 화면으로 이동한다.
- 새 메시지가 보이지 않으면 offset 조회 기준을 latest가 아닌 earliest 또는 beginning으로 변경한다.
- payload에 `id`, `service`, `level`, `message`, `traceId`, `requestId`, `timestamp` 같은 `log-service` 발행 필드가 포함되는지 확인한다.

Consumer group 확인:

- `Consumers` 또는 `Consumer Groups` 메뉴에서 `event-consumer` group을 연다.
- `log-analyzer.dev.log-events` topic의 current offset, end offset, lag을 확인한다.
- `log-service`가 메시지를 발행한 뒤 end offset이 증가하는지 확인한다.
- `event-consumer`가 consume한 뒤 current offset이 증가하고 lag이 감소하는지 확인한다.

## Log Service 발행 후 Consume 확인

검증 흐름:

```text
log-service
  ↓
log-analyzer.dev.log-events
  ↓
event-consumer
  ↓
consumer group: event-consumer
```

절차:

1. `log-service`와 `event-consumer`를 local profile로 실행한다.
2. `log-service`의 로그 이벤트 발행 API인 `POST /api/logs`를 호출한다.
3. Kafka UI 또는 CLI end offset 조회에서 `log-analyzer.dev.log-events`의 offset 증가를 확인한다.
4. `event-consumer` 로그에서 consume 성공 로그를 확인한다.
5. Consumer group 상세 정보에서 `event-consumer`의 `CURRENT-OFFSET` 증가와 `LAG` 감소를 확인한다.

발행 API 호출 예시:

```bash
curl -X POST http://localhost:7020/api/logs \
  -H 'Content-Type: application/json' \
  -d '{
    "serviceName": "local-test-service",
    "level": "INFO",
    "message": "Kafka local verification message",
    "timestamp": "2026-07-01T00:00:00Z",
    "traceId": "trace-local-001",
    "requestId": "request-local-001"
  }'
```

`event-consumer` 성공 로그 예시:

```text
Consumed log event successfully: eventId=..., traceId=..., requestId=..., serviceName=..., level=...
```

## DLQ 적재 확인

DLQ 발생 시 흐름:

```text
event-consumer 처리 실패
  ↓
retry
  ↓
log-analyzer.dev.log-events-dlq
```

확인 절차:

1. `log-analyzer.dev.log-events-dlq` topic이 생성되어 있는지 확인한다.
2. backend에서 DLQ 발행이 가능한 실패 조건을 만든다.
3. Kafka UI의 `log-analyzer.dev.log-events-dlq` topic 메시지 화면에서 payload 적재 여부를 확인한다.
4. CLI end offset 조회로 `log-analyzer.dev.log-events-dlq`의 offset 증가 여부를 확인한다.

DLQ 메시지가 보이지 않으면 실패 조건이 retry 후 DLQ 발행까지 도달했는지 backend 로그를 먼저 확인한다.

## 제외 범위

- Kafka topic 생성 스크립트 자체 변경은 이 작업에서 다루지 않는다.
- backend producer/consumer 코드는 이 작업에서 수정하지 않는다.
- retry/DLQ 처리 로직 구현은 이 작업에서 다루지 않는다.
