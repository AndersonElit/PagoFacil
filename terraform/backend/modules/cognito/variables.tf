variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "callback_urls" {
  description = "URLs de callback OAuth2"
  type        = list(string)
  default     = ["http://localhost:3000/api/auth/callback/cognito"]
}

variable "logout_urls" {
  description = "URLs de logout OAuth2"
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "enable_domain" {
  description = "Crear el dominio del User Pool (false en Floci: CreateUserPoolDomain no soportado)"
  type        = bool
  default     = true
}

variable "emulator" {
  description = "Crear un app client mínimo sin OAuth/token config (true en Floci: devuelve atributos inconsistentes tras el apply)"
  type        = bool
  default     = false
}
