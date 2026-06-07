variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (permite acceso al puerto 27017)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas; subnet_ids[0] determina la AZ del volumen EBS"
  type        = list(string)
}

variable "availability_zone" {
  description = "Availability Zone (se infiere de subnet_ids[0] si se omite; requerido con floci)"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI Amazon Linux 2 para la instancia MongoDB"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.medium"
}

variable "volume_size_gb" {
  description = "Tamaño del volumen EBS para los datos de MongoDB en GB"
  type        = number
  default     = 20
}

variable "volume_type" {
  description = "Tipo de volumen EBS"
  type        = string
  default     = "gp3"
}

variable "mongodb_version" {
  description = "Versión mayor de MongoDB a instalar (p. ej. 7.0)"
  type        = string
  default     = "7.0"
}

variable "mongodb_admin_password" {
  description = "Contraseña del usuario admin de MongoDB (se almacena en Secrets Manager)"
  type        = string
  sensitive   = true
}
