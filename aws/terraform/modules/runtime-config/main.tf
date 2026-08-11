resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name  = "/${var.project}/${var.environment}/${each.key}"
  type  = "String"
  value = each.value
  tags  = var.tags
}

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_names

  name                    = "/${var.project}/${var.environment}/${each.value}"
  recovery_window_in_days = 7
  tags                    = var.tags
}
