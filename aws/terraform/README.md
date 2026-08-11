# Terraform Layout Plan

이 디렉터리는 AWS MVP 리소스를 Terraform으로 확장하기 위한 기준 위치다.

이 문서는 MVP 환경에서 어떤 AWS 리소스가 몇 개 생성되는지 명확히 설명한다. 백엔드 애플리케이션은 ECS Fargate task로 실행하고, 직접 관리하는 EC2 인스턴스는 Kafka/OpenSearch용 Support EC2 1대로 제한한다.

## MVP에서 실제로 사용하는 실행 단위

MVP 기본값 기준 실행 단위는 다음과 같다.

| 구분 | 개수 | 무엇이 실행되는가 | 운영 접속 대상인가 |
|---|---:|---|---|
| ALB | 1개 | 외부 HTTP 요청을 받는 Load Balancer | 아니오 |
| ECS Cluster | 1개 | Fargate service들을 묶는 논리 단위 | 아니오 |
| ECS Fargate Service | 3개 | `gateway-service`, `log-service`, `event-consumer` | 아니오 |
| ECS Fargate Task | 기본 3개 | 각 service당 task 1개 | 아니오 |
| RDS PostgreSQL | 1개 | PostgreSQL Single-AZ DB instance | 아니오 |
| Support EC2 | 1대 | Kafka, Kafka UI, OpenSearch, OpenSearch Dashboards Docker Compose | 예 |
| EBS Volume | 1개 이상 | Support EC2의 Kafka/OpenSearch 데이터 저장 | EC2에 연결됨 |
| ECR Repository | 3개 권장 | 백엔드 서비스별 Docker image 저장소 | 아니오 |
| CloudWatch Log Group | 3개 이상 | ECS 서비스 로그 저장 | 아니오 |

MVP에서 독립 실행 리소스로 구분해 관리하는 주요 인스턴스성 리소스는 아래 2종류다.

- RDS DB instance 1개
- Support EC2 instance 1대

`gateway-service`, `log-service`, `event-consumer`는 EC2에 직접 배포하지 않고 ECS Fargate task로 실행한다. 이를 통해 서버 운영 부담은 줄이고, ECS 기반 컨테이너 운영 경험은 유지한다.

## Recommended MVP Size

비용 효율적인 MVP 기준 sizing 예시는 다음과 같다. 실제 타입은 AWS region, Free Tier 여부, 성능 요구사항에 맞춰 조정한다.

| 리소스 | MVP 권장값 | 설명 |
|---|---|---|
| ECS `gateway-service` | 0.25 vCPU / 0.5GB, desired count 1 | 외부 API 진입점 |
| ECS `log-service` | 0.25 vCPU / 0.5GB, desired count 1 | 로그 저장/조회 API |
| ECS `event-consumer` | 0.25 vCPU / 0.5GB, desired count 1 | Kafka 이벤트 소비 및 OpenSearch 색인 |
| RDS PostgreSQL | `db.t4g.micro` 또는 `db.t3.micro`, Single-AZ | MVP DB |
| Support EC2 | `t3.small` 이상 권장 | Kafka와 OpenSearch를 같은 인스턴스에서 실행 |
| Support EC2 EBS | gp3 30GB 이상 | Kafka/OpenSearch 데이터 영속화 |
| ALB | 1개 | Public Subnet 배치 |

Kafka와 OpenSearch를 Support EC2 1대에서 함께 실행하므로, 안정적인 데모 환경 기준으로는 `t3.small` 이상을 기본 후보로 둔다. 더 작은 인스턴스 타입은 단기 검증용으로만 고려한다.

## Network Count 기준

MVP 네트워크는 2개 AZ 구성을 기준으로 한다. ALB와 RDS subnet group 구성을 포함해 AWS 표준 배치 구조를 경험할 수 있다.

| 리소스 | 권장 개수 | 설명 |
|---|---:|---|
| VPC | 1개 | 로그 분석기 전용 네트워크 |
| Public Subnet | 2개 | ALB 배치 |
| Private App Subnet | 2개 | ECS Fargate task 배치 |
| Private DB Subnet | 2개 | RDS subnet group |
| Internet Gateway | 1개 | Public Subnet 인터넷 경로 |
| NAT Gateway | 0~1개 | 외부 API 호출이 필요한 경우에만 사용 |

Private Subnet의 outbound 경로는 필요한 AWS 서비스와 외부 API 호출 여부를 기준으로 정한다. MVP에서는 VPC Endpoint 기반 구성을 우선 검토하고, 외부 API 호출이 필요할 때 NAT Gateway 1개를 추가한다.

