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

# Providers Kubernetes/Helm apuntando al cluster K3s nativo en el VPS.
# kubeconfig descargado por base-infrastructure-builder.sh; contexto renombrado a k3s-pagofacil-dev.
provider "kubernetes" {
  config_path    = "${path.module}/.kube/config-k3s"
  config_context = "k3s-pagofacil-dev"
}

provider "helm" {
  kubernetes {
    config_path    = "${path.module}/.kube/config-k3s"
    config_context = "k3s-pagofacil-dev"
  }
}

# Floci — emulador AWS en el VPS (puerto 4566)
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2              = "http://192.168.122.4:4566"
    eks              = "http://192.168.122.4:4566"
    rds              = "http://192.168.122.4:4566"
    s3               = "http://192.168.122.4:4566"
    iam              = "http://192.168.122.4:4566"
    sts              = "http://192.168.122.4:4566"
    cognitoidp       = "http://192.168.122.4:4566"
    apigateway       = "http://192.168.122.4:4566"
    apigatewayv2     = "http://192.168.122.4:4566"
    secretsmanager         = "http://192.168.122.4:4566"
    ecr                    = "http://192.168.122.4:4566"
    elasticloadbalancing   = "http://192.168.122.4:4566"
    elasticloadbalancingv2 = "http://192.168.122.4:4566"
    kafka                  = "http://192.168.122.4:4566"
    cloudwatchlogs       = "http://192.168.122.4:4566"
    ssm                  = "http://192.168.122.4:4566"
    autoscaling          = "http://192.168.122.4:4566"
    lambda               = "http://192.168.122.4:4566"
    events               = "http://192.168.122.4:4566"
  }
}

provider "archive" {}
