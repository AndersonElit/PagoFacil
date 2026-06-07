module "frontend" {
  source       = "../../modules/vercel-project"
  project_name = "pagofacil-staging"
  api_url      = var.api_url
}