- VPC Endpoint: ECR API/DKR, S3, CloudWatch Logs, SSM, SSMMessages, EC2Messages
- NAT Gateway 1개: 외부 API 호출 또는 별도 패키지 저장소 접근이 필요한 경우
- ECS image pull, CloudWatch 로그 전송, Session Manager 연결 요구사항을 기준으로 필요한 endpoint를 확정한다.

## Target Resources

Terraform으로 관리할 리소스:

- VPC
- Public Subnet / Private App Subnet / Private DB Subnet
- Internet Gateway
- NAT Gateway 선택 구성
- VPC Endpoint (ECR, S3, CloudWatch Logs, SSM, SSMMessages, EC2Messages)
- Security Group
- ALB / Target Group / Listener
- ECR repositories
- ECS Cluster
- ECS Task Definition
- ECS Service
- CloudWatch Log Group
- RDS PostgreSQL Single-AZ
- Support EC2
- EBS volume for Support EC2
- IAM role / policy
- SSM Parameter Store 또는 Secrets Manager entries
- CloudWatch Alarm / Dashboard

## Proposed Module Boundaries

```text
aws/terraform/
  envs/
    dev/
      main.tf
      variables.tf
      outputs.tf
      terraform.tfvars.example
  modules/
    network/
    security/
    alb/
    ecr/
    ecs-service/
    rds-postgres/
    support-ec2/
    observability/
```

## Service Configuration Inputs

ECS service module은 최소 아래 값을 입력으로 받는다.

| 값 | 설명 |
|---|---|
| `service_name` | `gateway-service`, `log-service`, `event-consumer` |
| `container_image` | ECR image URI |
| `container_port` | backend container port |
| `cpu` | Fargate task CPU |
| `memory` | Fargate task memory |
| `desired_count` | MVP 기본값 1 |
| `environment` | non-secret 환경 변수 |
| `secrets` | SSM 또는 Secrets Manager ARN |
| `security_group_ids` | ECS task SG |
| `subnet_ids` | Private App Subnet |
| `target_group_arn` | ALB에 붙는 서비스만 설정 |

`event-consumer`는 ALB target group에 붙이지 않는다.

## Support EC2 Operations Access

Support EC2 운영 접속의 기본값은 AWS Systems Manager Session Manager다. Bastion Host와 Public SSH는 MVP 구성에 포함하지 않는다.

- Support EC2는 Private Subnet에 배치하고 Public IP를 부여하지 않는다.
- Security Group에는 SSH `22`, Kafka UI `8080`, OpenSearch Dashboards `5601` 인바운드 규칙을 추가하지 않는다.
- EC2 instance profile에는 `AmazonSSMManagedInstanceCore`를 연결한다.
- SSM Agent가 Systems Manager에 연결할 수 있도록 NAT Gateway 또는 `ssm`, `ssmmessages`, `ec2messages` VPC Endpoint를 구성한다.
- Kafka UI와 OpenSearch Dashboards는 Session Manager 포트 포워딩으로 관리자 PC의 localhost에서 접근한다.

## Secret and Parameter Naming

권장 naming:

```text
/log-analyzer/dev/db/host
/log-analyzer/dev/db/port
/log-analyzer/dev/db/name
/log-analyzer/dev/db/username
/log-analyzer/dev/db/password
/log-analyzer/dev/kafka/bootstrap-servers
/log-analyzer/dev/opensearch/url
```

DB password는 Secrets Manager를 우선 사용한다. 단순 MVP 비용 절감을 우선하면 SecureString SSM Parameter Store를 사용할 수 있다.

## CI/CD Contract

GitHub Actions는 다음 순서로 배포한다.

```text
GitHub Actions
  -> AWS OIDC AssumeRole
  -> Docker build
  -> ECR push
  -> ECS task definition render
  -> ECS service deploy
```

필요 IAM 권한은 ECR push, ECS deploy, task definition register, IAM pass role로 제한한다.

## Production Upgrade Path

Terraform module은 MVP에서 Production으로 다음 변경을 흡수할 수 있어야 한다.

| MVP module | Production 변경 |
|---|---|
| `support-ec2` | `msk`, `opensearch-service` module로 대체 |
| `rds-postgres` Single-AZ | Multi-AZ 옵션 활성화 |
| `ecs-service` desired count 1 | desired count 2+, Auto Scaling 추가 |
| `security` Session Manager 기반 운영 접속 | IAM 권한, 접근 감사, VPN 또는 내부 운영 도구 연계 강화 |
| `observability` 최소 알람 | SLO 기반 알람과 대시보드 확장 |
