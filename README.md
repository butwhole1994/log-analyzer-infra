# [Log Analyzer Infra](https://github.com/users/butwhole1994/projects/5?pane=info)

로컬 개발용 인프라를 관리하는 저장소입니다.
`local/` 기준으로 PostgreSQL, Redis, Kafka, OpenSearch를 실행하고 상태를 확인할 수 있습니다.

## 디렉터리 구조

- `local/docker-compose.yml`: 로컬 인프라 컨테이너 정의
- `local/.env`: 로컬 실행용 포트, 계정, 이미지 설정
- `local/postgres/init.sql`: PostgreSQL 초기 스키마 및 시드 데이터
- `local/scripts/create-kafka-topics.sh`: Kafka 토픽 생성 및 확인 스크립트
- `local/opensearch/init.sh`: OpenSearch 템플릿, 파이프라인, 초기 인덱스 생성
- `local/scripts/health-check.sh`: 전체 인프라 헬스체크

## 실행 순서

아래 순서는 `local/` 디렉터리에서 실행하는 기준입니다.
Windows에서는 Git Bash 또는 WSL 같은 Bash 실행 환경이 필요합니다.

1. Docker Desktop이 실행 중인지 확인합니다.
2. `local/.env` 설정을 확인합니다.
3. 인프라를 기동합니다.

```bash
cd local
docker compose --env-file .env -f docker-compose.yml up -d
```

4. PostgreSQL과 Redis가 올라올 때까지 잠시 기다립니다.
5. Kafka 토픽을 생성합니다.

```bash
bash scripts/create-kafka-topics.sh
```

6. OpenSearch 초기 설정을 적용합니다.

```bash
bash opensearch/init.sh
```

7. 전체 상태를 점검합니다.

```bash
bash scripts/health-check.sh
```

## 서비스 연결 정보

`local/.env` 기준 기본 연결 값은 다음과 같습니다.

- PostgreSQL: `127.0.0.1:15432`
- Redis: `127.0.0.1:16379`
- Kafka: `127.0.0.1:19092`
- Kafka UI: `http://127.0.0.1:18080`
- Redis Commander: `http://127.0.0.1:18081`
- OpenSearch: `http://127.0.0.1:19200`
- OpenSearch Dashboards: `http://127.0.0.1:15601`

## 연결 확인 방법

### PostgreSQL

```bash
docker compose --env-file .env -f docker-compose.yml exec -T postgres pg_isready -U admin -d log-analyzer-db
```

정상 응답이 나오면 연결이 된 상태입니다.
필요하면 `psql`로 `select 1;`을 실행해도 됩니다.

### Redis

```bash
docker compose --env-file .env -f docker-compose.yml exec -T redis redis-cli ping
```

응답이 `PONG`이면 정상입니다.

### Kafka

토픽 목록을 확인합니다.

```bash
docker compose --env-file .env -f docker-compose.yml exec -T kafka \
  sh -lc '/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list'
```

또는 `http://127.0.0.1:18080`의 Kafka UI에서 브로커와 토픽 상태를 확인합니다.

### OpenSearch

```bash
curl http://127.0.0.1:19200/_cluster/health
```

`status`가 반환되면 연결이 된 상태입니다.
OpenSearch Dashboards는 `http://127.0.0.1:15601`에서 확인합니다.

## 자주 발생하는 오류

- `port is already allocated`: 이전에 같은 포트를 쓰는 컨테이너가 남아 있습니다. `docker ps`로 확인한 뒤 중지합니다.
- `docker: command not found`: Docker Desktop 또는 Docker CLI가 설치되지 않았습니다.
- `pg_isready` 실패: PostgreSQL이 아직 기동 중이거나 `local/.env`의 계정 정보가 맞지 않습니다.
- Redis가 `PONG`을 반환하지 않음: `redis` 컨테이너가 완전히 뜨기 전이거나 포트 충돌이 있습니다.
- Kafka 토픽이 보이지 않음: `auto-create`가 꺼져 있으므로 `scripts/create-kafka-topics.sh`를 먼저 실행해야 합니다.
- OpenSearch 초기화 실패: OpenSearch가 먼저 준비되지 않았거나 `local/.env`의 보안 설정과 요청 방식이 맞지 않습니다.
- Bash 스크립트 실행 실패: Windows에서 Git Bash 또는 WSL 같은 Bash 실행 환경이 필요합니다.

## 비고

- 이 저장소의 README에는 infra 로컬 실행에 필요한 정보만 적었습니다.
- 백엔드 실행 순서와 Gateway 호출 방법은 backend 저장소 문서를 따로 참고해야 합니다.
