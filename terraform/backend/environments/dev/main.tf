# Floci tiene una VPC por defecto; la descubrimos en lugar de usar IDs hardcodeados.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  project_name = "pagofacil"
  environment  = "dev"
  services     = ["identity-service", "wallet-service", "fraud-compliance-service", "notification-service", "audit-service", "reporting-projection-service", "integration-service", "report-extraction-service", "report-processing-service"]

  vpc_id     = data.aws_vpc.default.id
  vpc_cidr   = data.aws_vpc.default.cidr_block
  subnet_ids = data.aws_subnets.default.ids

  # Apache Kafka nativo (KRaft) en el VPS. Acceso desde microservicios (K3s pods): VPS_IP:9092.
  # Externo (CLI/herramientas desde el host): VPS_IP:29092.
  kafka_bootstrap_brokers          = "192.168.122.4:9092"
  kafka_bootstrap_brokers_external = "192.168.122.4:29092"

  # Registry de imágenes de dev: Gitea Package Registry (OCI nativo) en el VPS.
  # Jenkins push: docker push 192.168.122.4:3000/pagofacil/<servicio>:<tag>
  # K3s pull: usa imagePullSecrets con credenciales de Gitea.
  gitea_registry = "192.168.122.4:3000/pagofacil"
}

module "iam" {
  source       = "../../modules/iam"
  environment  = local.environment
  project_name = local.project_name
}

module "cognito" {
  source        = "../../modules/cognito"
  environment   = local.environment
  project_name  = local.project_name
  enable_domain = false
  emulator      = true
}

module "api_gateway" {
  source                     = "../../modules/api-gateway"
  environment                = local.environment
  project_name               = local.project_name
  cognito_user_pool_endpoint = module.cognito.user_pool_endpoint
  cognito_client_id          = module.cognito.client_id

  depends_on = [module.cognito]
}

module "secrets_manager" {
  source      = "../../modules/secrets-manager"
  environment = local.environment
  services    = local.services
}

# ECR eliminado en dev: Gitea Package Registry (OCI nativo) reemplaza ECR.
# El módulo terraform/backend/modules/ecr se conserva para staging/prod (AWS ECR real).

# RDS eliminado en dev: PostgreSQL 16 corre como servicio nativo (postgresql.service)
# en el VPS. Conexión directa: 192.168.122.4:5432. Sin Terraform ni floci.
# El módulo terraform/backend/modules/rds se conserva para staging/prod (AWS RDS real).

# MSK eliminado en dev: Kafka nativo (KRaft) en el VPS (192.168.122.4:9092).
# El módulo terraform/backend/modules/msk se conserva para staging/prod (AWS MSK real).

# ArgoCD se instala en K3s nativo del VPS via Helm CLI (vps-setup.sh k3s).
# Los ApplicationSet/AppProject se aplican desde environments/dev/argocd-bootstrap/.
# El módulo terraform/backend/modules/argocd se conserva para staging/prod (EKS real).

# Activa este módulo después de ejecutar report_lambdas_scaffold.py.
# module "reporting_lambdas" {
#   source                  = "../../modules/reporting-lambdas"
#   org                     = local.project_name
#   kafka_topic             = "report.processed"
#   kafka_bootstrap_servers = local.kafka_bootstrap_brokers
#   lambda_runtime          = "python3.12"
#   report_bucket           = "${local.project_name}-reports"
#   aws_endpoint_url        = "http://localhost:4566"
# }
