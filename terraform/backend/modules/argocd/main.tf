# Instalación de ArgoCD con el chart oficial argo-helm.
# Los providers helm/kubernetes se configuran en el entorno (apuntando al EKS).
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.namespace
  create_namespace = true

  # TLS terminado en el LoadBalancer; el server corre en modo insecure detrás de él.
  values = [yamlencode({
    global = {
      domain = var.argocd_domain
    }
    configs = {
      params = {
        "server.insecure" = true
      }
    }
    server = {
      service = {
        type = var.server_service_type
      }
    }
    # En prod conviene HA; en otros ambientes, instalación mínima.
    controller = {
      replicas = var.environment == "prod" ? 1 : 1
    }
    redis-ha = {
      enabled = var.environment == "prod"
    }
    repoServer = {
      replicas = var.environment == "prod" ? 2 : 1
    }
  })]
}
