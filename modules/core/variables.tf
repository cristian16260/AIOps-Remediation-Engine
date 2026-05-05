variable "vpc_id" {
  description = "ID de la VPC donde residirá la EC2 víctima"
  type        = string
}

variable "private_subnets" {
  description = "Lista de subredes privadas"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID para la instancia EC2 (Amazon Linux 2023 recomendado)"
  type        = string
  default     = "ami-0c101f26f147fa7fd" # Update based on region
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para la víctima"
  type        = string
  default     = "t3.micro"
}
