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
  services     = []

  vpc_id     = data.aws_vpc.default.id
  vpc_cidr   = data.aws_vpc.default.cidr_block
  subnet_ids = data.aws_subnets.default.ids

  # Apache Kafka standalone (KRaft) que levanta floci-start en floci-net (no MSK).
  # Interno: para microservicios como contenedores en floci-net. Externo: desde el host.
  kafka_bootstrap_brokers          = "pagofacil-kafka-dev:9092"
  kafka_bootstrap_brokers_external = "localhost:29092"

  # Registry de imágenes de dev: el que crea k3d (`--registry-create`). Reemplaza al
  # ECR emulado de floci (cuyo pull de capas es poco fiable). Jenkins/Kaniko empuja
  # aquí y K3d hace pull desde aquí. Interno a floci-net; el host lo ve en localhost:5100.
  dev_registry = "k3d-pagofacil-registry:5100"
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

module "ecr" {
  source       = "../../modules/ecr"
  environment  = local.environment
  project_name = local.project_name
  services     = local.services
}

# En dev NO se usa EKS (módulo eks): el plano de cómputo real es el cluster K3d que
# levanta floci-start (pagofacil-dev en floci-net). Tampoco se usa el módulo jenkins
# (controller EC2 + agentes EKS): en dev el controller Jenkins corre como contenedor
# en floci-net y lanza agentes como pods en K3d (lo configura setup-cicd-pipeline.sh).
#
# ArgoCD (CD por GitOps) se instala en el cluster K3d vía Helm. En dev el server se
# expone como NodePort (en EKS sería LoadBalancer); se accede con kubectl port-forward.
# Los ApplicationSet/AppProject se aplican desde environments/dev/argocd-bootstrap/.
module "argocd" {
  source              = "../../modules/argocd"
  environment         = local.environment
  project_name        = local.project_name
  server_service_type = "NodePort"
  argocd_domain       = "localhost"
}

# MSK desactivado en dev: floci deja el cluster en estado CREATING para siempre y el
# provider de AWS crashea al leerlo (nil pointer en kafka/cluster.go). Kafka local lo
# da el contenedor Apache Kafka standalone (pagofacil-kafka-dev en floci-net, KRaft)
# que levanta floci-start; los microservicios apuntan a local.kafka_bootstrap_brokers.
# El módulo queda reservado para staging/prod (AWS real).
module "msk" {
  source       = "../../modules/msk"
  environment  = local.environment
  project_name = local.project_name
  vpc_id       = local.vpc_id
  vpc_cidr     = local.vpc_cidr
  subnet_ids   = local.subnet_ids
  enabled      = false
}

# Floci levanta un contenedor PostgreSQL real (postgres:16-alpine) y proxya TCP
# en un puerto del rango 7001-7099 (no 5432): leerlo del output rds_endpoint/rds_port.
# vpc_security_group_ids vacío en dev: el SG no aplica al proxy TCP de floci y
# evitamos referenciar el sg-00000000 de prueba.
module "rds" {
  source                 = "../../modules/rds"
  environment            = local.environment
  project_name           = local.project_name
  subnet_ids             = local.subnet_ids
  vpc_security_group_ids = []
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  enabled                = true
  floci                  = true
}

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
