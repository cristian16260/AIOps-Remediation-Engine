variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "secret_arn" {
  description = "ARN del secreto de Secrets Manager (Tier 1)"
  type        = string
}
