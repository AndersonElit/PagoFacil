output "api_endpoint" {
  description = "URL base del API Gateway (floci)"
  value       = module.api_gateway.api_endpoint
}

output "user_pool_id" {
  description = "ID del User Pool de Cognito (floci)"
  value       = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  description = "App Client ID de Cognito (floci)"
  value       = module.cognito.client_id
}

output "user_pool_endpoint" {
  description = "Endpoint del User Pool de Cognito (issuer JWT para NextAuth y API Gateway)"
  value       = module.cognito.user_pool_endpoint
}

# Registry de imágenes: Gitea Package Registry (OCI nativo) en el VPS.
# setup-cicd-pipeline.sh lee este output para configurar GITEA_REGISTRY en Jenkins.
output "gitea_registry" {
  description = "Registry de imágenes de dev (Gitea Package Registry en VPS). Formato: <VPS_IP>:3000/<org>"
  value       = local.gitea_registry
}

output "secret_arns" {
  description = "ARNs de los secrets en Secrets Manager (floci)"
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

# ArgoCD se instaló via Helm en K3s nativo (vps-setup.sh k3s).
# UI: http://<VPS_IP>:30080  |  HTTPS: http://<VPS_IP>:30443
# Password admin: kubectl --kubeconfig ~/.kube/config-k3s-vps \
#   get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
output "argocd_ui_url" {
  description = "URL de la UI de ArgoCD en K3s (NodePort)"
  value       = "http://192.168.122.4:30080"
}

output "kafka_bootstrap_brokers" {
  description = "Bootstrap brokers de Kafka nativo en VPS (para microservicios en K3s)"
  value       = local.kafka_bootstrap_brokers
}

output "kafka_bootstrap_brokers_external" {
  description = "Bootstrap brokers de Kafka accesibles desde el host"
  value       = local.kafka_bootstrap_brokers_external
}

# PostgreSQL nativo en VPS: acceder directamente via VPS_IP:5432
# Sin módulo Terraform — las BDs se crean con init-databases.sh apuntando al VPS.
output "postgres_host" {
  description = "Host de PostgreSQL nativo en VPS (no gestionado por Terraform)"
  value       = "192.168.122.4"
}

output "postgres_port" {
  description = "Puerto de PostgreSQL nativo en VPS"
  value       = 5432
}
