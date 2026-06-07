output "api_endpoint" {
  description = "URL base del API Gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "authorizer_id" {
  description = "ID del JWT authorizer"
  value       = aws_apigatewayv2_authorizer.cognito_jwt.id
}

output "stage_name" {
  description = "Nombre del stage desplegado"
  value       = aws_apigatewayv2_stage.default.name
}

output "api_id" {
  description = "ID del API Gateway"
  value       = aws_apigatewayv2_api.main.id
}
