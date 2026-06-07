variable "project_name" {
  description = "Nombre del proyecto en Vercel"
  type        = string
}

variable "framework" {
  description = "Framework del proyecto (nextjs, create-react-app, etc.)"
  type        = string
  default     = "nextjs"
}

variable "api_url" {
  description = "URL del backend expuesta al frontend"
  type        = string
}
