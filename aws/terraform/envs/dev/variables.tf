variable "aws_region" {
  type = string
}

variable "owner" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "execution_role_arn" {
  type = string
}

variable "execution_role_name" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "kafka_bootstrap_servers" {
  type = string
}

variable "opensearch_url" {
  type = string
}

variable "services" {
  type = map(object({
    image              = string
    container_port     = number
    cpu                = number
    memory             = number
    desired_count      = number
    security_group_ids = list(string)
    task_role_arn      = string
    target_group_arn   = optional(string)
  }))
}
