variable "deployment_mode" {
  description = "Estrategia de despliegue: 'api_only' para costo optimizado o 'ha_failover' para alta disponibilidad."
  type        = string
  default     = "api_only"
  
  validation {
    condition     = contains(["api_only", "ha_failover"], var.deployment_mode)
    error_message = "El modo de despliegue debe ser 'api_only' o 'ha_failover'."
  }
}

variable "vpc_id" {
  description = "ID de la VPC base"
  type        = string
}

variable "private_subnets" {
  description = "Subredes privadas para el despliegue de recursos"
  type        = list(string)
}

variable "llm_api_key" {
  description = "Clave API real para OpenAI o Anthropic (Tier 1)"
  type        = string
  sensitive   = true
}
