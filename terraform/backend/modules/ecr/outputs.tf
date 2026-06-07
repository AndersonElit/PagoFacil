output "repository_urls" {
  description = "Mapa de service_name => repository_url"
  value       = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}

output "registry_id" {
  description = "ID del registro ECR"
  value       = try(values(aws_ecr_repository.service)[0].registry_id, null)
}
