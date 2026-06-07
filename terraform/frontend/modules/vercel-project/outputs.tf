output "project_id" {
  description = "ID del proyecto Vercel"
  value       = vercel_project.this.id
}

output "deployment_url" {
  description = "URL de despliegue del proyecto"
  value       = "https://${vercel_project.this.name}.vercel.app"
}
