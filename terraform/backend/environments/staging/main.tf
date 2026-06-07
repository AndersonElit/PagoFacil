locals {
  environment = "staging"
}

module "iam" {
  source       = "../../modules/iam"
  environment  = local.environment
  project_name = var.project_name
}

module "cognito" {
  source       = "../../modules/cognito"
  environment  = local.environment
  project_name = var.project_name
}

module "api_gateway" {
  source                     = "../../modules/api-gateway"
  environment                = local.environment
  project_name               = var.project_name
  cognito_user_pool_endpoint = module.cognito.user_pool_endpoint
  cognito_client_id          = module.cognito.client_id

  depends_on = [module.cognito]
}

module "secrets_manager" {
  source      = "../../modules/secrets-manager"
  environment = local.environment
  services    = var.services
}

module "ecr" {
  source       = "../../modules/ecr"
  environment  = local.environment
  project_name = var.project_name
  services     = var.services
}

module "eks" {
  source       = "../../modules/eks"
  environment  = local.environment
  project_name = var.project_name
  subnet_ids   = var.subnet_ids
}

module "jenkins" {
  source                = "../../modules/jenkins"
  environment           = local.environment
  project_name          = var.project_name
  vpc_id                = var.vpc_id
  vpc_cidr              = var.vpc_cidr
  subnet_ids            = var.subnet_ids
  public_subnet_ids     = var.public_subnet_ids
  ami_id                = var.ami_id
  aws_region            = var.aws_region
  alb_internal          = true
  eks_cluster_name      = module.eks.cluster_name
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_issuer_host  = module.eks.oidc_issuer_host
  shared_library_repo   = var.shared_library_repo
  sonar_url             = var.sonar_url
  sonar_token           = var.sonar_token
  slack_team            = var.slack_team
  slack_token           = var.slack_token
  vercel_token          = var.vercel_token
  vercel_org_id         = var.vercel_org_id
  vercel_project_id     = var.vercel_project_id
  gitops_git_username   = var.gitops_git_username
  gitops_git_token      = var.gitops_git_token
}

module "msk" {
  source       = "../../modules/msk"
  environment  = local.environment
  project_name = var.project_name
  vpc_id       = var.vpc_id
  vpc_cidr     = var.vpc_cidr
  subnet_ids   = var.subnet_ids
}

module "rds" {
  source                  = "../../modules/rds"
  environment             = local.environment
  project_name            = var.project_name
  subnet_ids              = var.subnet_ids
  vpc_security_group_ids  = var.vpc_security_group_ids
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
}

# ArgoCD (CD por GitOps). Se instala en el cluster EKS de este ambiente; los
# ApplicationSet/AppProject se aplican desde environments/staging/argocd-bootstrap/.
module "argocd" {
  source       = "../../modules/argocd"
  environment  = local.environment
  project_name = var.project_name

  depends_on = [module.eks]
}

# Activa este módulo después de ejecutar report_lambdas_scaffold.py.
# module "reporting_lambdas" {
#   source           = "../../modules/reporting-lambdas"
#   org              = var.project_name
#   kafka_topic      = "report.processed"
#   lambda_runtime   = "python3.12"
#   report_bucket    = "${var.project_name}-reports"
#   aws_endpoint_url = ""
# }
