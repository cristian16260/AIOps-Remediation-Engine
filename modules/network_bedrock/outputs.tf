output "bedrock_vpce_id" {
  description = "ID del VPC Endpoint de Bedrock Runtime"
  value       = aws_vpc_endpoint.bedrock_runtime.id
}
