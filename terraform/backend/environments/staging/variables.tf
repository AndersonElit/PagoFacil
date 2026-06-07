variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "services" {
  description = "Lista de microservicios del proyecto"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID de la VPC donde se despliega la infraestructura"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas (ECS tasks, RDS)"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets públicas para el ALB de Jenkins"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI base (Amazon Linux 2023) para la instancia EC2 del controller Jenkins"
  type        = string
}

variable "db_name" {
  description = "Nombre de la base de datos inicial"
  type        = string
}

variable "db_username" {
  description = "Usuario administrador de la base de datos"
  type        = string
}

variable "db_password" {
  description = "Contraseña del usuario administrador"
  type        = string
  sensitive   = true
}

variable "vpc_security_group_ids" {
  description = "IDs de security groups con acceso a RDS"
  type        = list(string)
}

variable "shared_library_repo" {
  description = "URL git del repositorio jenkins-shared-library"
  type        = string
}

variable "sonar_url" {
  description = "URL del servidor SonarQube"
  type        = string
}

variable "sonar_token" {
  description = "Token de autenticación de SonarQube"
  type        = string
  sensitive   = true
}

variable "slack_team" {
  description = "Workspace de Slack"
  type        = string
}

variable "slack_token" {
  description = "Token del bot de Slack"
  type        = string
  sensitive   = true
}

variable "vercel_token" {
  description = "Token de servicio de Vercel"
  type        = string
  sensitive   = true
}

variable "vercel_org_id" {
  description = "ID de la organización en Vercel"
  type        = string
}

variable "vercel_project_id" {
  description = "ID del proyecto en Vercel"
  type        = string
}

variable "gitops_git_username" {
  description = "Usuario git para bumpImageTag"
  type        = string
}

variable "gitops_git_token" {
  description = "Token git para bumpImageTag"
  type        = string
  sensitive   = true
}
