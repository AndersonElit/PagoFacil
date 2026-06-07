module "frontend" {
  source       = "../../modules/vercel-project"
  project_name = "pagofacil-dev"
  api_url      = var.api_url
}
