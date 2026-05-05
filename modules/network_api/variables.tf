variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "ID de la subred pública para el NAT Gateway"
  type        = string
}

variable "private_subnet_route_table_id" {
  description = "Route table ID de la subred privada para agregar la ruta al NAT Gateway"
  type        = string
}

variable "llm_api_key" {
  description = "Clave API real para OpenAI/Anthropic"
  type        = string
  sensitive   = true
}
