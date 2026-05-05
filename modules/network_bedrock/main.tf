# Security Group para los VPC Endpoints
resource "aws_security_group" "bedrock_vpce_sg" {
  name        = "aiops-bedrock-vpce-sg"
  description = "Permitir trafico interno de Lambda hacia Bedrock"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] # Ajustar al CIDR de la VPC en prod
    description = "HTTPS desde la VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    FinOps = "Tier2-Network"
  }
}

# VPC Endpoint para Bedrock (Runtime - para inferencia)
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.us-east-1.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnets
  security_group_ids  = [aws_security_group.bedrock_vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name   = "aiops-bedrock-runtime-vpce"
    FinOps = "Tier2-Network"
  }
}
