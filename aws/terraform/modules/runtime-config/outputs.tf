output "parameter_arns" {
  description = "SSM Parameter ARNs, keyed by their relative path. Use these in ECS container definition secrets.valueFrom."
  value       = { for key, parameter in aws_ssm_parameter.this : key => parameter.arn }
}

output "secret_arns" {
  description = "Secrets Manager ARNs, keyed by their relative path."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}
