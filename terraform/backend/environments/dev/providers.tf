terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Providers Kubernetes/Helm apuntando al cluster K3d local (lo crea floci-start con
# `k3d cluster create pagofacil-dev`). A diferencia de staging/prod (EKS, auth por
# `aws eks get-token`), aquí la autenticación es por certificado de cliente del
# kubeconfig que k3d genera. El cluster debe existir antes de `terraform apply`.
provider "kubernetes" {
  config_path    = "${path.module}/.kube/config-k3d"
  config_context = "k3d-pagofacil-dev"
}

provider "helm" {
  kubernetes {
    config_path    = "${path.module}/.kube/config-k3d"
    config_context = "k3d-pagofacil-dev"
  }
}

# Floci — emulador AWS local (puerto 4566)
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2              = "http://localhost:4566"
    eks              = "http://localhost:4566"
    rds              = "http://localhost:4566"
    s3               = "http://localhost:4566"
    iam              = "http://localhost:4566"
    sts              = "http://localhost:4566"
    cognitoidp       = "http://localhost:4566"
    apigateway       = "http://localhost:4566"
    apigatewayv2     = "http://localhost:4566"
    secretsmanager         = "http://localhost:4566"
    ecr                    = "http://localhost:4566"
    elasticloadbalancing   = "http://localhost:4566"
    elasticloadbalancingv2 = "http://localhost:4566"
    kafka                  = "http://localhost:4566"
    cloudwatchlogs       = "http://localhost:4566"
    ssm                  = "http://localhost:4566"
    autoscaling          = "http://localhost:4566"
    lambda               = "http://localhost:4566"
    events               = "http://localhost:4566"
  }
}

provider "archive" {}
