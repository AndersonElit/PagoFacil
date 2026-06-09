output "user_pool_id" {
  description = "ID del User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "ARN del User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Endpoint del User Pool (usado como issuer en API Gateway)"
  value       = "https://${aws_cognito_user_pool.main.endpoint}"
}

output "client_id" {
  description = "ID del App Client"
  value       = aws_cognito_user_pool_client.app_client.id
}

output "jwks_uri" {
  description = "URL del JWKS para validación de tokens"
  value       = "https://${aws_cognito_user_pool.main.endpoint}/.well-known/jwks.json"
}
