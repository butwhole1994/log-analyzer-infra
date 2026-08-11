# Support EC2 Runtime

Support EC2는 AWS MVP에서 Kafka와 OpenSearch를 비용 절감 목적으로 직접 운영하는 단일 EC2 인스턴스다.

이 디렉터리는 `local/docker-compose.yml`에서 AWS RDS로 대체되는 PostgreSQL과 MVP 범위 밖인 Redis를 제외하고, Kafka/OpenSearch 운영에 필요한 컨테이너만 분리한 기준이다.

## Services

| 서비스 | 컨테이너 | 기본 포트 | 접근 주체 |
|---|---|---:|---|
| Kafka | `log-analyzer-kafka` | 9092 | `log-service`, `event-consumer` |
| Kafka UI | `log-analyzer-kafka-ui` | 8080 | 관리자 |
| OpenSearch | `log-analyzer-opensearch` | 9200 | `log-service`, `event-consumer` |
| OpenSearch Dashboards | `log-analyzer-opensearch-dashboards` | 5601 | 관리자 |

## EBS Persistence

EC2에 EBS volume을 붙이고 Docker volume 또는 bind mount의 backing path를 EBS 경로로 둔다.

권장 mount 예시:

```text
/data/log-analyzer/kafka
/data/log-analyzer/opensearch
```

이 MVP 구성은 단일 인스턴스이므로 Kafka/OpenSearch의 고가용성을 제공하지 않는다. 장애 복구는 EBS snapshot, Docker Compose 재기동, topic/index 초기화 스크립트 재실행을 기준으로 한다.

## Usage

1. EC2에 Docker와 Docker Compose plugin을 설치한다.
2. `.env.example`을 `.env`로 복사하고 값을 조정한다.
3. EBS mount 경로를 생성한다.
4. Docker Compose를 실행한다.

```bash
docker compose --env-file .env -f docker-compose.yml up -d
```

Kafka topic 초기화는 local 스크립트를 재사용할 수 있다.

```bash
COMPOSE_FILE=aws/support-ec2/docker-compose.yml \
ENV_FILE=aws/support-ec2/.env \
bash local/kafka/create-topics.sh
```

OpenSearch 초기화도 local 스크립트를 재사용할 수 있다.

```bash
ENV_FILE=aws/support-ec2/.env \
OPENSEARCH_URL=http://localhost:9200 \
bash local/opensearch/init.sh
```

## Security Group Policy

Support EC2는 Public Internet에 직접 노출하지 않는다.

| Inbound Source | Port | 목적 |
|---|---:|---|
| ECS services SG | 9092 | Kafka publish/consume |
| ECS services SG | 9200 | OpenSearch index/search |

MVP에서는 Bastion Host와 Public SSH를 사용하지 않는다. Support EC2에는 Public IP를 부여하지 않으며, 포트 `22`, `8080`, `5601`의 인바운드 규칙을 생성하지 않는다.

운영 셸 접속은 AWS Systems Manager Session Manager를 사용한다. Kafka UI와 OpenSearch Dashboards는 Session Manager 포트 포워딩을 통해 관리자 PC의 `localhost:8080`, `localhost:5601`에서 접근한다. 이를 위해 SSM Agent와 `AmazonSSMManagedInstanceCore` 권한이 포함된 EC2 인스턴스 프로파일이 필요하며, Private Subnet에는 NAT Gateway 또는 `ssm`, `ssmmessages`, `ec2messages` VPC Endpoint를 통한 outbound 경로가 필요하다.

## Backend Environment Values

ECS task에는 아래 값을 SSM Parameter Store 또는 Secrets Manager를 통해 주입한다.

```text
KAFKA_BOOTSTRAP_SERVERS=<support-ec2-private-dns-or-ip>:9092
KAFKA_TOPIC_LOG_EVENTS=log-analyzer.dev.log-events
KAFKA_TOPIC_LOG_EVENTS_DLQ=log-analyzer.dev.log-events-dlq
OPENSEARCH_URL=http://<support-ec2-private-dns-or-ip>:9200
OPENSEARCH_READ_TARGET=log-analyzer-dev-logs-read
OPENSEARCH_INDEX_NAME=log-analyzer-dev-logs-write
OPENSEARCH_PIPELINE_NAME=log-analyzer-dev-logs-pipeline
```
