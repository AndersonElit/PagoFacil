output "cluster_arn" {
  description = "ARN del cluster MSK"
  value       = try(aws_msk_cluster.main[0].arn, "")
}

output "cluster_name" {
  description = "Nombre del cluster MSK"
  value       = try(aws_msk_cluster.main[0].cluster_name, "")
}

output "bootstrap_brokers" {
  description = "Lista de brokers Kafka en texto plano (para conexiones internas en dev)"
  value       = try(aws_msk_cluster.main[0].bootstrap_brokers, "")
}

output "bootstrap_brokers_tls" {
  description = "Lista de brokers Kafka con TLS"
  value       = try(aws_msk_cluster.main[0].bootstrap_brokers_tls, "")
}

output "zookeeper_connect_string" {
  description = "String de conexión a ZooKeeper"
  value       = try(aws_msk_cluster.main[0].zookeeper_connect_string, "")
}

output "security_group_id" {
  description = "ID del SG del cluster MSK (añadir a los microservicios que lo consuman)"
  value       = try(aws_security_group.msk[0].id, "")
}

output "msk_access_policy_arn" {
  description = "ARN de la política IAM para producir/consumir en MSK (adjuntar al task role)"
  value       = try(aws_iam_policy.msk_access[0].arn, "")
}

output "cloudwatch_log_group" {
  description = "Nombre del log group de CloudWatch para los brokers MSK"
  value       = try(aws_cloudwatch_log_group.msk_broker[0].name, "")
}
