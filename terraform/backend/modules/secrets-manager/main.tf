resource "aws_secretsmanager_secret" "service_env" {
  for_each = toset(var.services)

  name        = "/${var.environment}/${each.key}/env"
  description = "Variables de entorno para el microservicio ${each.key}"

  tags = {
    Environment = var.environment
    Service     = each.key
  }
}

resource "aws_secretsmanager_secret_version" "service_env" {
  for_each = toset(var.services)

  secret_id = aws_secretsmanager_secret.service_env[each.key].id
  secret_string = jsonencode({
    DB_URL       = "jdbc:postgresql://localhost:5432/${each.key}"
    DB_USER      = "change_me"
    DB_PASSWORD  = "change_me"
    RABBITMQ_URL = "amqp://localhost:5672"
  })
}
