---
name: terraform-modular-finops
description: Design and implement modular Terraform infrastructure with cost optimization (FinOps) strategies. Use when building reusable modules, managing multi-tier deployments, controlling costs through deployment modes, and applying IaC best practices. Based on HashiCorp official guidelines and AWS standards.
license: Cristian Custom
---

# Terraform Modular + AWS FinOps

## When to use this skill

Use this skill when:
- Designing modular Terraform structures
- Creating reusable infrastructure modules
- Implementing multi-tier deployments (dev, staging, prod)
- Managing infrastructure costs with conditional resources
- Applying IaC best practices across teams
- Setting up deployment pipelines with Terraform
- Versioning and publishing modules

## How to use this skill

### 1. Module Structure (Best Practice)

Create composable, reusable modules:

```
terraform-aws-project/
├── modules/
│   ├── vpc/
│   │   ├── main.tf              # VPC, subnets, gateways
│   │   ├── variables.tf          # Input variables
│   │   ├── outputs.tf            # Export values
│   │   ├── versions.tf           # Provider requirements
│   │   └── README.md
│   │
│   ├── lambda/
│   │   ├── main.tf              # Lambda function, IAM, env vars
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md
│   │
│   ├── networking/
│   │   ├── security_groups.tf
│   │   ├── nat_gateway.tf
│   │   ├── vpc_endpoints.tf
│   │   └── ...
│   │
│   └── observability/
│       ├── cloudwatch.tf
│       ├── alarms.tf
│       └── ...
│
├── environments/
│   ├── dev/
│   │   ├── main.tf              # Root config (calls modules)
│   │   ├── terraform.tfvars      # Dev-specific values
│   │   └── backend.tf
│   │
│   ├── staging/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   │
│   └── prod/
│       ├── main.tf
│       ├── terraform.tfvars
│       └── backend.tf
│
├── main.tf                       # Root orchestrator (optional)
├── variables.tf                  # Global variables
├── outputs.tf
├── versions.tf
├── .terraform-docs.yaml
└── README.md
```

---

### 2. Modular Module Design

#### Bad: Monolithic module
```hcl
# ❌ NOT RECOMMENDED: Single 500-line module
module "everything" {
  source = "./modules/everything"
  
  # 50+ variables needed
  vpc_cidr = "10.0.0.0/16"
  vpc_name = "my-vpc"
  ec2_instance_type = "t3.medium"
  lambda_memory = 256
  ...
}
```

#### Good: Composable modules
```hcl
# ✅ RECOMMENDED: Small, single-purpose modules

# Module 1: VPC (network foundation)
module "vpc" {
  source = "./modules/vpc"
  
  name              = "production-vpc"
  cidr              = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  tags = {
    Environment = "production"
    Project     = "aIOps"
  }
}

# Module 2: Lambda (compute)
module "lambda_aIOps" {
  source = "./modules/lambda"
  
  function_name = "aIOps-remediation-engine"
  handler       = "handler.main"
  runtime       = "python3.11"
  memory        = var.deployment_mode == "ha_failover" ? 1024 : 512
  timeout       = 30
  
  environment_variables = {
    LLM_TIER_1     = "openai"
    LLM_TIER_2     = "bedrock"
    CIRCUIT_BREAKER_TABLE = aws_dynamodb_table.circuit_status.name
  }
  
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [module.vpc.lambda_security_group_id]
  
  tags = local.common_tags
}

# Module 3: Network Tier 1 (API External)
module "network_tier1_api" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  source = "./modules/network_api"
  
  vpc_id                  = module.vpc.id
  lambda_security_group   = module.lambda_aIOps.security_group_id
  secrets_manager_enabled = true
  
  tags = local.common_tags
}

# Module 4: Network Tier 2 (Bedrock)
module "network_tier2_bedrock" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  source = "./modules/network_bedrock"
  
  vpc_id               = module.vpc.id
  lambda_role_arn      = module.lambda_aIOps.execution_role_arn
  bedrock_enabled      = true
  
  tags = local.common_tags
}

# Module 5: Monitoring (essential for all)
module "observability" {
  source = "./modules/observability"
  
  lambda_function_name = module.lambda_aIOps.function_name
  enable_detailed_monitoring = var.deployment_mode == "ha_failover"
  circuit_breaker_table = aws_dynamodb_table.circuit_status.name
  
  tags = local.common_tags
}
```

---

### 3. Input Variables + Type Safety

Define variables strictly:

```hcl
# variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "deployment_mode" {
  description = "Deployment mode: api_only (cost-optimized) or ha_failover (high availability)"
  type        = string
  default     = "api_only"
  
  validation {
    condition     = contains(["api_only", "bedrock_only", "ha_failover"], var.deployment_mode)
    error_message = "Mode must be api_only, bedrock_only, or ha_failover."
  }
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory >= 128 && var.lambda_memory <= 10240
    error_message = "Memory must be between 128 and 10240 MB."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    CostCenter  = "Engineering"
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway (costs ~$45/month)"
  type        = bool
  default     = true
}
```

