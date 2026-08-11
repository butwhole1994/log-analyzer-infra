terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  project     = "log-analyzer"
  environment = "dev"
  tags = {
    project      = local.project
    env          = local.environment
    owner        = var.owner
    managed-by   = "terraform"
    service      = "platform"
  }

  common_value_from = {
    DB_HOST                   = module.runtime_config.parameter_arns["db/host"]
    DB_PORT                   = module.runtime_config.parameter_arns["db/port"]
    DB_NAME                   = module.runtime_config.parameter_arns["db/name"]
    DB_USERNAME               = module.runtime_config.parameter_arns["db/username"]
    DB_PASSWORD               = module.runtime_config.secret_arns["db/password"]
    KAFKA_BOOTSTRAP_SERVERS   = module.runtime_config.parameter_arns["kafka/bootstrap-servers"]
    KAFKA_TOPIC_LOG_EVENTS   = module.runtime_config.parameter_arns["kafka/topic-log-events"]
    KAFKA_TOPIC_LOG_EVENTS_DLQ = module.runtime_config.parameter_arns["kafka/topic-log-events-dlq"]
    OPENSEARCH_URL            = module.runtime_config.parameter_arns["opensearch/url"]
    OPENSEARCH_READ_TARGET    = module.runtime_config.parameter_arns["opensearch/read-target"]
    OPENSEARCH_INDEX_NAME     = module.runtime_config.parameter_arns["opensearch/index-name"]
    OPENSEARCH_PIPELINE_NAME  = module.runtime_config.parameter_arns["opensearch/pipeline-name"]
  }
}

module "runtime_config" {
  source      = "../../modules/runtime-config"
  project     = local.project
  environment = local.environment
  tags        = local.tags

  parameters = {
    "db/host"                    = var.db_host
    "db/port"                    = tostring(var.db_port)
    "db/name"                    = var.db_name
    "db/username"                = var.db_username
    "kafka/bootstrap-servers"    = var.kafka_bootstrap_servers
    "kafka/topic-log-events"     = "log-analyzer.dev.log-events"
    "kafka/topic-log-events-dlq" = "log-analyzer.dev.log-events-dlq"
    "opensearch/url"             = var.opensearch_url
    "opensearch/read-target"     = "log-analyzer-dev-logs-read"
    "opensearch/index-name"      = "log-analyzer-dev-logs-write"
    "opensearch/pipeline-name"   = "log-analyzer-dev-logs-pipeline"
  }

  secret_names = ["db/password"]
}

module "services" {
  for_each = var.services

  source              = "../../modules/ecs-service"
  project             = local.project
  environment         = local.environment
  service_name        = each.key
  cluster_arn         = var.ecs_cluster_arn
  image               = each.value.image
  container_port      = each.value.container_port
  cpu                 = each.value.cpu
  memory              = each.value.memory
  desired_count       = each.value.desired_count
  private_subnet_ids  = var.private_subnet_ids
  security_group_ids  = each.value.security_group_ids
  execution_role_arn  = var.execution_role_arn
  execution_role_name = var.execution_role_name
  task_role_arn       = each.value.task_role_arn
  target_group_arn    = each.value.target_group_arn
  value_from          = local.common_value_from
  tags                = merge(local.tags, { service = each.key })
}
