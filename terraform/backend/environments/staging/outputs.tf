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

output "ecr_registry" {
  description = "URL base del registry ECR (para docker login y construcción de image tags)"
  value       = try(split("/", values(module.ecr.repository_urls)[0])[0], null)
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

output "jenkins_url" {
  description = "URL de acceso a la UI de Jenkins"
  value       = module.jenkins.jenkins_url
}

output "jenkins_ebs_volume_id" {
  description = "ID del volumen EBS que persiste JENKINS_HOME"
  value       = module.jenkins.ebs_volume_id
}

output "jenkins_agent_role_arn" {
  description = "ARN del IAM role del agente Jenkins (IRSA para pods en EKS)"
  value       = module.jenkins.agent_role_arn
}

output "msk_cluster_arn" {
  description = "ARN del cluster MSK"
  value       = module.msk.cluster_arn
}

output "msk_bootstrap_brokers" {
  description = "Bootstrap brokers Kafka (plaintext)"
  value       = module.msk.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  description = "Bootstrap brokers Kafka (TLS)"
  value       = module.msk.bootstrap_brokers_tls
}

output "msk_access_policy_arn" {
  description = "ARN de la política IAM para adjuntar al task role de los microservicios"
  value       = module.msk.msk_access_policy_arn
}

output "argocd_namespace" {
  description = "Namespace donde quedó instalado ArgoCD"
  value       = module.argocd.namespace
}

output "argocd_admin_password_cmd" {
  description = "Comando para leer la contraseña inicial del admin de ArgoCD"
  value       = module.argocd.admin_password_cmd
}

output "argocd_server_url_cmd" {
  description = "Comando para obtener la URL (LoadBalancer) del argocd-server"
  value       = module.argocd.server_url_cmd
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
