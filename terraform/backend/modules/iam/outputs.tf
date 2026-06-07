output "task_execution_role_arn" {
  description = "ARN del ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "task_role_arn" {
  description = "ARN del ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "secrets_read_policy_arn" {
  description = "ARN de la política de lectura de Secrets Manager"
  value       = aws_iam_policy.secrets_read.arn
}

output "ecr_pull_policy_arn" {
  description = "ARN de la política de pull de ECR"
  value       = aws_iam_policy.ecr_pull.arn
}
