variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC donde se despliega Jenkins"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (regla de entrada para agentes JNLP port 50000)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas; subnet_ids[0] determina la AZ del volumen EBS"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets públicas para el ALB"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI base para la instancia EC2 del controller (Amazon Linux 2023 con Docker disponible vía dnf)"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para el controller Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "volume_size_gb" {
  description = "Tamaño del volumen EBS para JENKINS_HOME en GB"
  type        = number
  default     = 30
}

variable "volume_type" {
  description = "Tipo de volumen EBS"
  type        = string
  default     = "gp3"
}

variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability Zone (se infiere de subnet_ids[0] si se omite; requerido con floci)"
  type        = string
  default     = ""
}

variable "jenkins_image" {
  description = "Imagen Docker del controller (recomendado: imagen propia con JCasC + plugins en ECR)"
  type        = string
  default     = "jenkins/jenkins:lts-jdk21"
}

# --- Integración con EKS (agentes + RBAC) ---

variable "eks_cluster_name" {
  description = "Nombre del cluster EKS donde corren los agentes y se despliega la aplicación"
  type        = string
}

variable "eks_cluster_endpoint" {
  description = "Endpoint del API server de EKS (serverUrl del Kubernetes cloud en JCasC)"
  type        = string
}

variable "shared_library_repo" {
  description = "URL git del repositorio jenkins-shared-library (Global Pipeline Library)"
  type        = string
  default     = ""
}

variable "sonar_url" {
  description = "URL del servidor SonarQube (ej. http://sonarqube:9000)"
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
  description = "Workspace de Slack (subdominio de slack.com)"
  type        = string
  default     = ""
}

variable "slack_token" {
  description = "Token del bot de Slack para el canal #cicd"
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
  description = "ID del proyecto pagofacil-web en Vercel"
  type        = string
  default     = ""
}

variable "gitops_git_username" {
  description = "Usuario git con permiso de push (para bumpImageTag)"
  type        = string
  default     = ""
}

variable "gitops_git_token" {
  description = "Token del usuario git (para bumpImageTag)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "ARN del IAM OIDC provider del cluster EKS (para IRSA del agente)"
  type        = string
}

variable "eks_oidc_issuer_host" {
  description = "Host del OIDC issuer del cluster (issuer sin el prefijo https://), para las condiciones IRSA"
  type        = string
}

variable "agent_namespace" {
  description = "Namespace de Kubernetes donde el controller lanza los pods agente"
  type        = string
  default     = "jenkins"
}

variable "allowed_cidr_blocks" {
  description = "CIDRs con acceso HTTP/HTTPS a la UI de Jenkins vía ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_internal" {
  description = "Si true el ALB es interno (solo accesible desde la VPC)"
  type        = bool
  default     = false
}

variable "attach_ssm_policy" {
  description = "Adjuntar AmazonSSMManagedInstanceCore al rol EC2 (false en Floci: managed policy no existe)"
  type        = bool
  default     = true
}

variable "enable_compute" {
  description = "Crear el cómputo EC2/ELB + access entries EKS + IRSA del agente (false en Floci: no soporta launch templates, ELBv2 ni access entries)"
  type        = bool
  default     = true
}
