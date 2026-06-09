variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de subnets para el DB subnet group"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "IDs de security groups con acceso a RDS"
  type        = list(string)
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

variable "engine_version" {
  description = "Versión del motor PostgreSQL"
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = "Tipo de instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Almacenamiento asignado en GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Habilitar despliegue Multi-AZ"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Proteger la instancia contra eliminación accidental"
  type        = bool
  default     = false
}

variable "enabled" {
  description = "Crear recursos RDS"
  type        = bool
  default     = true
}

variable "floci" {
  description = "Modo floci: omite subnet group y red no soportados; crea solo el DB instance"
  type        = bool
  default     = false
}
