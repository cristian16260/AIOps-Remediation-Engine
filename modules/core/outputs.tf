output "victim_instance_id" {
  description = "ID de la instancia EC2 víctima"
  value       = aws_instance.victim.id
}

output "event_rule_arn" {
  description = "ARN de la regla de EventBridge"
  value       = aws_cloudwatch_event_rule.alarm_capture.arn
}

output "event_rule_name" {
  description = "Nombre de la regla de EventBridge"
  value       = aws_cloudwatch_event_rule.alarm_capture.name
}
