# MVP3 OpenSearch Local Initialization Requirements

## 검토 결과

요구사항의 방향은 타당하다. MVP3에서 `event-consumer`가 로그 document를 안정적으로 색인하고 `log-service`가 같은 document를 조회하려면 OpenSearch index template, initial index, read/write alias, ingest pipeline을 로컬에서 반복 생성 또는 재확인할 수 있어야 한다.

다만 기존 구현과 비교했을 때 아래 항목은 보정이 필요하다.

- 현재 infra 스크립트 위치는 `local/opensearch/init.sh`이며, `local/scripts/create-opensearch-index.sh`가 이를 호출하는 wrapper다.
- 요구사항의 `local/opensearch/init-opensearch.sh`는 현재 존재하지 않는다. 다음 구현 작업에서는 기존 `init.sh`를 유지하고, 필요한 경우 `init-opensearch.sh`를 호환 wrapper로 추가한다.
- 기존 ingest pipeline은 색인 시각 필드로 `ingestedAt`을 생성한다.
- backend `OpenSearchLogDocument`와 현재 infra mapping 기준에는 `indexedAt`이 없다. `indexedAt`을 새 표준으로 도입하려면 backend DTO, 검색 응답, 문서까지 함께 변경해야 하므로 이번 요구사항에서는 `ingestedAt`을 기준 필드로 사용한다.
- 현재 script는 initial index가 이미 존재해도 alias 상태를 재확인하고 `logs-local-000001` 기준으로 보정한다.
- 현재 script는 template, pipeline을 `PUT`으로 생성하고 alias를 `_aliases` API로 재구성하므로 반복 실행 가능하다.

## 목적

MVP3에서 로그 이벤트를 OpenSearch에 안정적으로 색인하고 조회할 수 있도록 index, alias, ingest pipeline 초기화 스크립트를 정리한다.

이 작업의 범위는 OpenSearch 초기 리소스를 생성하거나 재확인할 수 있는 infra script를 정리하는 것이다. `event-consumer`의 indexing 로직과 backend 검색 API 구현은 backend work item에서 다룬다.

## 작업

- OpenSearch 초기화 스크립트의 위치와 실행 방법을 정리한다.
- 로그 index template 생성 로직을 정리한다.
- 로그 write alias 생성 로직을 정리한다.
- 로그 read alias 생성 로직을 정리한다.
- ingest pipeline 생성 로직을 정리한다.
- local 환경에서 사용할 초기 index 이름을 정리한다.
- index pattern 기준을 문서화한다.
- mapping 필드 기준을 정리한다.
- 이미 생성된 index, alias, pipeline이 있을 경우 중복 실행해도 실패하지 않도록 구성한다.
- OpenSearch 초기화 실패 시 원인을 확인할 수 있도록 출력 메시지를 정리한다.
- 초기화 후 index, alias, index template, ingest pipeline 상태를 확인하는 명령어를 문서화한다.
- OpenSearch Dashboards에서 index pattern과 alias를 확인하는 절차를 정리한다.

## 대상 리소스

| 리소스 | 이름 | 용도 |
| --- | --- | --- |
| index template | `logs-template` | `logs-*` index에 적용할 기본 settings/mapping template |
| initial index | `logs-local-000001` | local 환경 초기 로그 index |
| write alias | `logs-write` | `event-consumer`가 로그 document를 색인할 대상 alias |
| read alias | `logs-read` | `log-service`가 로그 document를 조회할 대상 alias |
| ingest pipeline | `logs-pipeline` | 로그 document 색인 전 처리 pipeline |

## Index Pattern

```text
logs-*
```

## Mapping 기준

아래 필드는 backend `OpenSearchLogDocument`, `OpenSearchLogIndexClient`, `OpenSearchLogSearchClient` 기준과 맞춘다.

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `eventId` | `keyword` | 로그 이벤트 고유 ID |
| `serviceName` | `keyword` | 로그를 발생시킨 서비스명 |
| `level` | `keyword` | 로그 레벨 |
| `message` | `text` | 로그 메시지 본문 |
| `traceId` | `keyword` | trace ID |
| `requestId` | `keyword` | request ID |
| `timestamp` | `date` | 로그 발생 시각 |
| `publishedAt` | `date` | Kafka 발행 또는 consumer 처리 기준 전달 시각 |
| `ingestedAt` | `date` | OpenSearch ingest pipeline이 설정하는 색인 처리 시각 |
| `metadata` | `object` | 추가 로그 정보 |
| `loggerName` | `keyword` | logger 이름 |
| `threadName` | `keyword` | thread 이름 |
| `spanId` | `keyword` | span ID |
| `host` | `keyword` | 로그 발생 host |
| `method` | `keyword` | HTTP method |
| `path` | `keyword` | HTTP path |
| `statusCode` | `integer` | HTTP status code |
| `durationMs` | `long` | 처리 시간 milliseconds |

`indexedAt`은 이번 요구사항의 기준 필드로 사용하지 않는다. 필요 시 별도 backend/infra migration work item으로 다룬다.

## Script 위치

현재 기준 실행 스크립트:

