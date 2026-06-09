resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = var.environment == "dev" ? "OFF" : "OPTIONAL"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  # Floci devuelve estos atributos en cero/vacío tras el apply, lo que produce un
  # error "Provider produced inconsistent result" (comprobación en tiempo de apply
  # que ignore_changes NO evita). En el emulador se omite toda la configuración
  # OAuth/token y se crea un client mínimo; en AWS real se configura completa.
  allowed_oauth_flows_user_pool_client = var.emulator ? null : true
  allowed_oauth_flows                  = var.emulator ? null : ["implicit", "code"]
  allowed_oauth_scopes                 = var.emulator ? null : ["email", "openid", "profile"]

  callback_urls = var.emulator ? null : var.callback_urls
  logout_urls   = var.emulator ? null : var.logout_urls

  supported_identity_providers = var.emulator ? null : ["COGNITO"]

  access_token_validity  = var.emulator ? null : 1
  id_token_validity      = var.emulator ? null : 1
  refresh_token_validity = var.emulator ? null : 30

  dynamic "token_validity_units" {
    for_each = var.emulator ? [] : [1]
    content {
      access_token  = "hours"
      id_token      = "hours"
      refresh_token = "days"
    }
  }
}

# CreateUserPoolDomain no está soportado en Floci; se omite en dev con enable_domain = false.
resource "aws_cognito_user_pool_domain" "main" {
  count        = var.enable_domain ? 1 : 0
  domain       = "${var.project_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}
