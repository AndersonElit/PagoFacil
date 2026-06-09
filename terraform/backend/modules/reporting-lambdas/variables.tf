variable "org" {
  type    = string
  default = "pagofacil"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# floci en dev (http://VPS_IP:4566); vacío en staging/prod => AWS real.
# En dev, sobreescribir con: TF_VAR_aws_endpoint_url=http://<VPS_IP>:4566 terraform apply
variable "aws_endpoint_url" {
  type    = string
  default = "http://localhost:4566"
}

variable "report_bucket" {
  type    = string
  default = "pagofacil-reports"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "kafka_bootstrap_servers" {
  type    = string
  default = "kafka:9092"
}

variable "kafka_topic" {
  type    = string
  default = "report.processed"
}
