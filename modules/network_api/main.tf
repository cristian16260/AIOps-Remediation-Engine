# Elastic IP para el NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "aiops-nat-eip"
    FinOps = "Tier1-Network"
  }
}

# NAT Gateway para dar salida a internet a la Lambda (Tier 1)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_id

  tags = {
    Name = "aiops-nat-gateway"
    FinOps = "Tier1-Network"
  }
}

# Ruta hacia internet por el NAT Gateway para la tabla de enrutamiento privada
resource "aws_route" "private_nat_route" {
  route_table_id         = var.private_subnet_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Secrets Manager para guardar la API Key (Anthropic/OpenAI)
resource "aws_secretsmanager_secret" "llm_api_key" {
  name        = "aiops/llm_api_key"
  description = "API Key para el LLM externo (Tier 1)"

  tags = {
    FinOps = "Tier1-Security"
  }
}

# Se inyecta el valor de la clave API mediante la variable segura
resource "aws_secretsmanager_secret_version" "llm_api_key_value" {
  secret_id     = aws_secretsmanager_secret.llm_api_key.id
  secret_string = var.llm_api_key

  # Ignoramos cambios en Terraform si prefieres actualizar la clave manualmente desde la consola de AWS
  lifecycle {
    ignore_changes = [secret_string]
  }
}
