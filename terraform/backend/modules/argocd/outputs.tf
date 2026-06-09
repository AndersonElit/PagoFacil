output "namespace" {
  description = "Namespace donde quedó instalado ArgoCD"
  value       = helm_release.argocd.namespace
}

output "release_name" {
  description = "Nombre del Helm release de ArgoCD"
  value       = helm_release.argocd.name
}

output "admin_password_cmd" {
  description = "Comando para leer la contraseña inicial del admin de ArgoCD"
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "server_url_cmd" {
  description = "Comando para obtener la URL (hostname del LoadBalancer) del argocd-server"
  value       = "kubectl -n ${helm_release.argocd.namespace} get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
