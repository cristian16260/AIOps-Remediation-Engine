terraform {
  # ==============================================================================
  # 1. GESTIÓN DEL ESTADO REMOTO (S3 + DynamoDB)
  # ------------------------------------------------------------------------------
  # Para producción, descomenta este bloque para guardar el estado en un S3
  # y evitar que dos personas desplieguen a la vez (State Locking).
  # Si lo descomentas, debes cambiar:
  # 1. "mi-bucket-estado-terraform" por el nombre de tu bucket S3 real.
  # 2. "mi-tabla-dynamodb-locks" por el nombre de tu tabla DynamoDB.
  # 3. La región "us-east-1" si tu bucket está en otra región.
  # ==============================================================================
  # backend "s3" {
  #   bucket         = "mi-bucket-estado-terraform"
  #   key            = "aiops-engine/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "mi-tabla-dynamodb-locks"
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project = "AIOps-Remediation-Engine"
      FinOps  = "Modular"
    }
  }
}

# Modulo Core (Siempre se despliega)
module "core" {
  source          = "./modules/core"
  vpc_id          = var.vpc_id
  private_subnets = var.private_subnets
}

# Modulo de Remediación (Lambda)
module "remediation" {
  source          = "./modules/remediation"
  vpc_id          = var.vpc_id
  private_subnets = var.private_subnets
  secret_arn      = module.network_api.secret_arn
}

# Modulo de Red Tier 1 (API Externa)
module "network_api" {
  source           = "./modules/network_api"
  vpc_id           = var.vpc_id
  public_subnet_id = var.private_subnets[0] # TODO: Cambiar por la subred pública real
  private_subnet_route_table_id = "rtb-dummy" # TODO: Cambiar por la tabla de rutas real
  llm_api_key      = var.llm_api_key
  # Siempre se despliega para desarrollo/pruebas de bajo costo
}

# Modulo de Red Tier 2 (Bedrock Fallback)
module "network_bedrock" {
  source = "./modules/network_bedrock"
  count  = var.deployment_mode == "ha_failover" ? 1 : 0
  
  vpc_id          = var.vpc_id
  private_subnets = var.private_subnets
}
