output "secret_arn" {
  description = "ARN del secreto en Secrets Manager"
  value       = aws_secretsmanager_secret.llm_api_key.arn
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway"
  value       = aws_nat_gateway.main.id
}
