# AWS 및 Terraform 리소스 명명·태그 관리 표준

## 목적

AWS 및 Terraform으로 생성·관리되는 리소스를 일관된 명명 규칙과 태그 정책으로 관리한다. 리소스 이름과 태그만으로 프로젝트, 환경, 서비스, 관리 주체를 식별할 수 있어야 한다.

## 적용 범위

본 규칙은 Terraform으로 관리되는 다음 AWS 리소스에 적용한다.

- ECS Cluster, Service, Task Definition
- ECR Repository
- RDS DB Instance
- EC2 Instance 및 EBS Volume
- ALB, Target Group
- CloudWatch Log Group
- Kafka Topic
- OpenSearch Index, Alias, Ingest Pipeline
- VPC, Subnet, Security Group 등 태그 지원 리소스
- IAM Role, SSM Parameter, Secrets Manager Secret 등 태그 지원 리소스

## 식별자 규칙

| 항목 | 규칙 | 예시 |
|---|---|---|
| 프로젝트 | 소문자와 하이픈(`-`) 사용 | `log-analyzer` |
| 환경 | `dev`, `stg`, `prod` 중 하나 | `dev` |
| 서비스 | 소문자와 하이픈(`-`) 사용 | `gateway-service` |
| 소유자 | 팀 또는 담당자 식별자 | `platform-team` |

환경별 리소스는 반드시 이름 또는 태그에 환경 값을 포함해야 한다. 서비스별 리소스는 반드시 이름 또는 `service` 태그로 서비스명을 식별할 수 있어야 한다.

## 공통 이름 형식

기본 이름 형식은 다음과 같다.

```text
{project}-{env}-{service}-{resource}
```

서비스에 속하지 않는 공유 리소스는 다음 형식을 사용한다.

```text
{project}-{env}-{resource}
```

## 리소스별 이름 규칙

| 리소스 | 이름 형식 | 예시 |
|---|---|---|
| ECS Cluster | `{project}-{env}-cluster` | `log-analyzer-dev-cluster` |
| ECS Service | `{project}-{env}-{service}` | `log-analyzer-dev-gateway-service` |
| ECS Task Definition Family | `{project}-{env}-{service}` | `log-analyzer-dev-log-service` |
| ECR Repository | `{project}/{service}` | `log-analyzer/gateway-service` |
| RDS DB Instance Identifier | `{project}-{env}-postgres` | `log-analyzer-dev-postgres` |
| EC2 Name 태그 | `{project}-{env}-{purpose}` | `log-analyzer-dev-support` |
| EBS Name 태그 | `{project}-{env}-{purpose}-ebs` | `log-analyzer-dev-support-ebs` |
| ALB | `{project}-{env}-alb` | `log-analyzer-dev-alb` |
| ALB Target Group | `{project}-{env}-{service}-tg` | `log-analyzer-dev-gateway-service-tg` |
| Security Group | `{project}-{env}-{purpose}-sg` | `log-analyzer-dev-ecs-task-sg` |
| CloudWatch Log Group | `/aws/ecs/{project}/{env}/{service}` | `/aws/ecs/log-analyzer/dev/gateway-service` |
| Kafka Topic | `{project}.{env}.{event}` | `log-analyzer.dev.log-events` |
| Kafka DLQ Topic | `{project}.{env}.{event}-dlq` | `log-analyzer.dev.log-events-dlq` |
| OpenSearch Index Template | `{project}-{env}-logs-template` | `log-analyzer-dev-logs-template` |
| OpenSearch Index Pattern | `{project}-{env}-logs-*` | `log-analyzer-dev-logs-*` |
| OpenSearch Initial Index | `{project}-{env}-logs-000001` | `log-analyzer-dev-logs-000001` |
| OpenSearch Read Alias | `{project}-{env}-logs-read` | `log-analyzer-dev-logs-read` |
| OpenSearch Write Alias | `{project}-{env}-logs-write` | `log-analyzer-dev-logs-write` |
| OpenSearch Ingest Pipeline | `{project}-{env}-logs-pipeline` | `log-analyzer-dev-logs-pipeline` |
| SSM Parameter | `/{project}/{env}/{category}/{name}` | `/log-analyzer/dev/db/host` |
| Secrets Manager Secret | `/{project}/{env}/{service}/{name}` | `/log-analyzer/dev/log-service/db-password` |