```text
log-analyzer-infra/
└─ local/
   └─ opensearch/
      └─ init.sh
```

현재 wrapper:

```text
log-analyzer-infra/
└─ local/
   └─ scripts/
      └─ create-opensearch-index.sh
```

다음 구현 작업에서 `init-opensearch.sh` 이름이 필요하면 기존 `init.sh`를 깨지 않고 아래 호환 wrapper를 추가한다.

```text
log-analyzer-infra/
└─ local/
   └─ opensearch/
      └─ init-opensearch.sh
```

## 실행 예시

권장 실행:

```bash
cd log-analyzer-infra/local

bash ./opensearch/init.sh
```

wrapper 실행:

```bash
cd log-analyzer-infra/local

bash ./scripts/create-opensearch-index.sh
```

호환 wrapper를 추가하는 경우:

```bash
cd log-analyzer-infra/local

bash ./opensearch/init-opensearch.sh
```

## 초기화 스크립트에서 처리할 항목

### 1. OpenSearch 연결 확인

```http
GET /
GET /_cluster/health
```

연결 실패 시 OpenSearch URL, 보안 plugin 사용 여부, 인증 정보, curl 오류를 확인할 수 있도록 출력한다.

### 2. Index template 생성

```http
PUT /_index_template/logs-template
```

template에는 `logs-*` index pattern, shard/replica 설정, mapping 기준 필드를 포함한다.

### 3. Ingest pipeline 생성

```http
PUT /_ingest/pipeline/logs-pipeline
```

pipeline은 `ingestedAt` 필드를 `{{_ingest.timestamp}}` 값으로 설정한다.

### 4. 초기 index 생성

```http
PUT /logs-local-000001
```

이미 존재하면 실패하지 않고 존재 상태를 출력한다. alias는 다음 단계에서 별도로 재확인한다.

### 5. Alias 생성 또는 재확인

```http
POST /_aliases
```

생성 또는 보정 대상 alias:

```text
logs-write
logs-read
```

`logs-write`는 `logs-local-000001`에 대해 `is_write_index: true`로 설정한다. 이미 index가 존재하지만 alias가 없거나 잘못 연결된 경우 `_aliases` API로 alias를 보정한다.

## Alias 기준

### logs-write

`event-consumer`가 로그 document를 색인할 때 사용하는 alias이다.

```text
event-consumer
  ↓
logs-write
  ↓
logs-local-000001
```

### logs-read

`log-service`가 로그 document를 조회할 때 사용하는 alias이다.

```text
log-service
  ↓
logs-read
  ↓
logs-local-000001
```

## 상태 확인 명령어

### OpenSearch 연결 확인

```bash
curl -X GET http://localhost:19200
```

### Cluster health 확인

```bash
curl -X GET "http://localhost:19200/_cluster/health?pretty"
```

### Index 확인

```bash
curl -X GET "http://localhost:19200/_cat/indices/logs-*?v"
```

### Alias 확인

```bash
curl -X GET "http://localhost:19200/_cat/aliases/logs-*?v"
```

### Index template 확인

```bash
curl -X GET "http://localhost:19200/_index_template/logs-template?pretty"
```

### Ingest pipeline 확인

```bash
curl -X GET "http://localhost:19200/_ingest/pipeline/logs-pipeline?pretty"
```

### Mapping 확인

```bash
curl -X GET "http://localhost:19200/logs-local-000001/_mapping?pretty"
```

## OpenSearch Dashboards 확인 기준

- OpenSearch Dashboards `http://127.0.0.1:15601`에 접속한다.
- Index Management에서 `logs-local-000001` index를 확인한다.
- Index Management에서 `logs-read`, `logs-write` alias를 확인한다.
- Dev Tools에서 `GET logs-*/_search` 조회가 가능한지 확인한다.
- Discover에서 `logs-*` 또는 `logs-read` 기준으로 로그 document를 조회할 수 있는지 확인한다.
- Discover가 index pattern 생성을 요구하면 `logs-*`를 Data view 또는 Index pattern으로 생성한다.

## 완료 조건

- OpenSearch 초기화 스크립트 위치와 실행 방법이 정리되어 있다.
- `logs-template` index template이 생성된다.
- `logs-pipeline` ingest pipeline이 생성된다.
- `logs-local-000001` 초기 index가 생성된다.
- `logs-write` alias가 생성되며 `is_write_index: true`로 연결된다.
- `logs-read` alias가 생성된다.
- 초기화 스크립트를 여러 번 실행해도 치명적인 오류 없이 동작한다.
- 이미 index가 존재하더라도 alias 누락 또는 불일치 상태를 재확인하고 보정할 수 있다.
- index, alias, index template, ingest pipeline 상태를 CLI로 확인할 수 있다.
- OpenSearch Dashboards에서 생성된 index와 alias를 확인할 수 있다.
- `event-consumer` indexing 코드는 이 작업에서 수정하지 않는다.
- `log-service` 검색 API 코드는 이 작업에서 수정하지 않는다.
- index rollover 정책은 이 작업에서 구현하지 않는다.
- ILM 또는 ISM 정책은 이 작업에서 구현하지 않는다.
