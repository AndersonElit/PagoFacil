variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "services" {
  description = "Lista de microservicios del proyecto"
  type        = list(string)
}
