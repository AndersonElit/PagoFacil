output "secret_arns" {
  description = "Mapa de service_name => secret_arn"
  value       = { for k, v in aws_secretsmanager_secret.service_env : k => v.arn }
}

output "secret_names" {
  description = "Mapa de service_name => secret_name"
  value       = { for k, v in aws_secretsmanager_secret.service_env : k => v.name }
}
