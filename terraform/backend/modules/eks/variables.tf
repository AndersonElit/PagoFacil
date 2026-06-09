variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev/staging/prod)"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de subnets donde se desplegará el cluster"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Tipos de instancia para los nodos"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Número deseado de nodos"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Número mínimo de nodos"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Número máximo de nodos"
  type        = number
  default     = 4
}

variable "attach_managed_policies" {
  description = "Adjuntar políticas administradas de AWS a los roles (false en Floci: no existen managed policies de EKS)"
  type        = bool
  default     = true
}

variable "enable_data_plane" {
  description = "Crear node group + OIDC provider (false en Floci: no soporta CreateNodegroup ni popula el OIDC issuer del cluster)"
  type        = bool
  default     = true
}
