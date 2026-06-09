output "endpoint" {
  description = "Endpoint de conexión a RDS"
  value       = try(aws_db_instance.main[0].endpoint, "")
}

output "port" {
  description = "Puerto de conexión a RDS"
  value       = try(aws_db_instance.main[0].port, null)
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = try(aws_db_instance.main[0].db_name, "")
}

output "identifier" {
  description = "Identificador de la instancia RDS"
  value       = try(aws_db_instance.main[0].identifier, "")
}

output "arn" {
  description = "ARN de la instancia RDS"
  value       = try(aws_db_instance.main[0].arn, "")
}
