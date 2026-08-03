# MVP3 Kafka Local Verification Requirements

## 검토 결과

요구사항의 방향은 타당하다. MVP3 로컬 검증에서 Kafka topic 생성 여부, 메시지 발행 여부, consumer group 상태, offset 변화 확인 절차를 문서화하는 것은 backend producer/consumer 구현 작업과 분리하기에 적절하다.

단, 대상 Consumer Group의 기본값은 수정이 필요하다. `log-analyzer-backend` local profile 기준 `event-consumer`의 기본 consumer group은 `event-consumer-local`이 아니라 `event-consumer`다. `event-consumer-local`을 사용하려면 backend 실행 시 `KAFKA_CONSUMER_GROUP_ID=event-consumer-local`을 별도로 지정해야 한다.

## 목적

MVP3에서 사용하는 Kafka topic과 consumer group을 로컬 환경에서 검증할 수 있도록 문서를 보완한다.

이 작업의 범위는 Kafka topic 생성 여부, 메시지 발행 여부, consumer group 상태, offset 변화를 확인하는 절차를 정리하는 것이다. Kafka producer 구현, consumer 구현, retry/DLQ 처리 로직은 backend work item에서 다룬다.

## 작업

- MVP3에서 사용하는 Kafka topic 목록을 문서에 정리한다.
- `mvp.log-events` topic 생성 여부 확인 방법을 작성한다.
- `mvp.log-events-dlq` topic 생성 여부 확인 방법을 작성한다.
- topic 상세 정보 확인 명령어를 작성한다.
- Kafka UI에서 topic을 확인하는 방법을 작성한다.
- Kafka UI에서 message payload를 확인하는 방법을 작성한다.
- Kafka UI에서 consumer group을 확인하는 방법을 작성한다.
- consumer group offset 증가 여부를 확인하는 방법을 작성한다.
- CLI로 topic 목록을 확인하는 명령어를 작성한다.
- CLI로 consumer group 목록을 확인하는 명령어를 작성한다.
- CLI로 consumer group 상세 상태를 확인하는 명령어를 작성한다.
- `log-service` 발행 후 `event-consumer` consume 여부를 확인하는 절차를 정리한다.
- DLQ topic에 메시지가 적재되었는지 확인하는 절차를 정리한다.

## 대상 Topic

| Topic | 용도 |
| --- | --- |
| `mvp.log-events` | `log-service`가 로그 이벤트를 발행하는 기본 topic |
| `mvp.log-events-dlq` | `event-consumer` 처리 실패 메시지가 이동하는 DLQ topic |

## 대상 Consumer Group

| Consumer Group | 용도 |
| --- | --- |
| `event-consumer` | local profile 기준 `event-consumer` 기본 consumer group |

`event-consumer-local`은 기본값이 아니다. 해당 이름으로 검증하려면 backend 실행 환경에 `KAFKA_CONSUMER_GROUP_ID=event-consumer-local`을 명시한다.

## Topic 목록 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --list'
```

## Topic 상세 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --topic mvp.log-events'
```

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --topic mvp.log-events-dlq'
```

## Topic End Offset 확인

`kafka-topics.sh --describe`는 partition 구성 확인용이다. 메시지 발행으로 offset이 증가했는지는 `GetOffsetShell`로 확인한다.

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --bootstrap-server kafka:9092 \
    --topic mvp.log-events'
```

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --bootstrap-server kafka:9092 \
    --topic mvp.log-events-dlq'
```

## Consumer Group 목록 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server kafka:9092 \
    --list'
```

## Consumer Group 상세 확인

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server kafka:9092 \
    --describe \
    --group event-consumer'
```

확인 기준:

- `TOPIC`에 `mvp.log-events`가 표시된다.
- `CURRENT-OFFSET`이 consume 완료 offset이다.
- `LOG-END-OFFSET`이 topic의 최신 offset이다.
- `LAG`가 `0`이면 최신 메시지까지 consume한 상태다.

## Kafka UI 확인 기준

- Kafka UI `http://127.0.0.1:18080`에 접속한다.
- `Topics` 메뉴에서 `mvp.log-events` topic이 존재하는지 확인한다.
- `Topics` 메뉴에서 `mvp.log-events-dlq` topic이 존재하는지 확인한다.
- `mvp.log-events` topic의 Messages 화면에서 message payload를 확인한다.
- 새 메시지가 보이지 않으면 offset 조회 기준을 latest가 아닌 earliest 또는 beginning으로 변경한다.
- Consumer Groups 메뉴에서 `event-consumer` group을 확인한다.
- `mvp.log-events` topic의 end offset이 증가하는지 확인한다.
- consume 이후 consumer group의 current offset이 증가하고 lag이 감소하는지 확인한다.
- 실패 메시지가 발생한 경우 `mvp.log-events-dlq` topic에 메시지가 적재되는지 확인한다.

## 검증 흐름

```text
log-service
  ↓
mvp.log-events
  ↓
event-consumer
  ↓
consumer group: event-consumer
```

DLQ 발생 시 흐름은 다음과 같다.

```text
event-consumer 처리 실패
  ↓
retry
  ↓
mvp.log-events-dlq
```

## 완료 조건

- MVP3에서 사용하는 Kafka topic 목록이 문서에 정리되어 있다.
- `mvp.log-events` topic 생성 여부를 CLI로 확인할 수 있다.
- `mvp.log-events-dlq` topic 생성 여부를 CLI로 확인할 수 있다.
- Kafka UI에서 topic과 message payload를 확인하는 방법이 문서화되어 있다.
- Kafka UI에서 consumer group 상태를 확인하는 방법이 문서화되어 있다.
- CLI로 consumer group 목록과 상세 상태를 확인할 수 있다.
- `log-service` 발행 후 `event-consumer` consume 여부를 확인하는 절차가 문서화되어 있다.
- DLQ topic 적재 여부를 확인하는 절차가 문서화되어 있다.
- Kafka topic 생성 스크립트 자체 변경은 이 작업에서 다루지 않는다.
- backend producer/consumer 코드는 이 작업에서 수정하지 않는다.
- retry/DLQ 처리 로직 구현은 이 작업에서 다루지 않는다.
