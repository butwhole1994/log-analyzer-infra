variable "project" { type = string }
variable "environment" { type = string }
variable "service_name" { type = string }
variable "cluster_arn" { type = string }
variable "image" { type = string }
variable "container_port" { type = number }
variable "cpu" { type = number }
variable "memory" { type = number }
variable "desired_count" { type = number }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "execution_role_arn" { type = string }
variable "execution_role_name" { type = string }
variable "task_role_arn" { type = string }

variable "environment_variables" {
  description = "Plain, non-sensitive container environment variables. Do not put credentials here."
  type        = map(string)
  default     = {}
}

variable "value_from" {
  description = "SSM Parameter or Secrets Manager ARNs, keyed by container environment variable name. ECS resolves both through the execution role."
  type        = map(string)
  default     = {}
}

variable "target_group_arn" {
  description = "Optional ALB target group ARN. Omit for worker services."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
