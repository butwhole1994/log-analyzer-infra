variable "project" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "parameters" {
  description = "Non-sensitive configuration stored as SSM String parameters. Keys are paths relative to /{project}/{environment}/."
  type        = map(string)
  default     = {}
}

variable "secret_names" {
  description = "Sensitive values stored in Secrets Manager. This creates secret containers only; values must be set outside Terraform."
  type        = set(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
