# Rol IAM para EC2 con políticas de SSM y CloudWatch Agent
resource "aws_iam_role" "ec2_role" {
  name = "aiops-ec2-victim-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "aiops-ec2-victim-profile"
  role = aws_iam_role.ec2_role.name
}

# Instancia EC2 (Víctima)
resource "aws_instance" "victim" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.private_subnets[0]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "AIOps-Victim-EC2"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y amazon-cloudwatch-agent
              # En un escenario real, configurar el CW Agent para monitorear métricas/logs específicos aquí
              systemctl enable amazon-cloudwatch-agent
              systemctl start amazon-cloudwatch-agent
              EOF
}

# Ejemplo de Alarma CloudWatch (Alto uso de CPU)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "aiops-high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors ec2 cpu utilization"

  dimensions = {
    InstanceId = aws_instance.victim.id
  }
}

# Regla de EventBridge para capturar la alarma
resource "aws_cloudwatch_event_rule" "alarm_capture" {
  name        = "aiops-capture-alarm"
  description = "Capture CloudWatch Alarms for AIOps Remediation"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
      alarmName = [aws_cloudwatch_metric_alarm.high_cpu.alarm_name]
    }
  })
}

# Nota: El destino para EventBridge (la función Lambda) se configurará en el módulo de remediación o raíz.
