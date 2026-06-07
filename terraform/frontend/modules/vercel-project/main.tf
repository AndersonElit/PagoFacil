# Sin git_repository: Jenkins es el único disparador de despliegues (vercel.json
# tiene "deploymentEnabled": false). Terraform solo provee el proyecto y sus vars.
resource "vercel_project" "this" {
  name      = var.project_name
  framework = var.framework
}

resource "vercel_project_environment_variable" "api_url" {
  project_id = vercel_project.this.id
  key        = "NEXT_PUBLIC_API_URL"
  value      = var.api_url
  target     = ["production", "preview", "development"]
}