---

### 4. Conditional Resources (FinOps)

Control costs with `count` based on deployment mode:

```hcl
# main.tf - Conditional resource creation

# ❌ NAT Gateway: $45/month × 1 = $45/month
resource "aws_nat_gateway" "main" {
  count           = var.enable_nat_gateway ? 1 : 0
  allocation_id   = aws_eip.nat[0].id
  subnet_id       = aws_subnet.public[0].id
  depends_on      = [aws_internet_gateway.main]
  
  tags = merge(local.common_tags, {
    Cost = "$45/month"
  })
}

# ❌ VPC Endpoints (Bedrock): $7/month × 2 = $14/month
resource "aws_vpc_endpoint" "bedrock" {
  count             = var.deployment_mode == "ha_failover" ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.bedrock"
  vpc_endpoint_type = "Interface"
  
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  
  tags = merge(local.common_tags, {
    Cost = "$7/month"
  })
}

# ❌ Site-to-Site VPN (On-Premise): $36/month
resource "aws_vpn_connection" "on_premise" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  type                = "ipsec.1"
  customer_gateway_id = aws_customer_gateway.on_premise[0].id
  vpn_gateway_id      = aws_vpn_gateway.main[0].id
  
  tags = merge(local.common_tags, {
    Cost = "$36/month"
  })
}

# Dynamic Lambda memory based on mode
resource "aws_lambda_function" "aIOps_engine" {
  # ... other config ...
  
  memory_size = var.deployment_mode == "ha_failover" ? 1024 : 512
  
  # Tier 1 needs more timeout (external API)
  # Tier 2/3 can be faster (internal)
  timeout = var.deployment_mode == "api_only" ? 15 : 30
  
  tags = local.common_tags
}

# Locals: Calculate costs
locals {
  cost_breakdown = {
    "api_only" = {
      nat_gateway_cost = 0         # NAT disabled
      vpc_endpoints_cost = 0       # Bedrock endpoint disabled
      vpn_cost = 0                 # VPN disabled
      lambda_memory_cost = "Low"   # 512 MB
      total_monthly_estimate = "$3-5"
    }
    
    "ha_failover" = {
      nat_gateway_cost = 45        # NAT enabled
      vpc_endpoints_cost = 14      # 2× endpoints
      vpn_cost = 36                # VPN to on-prem
      lambda_memory_cost = "High"  # 1024 MB
      total_monthly_estimate = "$95-120"
    }
  }
}
```

---

### 5. Root Module Orchestration

Main entry point coordinates all modules:

```hcl
# root main.tf

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Pessimistic constraint: allow 5.x but not 6.0
    }
  }
  
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "aIOps/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment  = var.environment
      Project      = "AIOps-Remediation"
      Terraform    = "true"
      CostCenter   = "Engineering"
      Owner        = "Platform-Team"
      CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}

# Core infrastructure
module "vpc" {
  source = "./modules/vpc"
  
  environment = var.environment
  cidr_block  = "10.0.0.0/16"
  
  tags = local.common_tags
}

# Lambda (Always deployed)
module "lambda" {
  source = "./modules/lambda"
  
  function_name      = "aIOps-engine"
  deployment_mode    = var.deployment_mode
  vpc_config         = module.vpc
  
  tags = local.common_tags
}

# Tier 1: External API (conditional on deployment_mode)
module "network_api" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  source = "./modules/network_api"
  
  vpc_id             = module.vpc.id
  lambda_security_group = module.lambda.security_group_id
  
  tags = local.common_tags
}

# Tier 2: AWS Bedrock (conditional on deployment_mode)
module "network_bedrock" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  source = "./modules/network_bedrock"
  
  vpc_id              = module.vpc.id
  lambda_execution_role = module.lambda.execution_role
  
  tags = local.common_tags
}

# Tier 3: On-Premise Local (conditional on deployment_mode)
module "network_local" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  source = "./modules/network_local"
  
  vpc_id           = module.vpc.id
  customer_gateway = aws_customer_gateway.on_premise.id
  
  tags = local.common_tags
}

# Monitoring (Always enabled)
module "observability" {
  source = "./modules/observability"
  
  lambda_name        = module.lambda.function_name
  deployment_mode    = var.deployment_mode
  enable_detailed    = var.environment == "prod"
  
  tags = local.common_tags
}

# Locals
locals {
  common_tags = merge(
    var.tags,
    {
      DeploymentMode = var.deployment_mode
      Environment    = var.environment
    }
  )
}
```

