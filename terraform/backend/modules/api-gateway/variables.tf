variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "cognito_user_pool_endpoint" {
  description = "Endpoint del User Pool de Cognito (issuer JWT)"
  type        = string
}

variable "cognito_client_id" {
  description = "App Client ID de Cognito (audience JWT)"
  type        = string
}

variable "cors_allow_origins" {
  description = "Orígenes permitidos por CORS"
  type        = list(string)
  default     = ["http://localhost:3000"]
}
