output "api_endpoint" {
  description = "URL base del API Gateway"
  value       = module.api_gateway.api_endpoint
}

output "user_pool_id" {
  description = "ID del User Pool de Cognito"
  value       = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  description = "App Client ID de Cognito"
  value       = module.cognito.client_id
}

output "user_pool_endpoint" {
  description = "Endpoint del User Pool de Cognito (issuer JWT para NextAuth y API Gateway)"
  value       = module.cognito.user_pool_endpoint
}

output "ecr_repository_urls" {
  description = "URLs de los repositorios ECR"
  value       = module.ecr.repository_urls
}

# En dev el registry es el de k3d (no ECR). setup-cicd-pipeline.sh lee este output
# para configurar ECR_REGISTRY del JCasC de Jenkins y construir los image tags.
output "ecr_registry" {
  description = "Registry de imágenes de dev (k3d). En floci-net: k3d-pagofacil-registry:5100"
  value       = local.dev_registry
}

output "secret_arns" {
  description = "ARNs de los secrets en Secrets Manager"
  value       = module.secrets_manager.secret_arns
  sensitive   = true
}

output "task_execution_role_arn" {
  description = "ARN del ECS task execution role"
  value       = module.iam.task_execution_role_arn
}

output "task_role_arn" {
  description = "ARN del ECS task role"
  value       = module.iam.task_role_arn
}

# ArgoCD corre en el cluster K3d. La UI se accede con port-forward (no hay LoadBalancer
# en dev). El password inicial del admin se lee del secret argocd-initial-admin-secret.
output "argocd_namespace" {
  description = "Namespace donde quedó instalado ArgoCD en K3d"
  value       = module.argocd.namespace
}

output "argocd_admin_password_cmd" {
  description = "Comando para leer la contraseña inicial del admin de ArgoCD"
  value       = module.argocd.admin_password_cmd
}

output "argocd_port_forward_cmd" {
  description = "Comando para exponer la UI de ArgoCD en https://localhost:8090"
  value       = "kubectl --kubeconfig .kube/config-k3d -n ${module.argocd.namespace} port-forward svc/argocd-server 8090:443"
}

output "kafka_bootstrap_brokers" {
  description = "Bootstrap brokers de Apache Kafka para microservicios como contenedores en floci-net"
  value       = local.kafka_bootstrap_brokers
}

output "kafka_bootstrap_brokers_external" {
  description = "Bootstrap brokers de Apache Kafka accesibles desde el host (CLI/herramientas)"
  value       = local.kafka_bootstrap_brokers_external
}

output "rds_endpoint" {
  description = "Endpoint de conexión a RDS"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "Puerto de conexión a RDS"
  value       = module.rds.port
}

output "rds_db_name" {
  description = "Nombre de la base de datos"
  value       = module.rds.db_name
}

output "rds_arn" {
  description = "ARN de la instancia RDS"
  value       = module.rds.arn
}
