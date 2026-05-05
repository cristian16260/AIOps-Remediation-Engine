variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "private_subnets" {
  description = "Subredes privadas para los VPC Endpoints"
  type        = list(string)
}
