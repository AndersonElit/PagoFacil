variable "project_name" {
  description = "Prefijo del proyecto"
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (staging/prod)"
  type        = string
}

variable "namespace" {
  description = "Namespace donde se instala ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Versión del chart argo-cd (argo-helm)"
  type        = string
  default     = "7.6.12"
}

variable "argocd_domain" {
  description = "Dominio público de la UI de ArgoCD (informativo si se usa LoadBalancer)"
  type        = string
  default     = "argocd.example.com"
}

variable "server_service_type" {
  description = "Tipo de Service del argocd-server (LoadBalancer expone una URL)"
  type        = string
  default     = "LoadBalancer"
}
