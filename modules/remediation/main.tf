data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "aiops-remediation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Política para invocar SSM y leer Secrets/Parameter Store/Bedrock
resource "aws_iam_role_policy" "lambda_aiops_policy" {
  name = "aiops-lambda-permissions"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ssm:*:*:document/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # 3. Principio de Menor Privilegio: Solo puede leer el API Key de LLM (ChatGPT / Anthropic)
        Resource = [var.secret_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        # 3. Principio de Menor Privilegio: Solo puede invocar a Claude 3 Haiku (o el modelo que elijamos en Bedrock)
        Resource = ["arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"]
      }
    ]
  })
}

resource "aws_security_group" "lambda_sg" {
  name        = "aiops-lambda-sg"
  description = "Security Group para la Lambda AIOps Engine"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "aiops_engine" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "aiops-remediation-engine"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30 # Aggressive timeout for failover support

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }
}

# SSM Document para mitigación genérica (ejemplo: reiniciar servicio)
resource "aws_ssm_document" "mitigation" {
  name          = "AIOps-RestartService"
  document_type = "Command"
  content       = jsonencode({
    schemaVersion = "2.2"
    description   = "Reinicia un servicio específico via AIOps"
    parameters = {
      ServiceName = {
        type        = "String"
        description = "Nombre del servicio a reiniciar"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "restartService"
        inputs = {
          runCommand = ["systemctl restart {{ ServiceName }}"]
        }
      }
    ]
  })
}