---

### 6. Environment-Specific Values

Use `terraform.tfvars` per environment:

```hcl
# environments/dev/terraform.tfvars
environment     = "dev"
deployment_mode = "api_only"    # Cost-optimized for dev

aws_region            = "us-east-1"
lambda_memory         = 256      # Smaller for cost
enable_nat_gateway    = false    # Disable for dev
enable_alarm_actions  = false    # No SNS in dev

tags = {
  Environment = "dev"
  CostCenter  = "R&D"
  Owner       = "dev-team"
}
```

```hcl
# environments/prod/terraform.tfvars
environment     = "prod"
deployment_mode = "ha_failover"  # HA for production

aws_region            = "us-east-1"
lambda_memory         = 1024      # High for performance
enable_nat_gateway    = true
enable_alarm_actions  = true      # Alert on-call

tags = {
  Environment = "prod"
  CostCenter  = "Operations"
  Owner       = "platform-team"
  SLA         = "99.9%"
}
```

---

### 7. Auto-Shutdown (Ephemeral Infrastructure)

Cleanup after testing:

```hcl
# modules/finops_cleanup/main.tf

resource "aws_scheduler_schedule" "auto_downgrade" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  name            = "aIOps-auto-downgrade"
  description     = "Auto-downgrade from ha_failover to api_only after 15 min"
  schedule_expression = "at(${timeadd(timestamp(), "15m")})"
  
  flexible_time_window {
    mode = "OFF"
  }
  
  target {
    arn      = var.codebuild_project_arn
    role_arn = aws_iam_role.scheduler.arn
    
    # Trigger terraform apply with api_only mode
    input = jsonencode({
      environment_variables = [
        {
          name  = "TF_VAR_deployment_mode"
          value = "api_only"
        }
      ]
    })
  }
  
  tags = var.tags
}

resource "aws_iam_role" "scheduler" {
  name = "aIOps-scheduler-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "aIOps-scheduler-policy"
  role = aws_iam_role.scheduler.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ]
      Resource = var.codebuild_project_arn
    }]
  })
}
```

---

### 8. Terraform Commands for Deployment

```bash
# Initialize (download modules + backend)
terraform init -upgrade

# Validate syntax
terraform validate

# Format code
terraform fmt -recursive

# Plan with specific mode
terraform plan -var="deployment_mode=api_only" -out=tfplan

# Review plan
terraform show tfplan

# Apply plan
terraform apply tfplan

# Destroy specific module (for cleanup)
terraform destroy -target=module.network_tier2_bedrock

# State management
terraform state list                    # Show resources
terraform state show aws_lambda_function.aIOps  # Show details
terraform state rm aws_nat_gateway.main # Remove from state (not AWS)
```

---

### 9. Module Documentation

Generate README with terraform-docs:

```bash
# Install terraform-docs
brew install terraform-docs

# Generate docs
terraform-docs markdown table ./modules/lambda

# Auto-update README
terraform-docs markdown table ./modules/lambda > ./modules/lambda/README.md
```

**Example: modules/lambda/README.md output**
```
## Requirements

| Name | Version |
|------|---------|
| aws | >= 4.0.0 |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| function_name | Lambda function name | `string` | n/a |
| memory | Memory in MB | `number` | 512 |
| timeout | Timeout in seconds | `number` | 30 |

## Outputs

| Name | Description |
|------|-------------|
| function_arn | Lambda function ARN |
| function_name | Lambda function name |
```

---

### 10. Cost Estimation

```hcl
# outputs.tf - Show cost estimates

output "monthly_cost_estimate" {
  description = "Estimated monthly AWS costs"
  value = {
    deployment_mode = var.deployment_mode
    
    api_only = {
      nat_gateway   = 0
      vpc_endpoints = 0
      vpn           = 0
      lambda        = "~$0.20 (per 1M invocations)"
      dynamodb      = "~$1.25 (on-demand)"
      total         = "$3-5/month"
    }
    
    ha_failover = {
      nat_gateway   = 45
      vpc_endpoints = 14
      vpn           = 36
      lambda        = "~$0.50"
      dynamodb      = "~$5 (provisioned)"
      total         = "$95-120/month"
    }
  }
}

output "deployment_mode_info" {
  description = "Current deployment configuration"
  value = {
    mode                = var.deployment_mode
    nat_gateway_enabled = var.enable_nat_gateway
    bedrock_enabled     = var.deployment_mode == "ha_failover"
    vpn_enabled         = var.deployment_mode == "ha_failover"
    lambda_memory_mb    = aws_lambda_function.aIOps.memory_size
  }
}
```

---

## Keywords

Terraform, modules, IaC, modular design, FinOps, cost optimization, conditional resources, multi-environment, AWS, variables, outputs, versioning, reusability, state management
