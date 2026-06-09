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
  description = "CIDR de la VPC (acceso a los puertos Kafka/ZooKeeper)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas; se necesita una por broker node (AZs distintas)"
  type        = list(string)
}

variable "kafka_version" {
  description = "Versión de Apache Kafka"
  type        = string
  default     = "3.7.x"
}

variable "number_of_broker_nodes" {
  description = "Número de brokers del cluster (debe ser múltiplo del número de AZs)"
  type        = number
  default     = 2
}

variable "broker_instance_type" {
  description = "Tipo de instancia MSK para los brokers"
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_ebs_volume_size" {
  description = "Tamaño del volumen EBS por broker en GB"
  type        = number
  default     = 20
}

variable "enabled" {
  description = "Crear recursos MSK"
  type        = bool
  default     = true
}

variable "floci" {
  description = "Modo floci: cluster mínimo (sin configuration_info, logging_info ni open_monitoring)"
  type        = bool
  default     = false
}
