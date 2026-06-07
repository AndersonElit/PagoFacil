output "cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint del API server de Kubernetes"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  description = "ARN del cluster EKS"
  value       = aws_eks_cluster.main.arn
}

output "cluster_ca_certificate" {
  description = "Certificado CA del cluster (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "URL del OIDC issuer (para IRSA); vacío cuando el data plane está desactivado (Floci)"
  value       = try(aws_eks_cluster.main.identity[0].oidc[0].issuer, "")
}

output "oidc_provider_arn" {
  description = "ARN del IAM OIDC provider del cluster (para los roles IRSA); vacío sin data plane"
  value       = try(aws_iam_openid_connect_provider.main[0].arn, "")
}

output "oidc_issuer_host" {
  description = "Host del OIDC issuer (sin https://) para las condiciones de confianza IRSA; vacío sin data plane"
  value       = try(replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", ""), "")
}

output "node_group_arn" {
  description = "ARN del node group; vacío sin data plane"
  value       = try(aws_eks_node_group.main[0].arn, "")
}
