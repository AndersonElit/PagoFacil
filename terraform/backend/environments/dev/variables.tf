variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID de la VPC (floci: valor de prueba)"
  type        = string
  default     = "vpc-00000000"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_ids" {
  description = "Subnets privadas (floci: valores de prueba)"
  type        = list(string)
  default     = ["subnet-00000001", "subnet-00000002"]
}

variable "public_subnet_ids" {
  description = "Subnets públicas para el ALB (floci: mismas que privadas)"
  type        = list(string)
  default     = ["subnet-00000001", "subnet-00000002"]
}

variable "ami_id" {
  description = "AMI base del controller Jenkins (floci: valor de prueba)"
  type        = string
  default     = "ami-00000000"
}

variable "availability_zone" {
  description = "Availability Zone (floci: valor de prueba)"
  type        = string
  default     = "us-east-1a"
}

variable "db_name" {
  description = "Nombre de la base de datos inicial (floci: valor de prueba)"
  type        = string
  default     = "pagofacil_dev"
}

variable "db_username" {
  description = "Usuario administrador de la base de datos (floci: valor de prueba)"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Contraseña del usuario administrador (floci: valor de prueba)"
  type        = string
  default     = "changeme123"
  sensitive   = true
}

variable "vpc_security_group_ids" {
  description = "IDs de security groups con acceso a RDS (floci: valor de prueba)"
  type        = list(string)
  default     = ["sg-00000000"]
}

variable "shared_library_repo" {
  description = "URL git del repositorio jenkins-shared-library"
  type        = string
  default     = ""
}

variable "sonar_url" {
  description = "URL del servidor SonarQube"
  type        = string
  default     = ""
}

variable "sonar_token" {
  description = "Token de autenticación de SonarQube"
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_team" {
  description = "Workspace de Slack"
  type        = string
  default     = ""
}

variable "slack_token" {
  description = "Token del bot de Slack"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vercel_token" {
  description = "Token de servicio de Vercel"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vercel_org_id" {
  description = "ID de la organización en Vercel"
  type        = string
  default     = ""
}

variable "vercel_project_id" {
  description = "ID del proyecto en Vercel"
  type        = string
  default     = ""
}

variable "gitops_git_username" {
  description = "Usuario git para bumpImageTag"
  type        = string
  default     = ""
}

variable "gitops_git_token" {
  description = "Token git para bumpImageTag"
  type        = string
  sensitive   = true
  default     = ""
}
