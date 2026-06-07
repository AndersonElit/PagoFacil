variable "vercel_api_token" {
  description = "Token de API de Vercel"
  type        = string
  sensitive   = true
}

variable "vercel_team" {
  description = "Slug del equipo en Vercel (vacío = cuenta personal)"
  type        = string
  default     = ""
}

variable "api_url" {
  description = "URL del backend"
  type        = string
}
