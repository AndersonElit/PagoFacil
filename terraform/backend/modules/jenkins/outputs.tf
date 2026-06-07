output "jenkins_url" {
  description = "URL de acceso a la UI de Jenkins vía ALB; vacío sin cómputo (Floci)"
  value       = try("http://${aws_lb.jenkins[0].dns_name}", "")
}

output "alb_dns_name" {
  description = "DNS name del ALB de Jenkins; vacío sin cómputo (Floci)"
  value       = try(aws_lb.jenkins[0].dns_name, "")
}

output "agent_role_arn" {
  description = "ARN del IAM role IRSA del agente; vacío sin cómputo (Floci)"
  value       = try(aws_iam_role.jenkins_agent[0].arn, "")
}

output "controller_role_arn" {
  description = "ARN del IAM role de la instancia EC2 del controller (mapeado en el access entry de EKS)"
  value       = aws_iam_role.jenkins_ec2.arn
}

output "ebs_volume_id" {
  description = "ID del volumen EBS que persiste JENKINS_HOME"
  value       = aws_ebs_volume.jenkins_home.id
}

output "ec2_security_group_id" {
  description = "ID del security group de la instancia EC2 Jenkins"
  value       = aws_security_group.jenkins_ec2.id
}
