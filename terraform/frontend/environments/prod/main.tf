module "frontend" {
  source       = "../../modules/vercel-project"
  project_name = "pagofacil-prod"
  api_url      = var.api_url
}
