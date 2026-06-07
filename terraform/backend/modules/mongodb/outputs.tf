output "secret_arn" {
  description = "ARN del secret con las credenciales admin de MongoDB"
  value       = aws_secretsmanager_secret.mongodb_admin.arn
}

output "secret_name" {
  description = "Nombre del secret (para referencia en microservicios)"
  value       = aws_secretsmanager_secret.mongodb_admin.name
}

output "security_group_id" {
  description = "ID del SG de MongoDB (añadir a los microservicios que necesiten acceso)"
  value       = aws_security_group.mongodb.id
}

output "ebs_volume_id" {
  description = "ID del volumen EBS con los datos de MongoDB"
  value       = aws_ebs_volume.mongodb_data.id
}

output "cloudwatch_log_group" {
  description = "Nombre del log group de CloudWatch para MongoDB"
  value       = aws_cloudwatch_log_group.mongodb.name
}