AWS 리소스별 이름 길이 또는 허용 문자 제약으로 전체 형식을 사용할 수 없는 경우, 프로젝트와 환경 식별자는 우선 유지한다.

## 필수 태그

태그를 지원하는 모든 AWS 리소스에는 다음 태그를 적용한다.

| 태그 키 | 값 | 설명 |
|---|---|---|
| `project` | `log-analyzer` | 프로젝트 식별자 |
| `env` | `dev`, `stg`, `prod` | 배포 환경 |
| `owner` | 팀 또는 담당자 식별자 | 리소스 책임 주체 |
| `managed-by` | `terraform` | 관리 도구 식별자 |
| `service` | 서비스명 또는 `platform` | 서비스 또는 공통 인프라 식별자 |

태그 예시는 다음과 같다.

```text
project=log-analyzer
env=dev
owner=platform-team
managed-by=terraform
service=gateway-service
```

VPC, ALB, RDS 등 특정 애플리케이션 서비스에 직접 속하지 않는 공통 인프라는 `service=platform`을 사용한다.

## Terraform 공통 태그 적용 방식

AWS Provider의 `default_tags`를 사용하여 모든 태그 지원 리소스에 공통 태그를 자동 적용한다.

```hcl
provider "aws" {
  default_tags {
    tags = {
      project      = var.project
      env          = var.environment
      owner        = var.owner
      managed-by   = "terraform"
    }
  }
}
```

서비스별 태그는 공통 태그와 병합하여 적용한다.

```hcl
locals {
  common_tags = {
    project      = var.project
    env          = var.environment
    owner        = var.owner
    managed-by   = "terraform"
  }
}

resource "aws_ecs_service" "this" {
  name = "${var.project}-${var.environment}-${var.service_name}"

  tags = merge(local.common_tags, {
    service = var.service_name
  })
}
```

`default_tags`가 적용되지 않거나 개별 태그 지정이 필요한 리소스도 동일한 `locals.common_tags` 기준을 사용해야 한다.

## 애플리케이션 환경 변수

Kafka와 OpenSearch 식별자는 실행 환경 변수로 재정의할 수 있어야 하며, 기본값은 `dev` 명명 규칙을 따른다.

```text
KAFKA_TOPIC_LOG_EVENTS=log-analyzer.dev.log-events
KAFKA_TOPIC_LOG_EVENTS_DLQ=log-analyzer.dev.log-events-dlq
OPENSEARCH_READ_TARGET=log-analyzer-dev-logs-read
OPENSEARCH_INDEX_NAME=log-analyzer-dev-logs-write
OPENSEARCH_PIPELINE_NAME=log-analyzer-dev-logs-pipeline
```

## Terraform 입력 변수

공통 모듈과 환경 구성은 최소한 다음 변수를 제공해야 한다.

```hcl
variable "project" {
  type    = string
  default = "log-analyzer"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment는 dev, stg, prod 중 하나여야 합니다."
  }
}

variable "owner" {
  type = string
}

variable "service_name" {
  type = string
}
```

## 완료 기준

- ECS, ECR, RDS, EC2, ALB, CloudWatch Log Group의 이름 규칙이 문서화되어 있다.
- Kafka Topic과 OpenSearch Index, Alias, Ingest Pipeline의 이름 규칙이 문서화되어 있다.
- 모든 환경은 `dev`, `stg`, `prod` 중 하나로 표준화되어 있다.
- 리소스 이름 또는 태그만으로 프로젝트, 환경, 서비스 및 관리 주체를 식별할 수 있다.
- 태그 지원 AWS 리소스에 `project`, `env`, `owner`, `managed-by`, `service` 태그가 적용된다.
- Terraform Provider의 `default_tags`와 공통 태그 `locals`를 통해 태그 정책을 일관되게 적용한다.
