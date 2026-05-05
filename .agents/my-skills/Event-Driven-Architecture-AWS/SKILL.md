---
name: event-driven-architecture-aws
description: Design and implement event-driven architectures using AWS EventBridge, SQS, SNS, and SSM. Use when building event-based systems, defining event routing rules, integrating CloudWatch alarms into automated workflows, and implementing async processing. Applicable to AIOps, remediation engines, and any system that reacts to events.
license: Cristian Custom
---

# Event-Driven Architecture - AWS (EventBridge + SSM)

## When to use this skill

Use this skill when:
- Designing systems that react to events (CloudWatch alarms, API calls, schedules)
- Routing events between AWS services (EventBridge rules)
- Implementing async processing (SQS + Lambda)
- Automating infrastructure operations via SSM
- Decoupling producers from consumers
- Building AIOps or self-healing pipelines
- Implementing auto-shutdown or scheduled jobs

## Architecture Level (Antigravity)

### 1. Core Event-Driven Pattern

The fundamental flow for an AIOps Remediation Engine:

```
┌─────────────────────────────────────────────────────────┐
│                    EVENT PRODUCERS                       │
│  EC2 CloudWatch Agent → CloudWatch Metrics → ALARM       │
└──────────────────────────┬──────────────────────────────┘
                           │ CloudWatch ALARM triggers event
                           ▼
┌─────────────────────────────────────────────────────────┐
│               EVENT BUS (Amazon EventBridge)            │
│  Rule: "source=cloudwatch AND detail-type=EC2 Alarm"    │
└──────────────────────────┬──────────────────────────────┘
                           │ Matches rule → routes to target
                           ▼
┌─────────────────────────────────────────────────────────┐
│               EVENT CONSUMER (Lambda)                   │
│  AIOps Engine → Diagnose → LLM → SSM Remediation        │
└──────────────────────────┬──────────────────────────────┘
                           │ Action completed
                           ▼
┌─────────────────────────────────────────────────────────┐
│               AUDIT & NOTIFICATION                       │
│  CloudWatch Logs + SNS Notification + S3 Audit Trail     │
└─────────────────────────────────────────────────────────┘
```

**Design Rules:**
- Producers have NO knowledge of consumers (fully decoupled)
- EventBridge is the central router (NOT Lambda calling Lambda)
- Events are immutable facts: "EC2 CPU > 90% at T=10:30:00"
- Every event must have a dead-letter destination on failure

---

### 2. Event Schema Design

Define event structure BEFORE building:

```json
{
  "version": "0",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "source": "aws.cloudwatch",
  "account": "123456789012",
  "time": "2026-05-04T10:30:00Z",
  "region": "us-east-1",
  "detail-type": "CloudWatch Alarm State Change",
  "detail": {
    "alarmName": "EC2-HighCPU-i-1234567890abcdef0",
    "state": {
      "value": "ALARM",
      "reason": "CPU exceeded 90%"
    },
    "configuration": {
      "metrics": [
        {
          "metricStat": {
            "metric": {
              "namespace": "AWS/EC2",
              "name": "CPUUtilization",
              "dimensions": {
                "InstanceId": "i-1234567890abcdef0"
              }
            }
          }
        }
      ]
    }
  }
}
```

**Custom Event (from Lambda to EventBridge):**
```json
{
  "source": "aIOps.remediation-engine",
  "detail-type": "Remediation Completed",
  "detail": {
    "instance_id": "i-1234567890abcdef0",
    "alarm_name": "EC2-HighCPU",
    "diagnosis": "High CPU caused by runaway process",
    "action_taken": "Process terminated via SSM",
    "tier_used": "tier1",
    "duration_ms": 4200,
    "status": "success"
  }
}
```

---

### 3. EventBridge Routing Rules

Design rules BEFORE deploying:

```
┌────────────────────────────────────────────────────────┐
│              EventBridge Rule Matrix                    │
├──────────────────┬─────────────────┬───────────────────┤
│ Event Pattern    │ Target           │ Action            │
├──────────────────┼─────────────────┼───────────────────┤
│ CloudWatch ALARM │ Lambda (AIOps)  │ Diagnose + Remediate│
│ ALARM + Critical │ SNS              │ Alert On-Call     │
│ Remediation OK   │ CloudWatch Logs  │ Audit Trail       │
│ Remediation FAIL │ SQS (DLQ)        │ Manual Review     │
│ Schedule 15min   │ CodeBuild        │ Auto-Shutdown     │
└──────────────────┴─────────────────┴───────────────────┘
```

---

### 4. SSM Remediation Commands

Map diagnoses to SSM documents:

```
Diagnosis: "high_cpu_runaway_process"
  → SSM Document: "AIOps-KillHighCPUProcess"
  → Command: "ps aux | sort -rk 3 | head | awk '{print $2}' | xargs kill"

Diagnosis: "disk_space_full"
  → SSM Document: "AIOps-CleanupDisk"
  → Command: "find /var/log -mtime +30 -delete && apt-get clean"

Diagnosis: "service_unresponsive"
  → SSM Document: "AIOps-RestartService"
  → Command: "systemctl restart <service_name>"

Diagnosis: "memory_leak"
  → SSM Document: "AIOps-RestartApp"
  → Command: "systemctl restart <app_service>"
```

---

## Implementation Level (Claude Code)

### 5. EventBridge Rule via Terraform

```hcl
# modules/core/eventbridge.tf

resource "aws_cloudwatch_event_rule" "ec2_alarms" {
  name        = "aIOps-ec2-alarm-trigger"
  description = "Capture EC2 CloudWatch alarms and route to AIOps Lambda"
  
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
      alarmName = [{
        prefix = "EC2-"  # Only capture EC2 alarms
      }]
    }
  })
  
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "aIOps_lambda" {
  rule      = aws_cloudwatch_event_rule.ec2_alarms.name
  target_id = "aIOps-remediation-lambda"
  arn       = var.lambda_function_arn
  
  # Retry config
  retry_policy {
    maximum_event_age_in_seconds = 300  # 5 min max
    maximum_retry_attempts       = 2
  }
  
  # Dead Letter Queue for failed invocations
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_alarms.arn
}

# Dead Letter Queue for failed events
resource "aws_sqs_queue" "dlq" {
  name                      = "aIOps-events-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  tags = var.tags
}

# Auto-shutdown scheduler (FinOps)
resource "aws_scheduler_schedule" "auto_downgrade" {
  count = var.deployment_mode == "ha_failover" ? 1 : 0
  
  name        = "aIOps-auto-downgrade-to-api-only"
  description = "Auto-downgrade from ha_failover to api_only after TTL"
  
  schedule_expression = "at(${timeadd(timestamp(), "${var.ha_failover_ttl_minutes}m")})"
  
  flexible_time_window {
    mode = "OFF"
  }
  
  target {
    arn      = var.codebuild_project_arn
    role_arn = aws_iam_role.scheduler.arn
  }
  
  tags = var.tags
}
```

---

### 6. Lambda: Event Processing

```python
# lambda/handler.py - Event parsing and routing

import json
import logging
import boto3
from typing import Dict, Any, Optional
from dataclasses import dataclass

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
events = boto3.client("events")

@dataclass
class ParsedAlarm:
    alarm_name: str
    instance_id: Optional[str]
    metric_name: str
    alarm_state: str
    timestamp: str
    raw_event: dict

def parse_cloudwatch_event(event: Dict) -> ParsedAlarm:
    """
    Parse CloudWatch Alarm EventBridge event.
    
    Args:
        event: Raw EventBridge event dict
        
    Returns:
        ParsedAlarm with structured fields
        
    Raises:
        ValueError: If required fields missing
    """
    detail = event.get("detail", {})
    
    if not detail:
        raise ValueError("Event has no detail field")
    
    # Extract instance ID from metric dimensions
    instance_id = None
    try:
        metrics = detail.get("configuration", {}).get("metrics", [])
        if metrics:
            dimensions = metrics[0].get("metricStat", {}).get("metric", {}).get("dimensions", {})
            instance_id = dimensions.get("InstanceId")
    except (KeyError, IndexError) as e:
        logger.warning(f"Could not extract instance_id: {e}")
    
    alarm_name = detail.get("alarmName", "unknown")
    
    if not alarm_name or alarm_name == "unknown":
        raise ValueError("Missing alarmName in event detail")
    
    return ParsedAlarm(
        alarm_name=alarm_name,
        instance_id=instance_id,
        metric_name=detail.get("configuration", {}).get("metrics", [{}])[0].get("metricStat", {}).get("metric", {}).get("name", "unknown"),
        alarm_state=detail.get("state", {}).get("value", "ALARM"),
        timestamp=event.get("time", ""),
        raw_event=event
    )

def execute_ssm_document(
    instance_id: str,
    document_name: str,
    parameters: Dict[str, list],
    timeout_seconds: int = 60
) -> Dict:
    """
    Execute SSM Document on EC2 instance.
    
    Args:
        instance_id: EC2 instance ID
        document_name: SSM document name (e.g., "AIOps-RestartService")
        parameters: Key-value pairs for the document
        timeout_seconds: Execution timeout
        
    Returns:
        SSM command response with CommandId
        
    Raises:
        RuntimeError: If SSM command fails to start
    """
    try:
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName=document_name,
            Parameters=parameters,
            TimeoutSeconds=timeout_seconds,
            Comment=f"AIOps auto-remediation via {document_name}"
        )
        
        command_id = response["Command"]["CommandId"]
        
        logger.info(
            "ssm_command_started",
            extra={
                "instance_id": instance_id,
                "document_name": document_name,
                "command_id": command_id
            }
        )
        
        return {
            "command_id": command_id,
            "status": "running",
            "instance_id": instance_id
        }
    
    except ssm.exceptions.InvalidInstanceId as e:
        logger.error(f"Invalid instance {instance_id}: {e}")
        raise RuntimeError(f"Instance {instance_id} not found or not managed by SSM") from e
    except Exception as e:
        logger.error(f"SSM command failed: {e}")
        raise RuntimeError(f"SSM execution failed: {str(e)}") from e

def wait_for_ssm_completion(
    command_id: str,
    instance_id: str,
    max_polls: int = 10,
    poll_interval_seconds: int = 5
) -> Dict:
    """
    Poll SSM command until completion.
    
    Returns:
        Final status dict: { status, output, error }
    """
    import time
    
    for attempt in range(max_polls):
        try:
            result = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id
            )
            
            status = result["Status"]
            
            if status in ["Success", "Failed", "TimedOut", "Cancelled"]:
                logger.info(
                    "ssm_command_completed",
                    extra={
                        "command_id": command_id,
                        "status": status,
                        "instance_id": instance_id
                    }
                )
                return {
                    "status": status,
                    "output": result.get("StandardOutputContent", ""),
                    "error": result.get("StandardErrorContent", "")
                }
            
            logger.info(f"SSM command {command_id} still running (attempt {attempt + 1})")
            time.sleep(poll_interval_seconds)
        
        except Exception as e:
            logger.warning(f"SSM poll error (attempt {attempt + 1}): {e}")
            time.sleep(poll_interval_seconds)
    
    return {"status": "Timeout", "output": "", "error": "Polling timeout"}

def publish_remediation_event(
    instance_id: str,
    alarm_name: str,
    diagnosis: str,
    action: str,
    status: str,
    duration_ms: float
):
    """
    Publish remediation result back to EventBridge for audit.
    """
    try:
        events.put_events(
            Entries=[{
                "Source": "aIOps.remediation-engine",
                "DetailType": "Remediation Completed",
                "Detail": json.dumps({
                    "instance_id": instance_id,
                    "alarm_name": alarm_name,
                    "diagnosis": diagnosis,
                    "action_taken": action,
                    "status": status,
                    "duration_ms": duration_ms
                }),
                "EventBusName": "default"
            }]
        )
        
        logger.info(
            "remediation_event_published",
            extra={
                "instance_id": instance_id,
                "status": status
            }
        )
    except Exception as e:
        logger.error(f"Failed to publish event: {e}")
        # Non-fatal: continue

def lambda_handler(event: Dict[str, Any], context) -> Dict:
    """
    Entry point for EventBridge-triggered Lambda.
    Orchestrates: Parse → Diagnose → Remediate → Audit
    """
    import time
    start_time = time.time()
    
    logger.info(
        "aIOps_engine_invoked",
        extra={"event_source": event.get("source", "unknown")}
    )
    
    # Parse incoming event
    try:
        alarm = parse_cloudwatch_event(event)
    except ValueError as e:
        logger.error(f"Event parsing failed: {e}")
        return {"statusCode": 400, "body": f"Invalid event: {str(e)}"}
    
    logger.info(
        "alarm_parsed",
        extra={
            "alarm_name": alarm.alarm_name,
            "instance_id": alarm.instance_id,
            "metric": alarm.metric_name
        }
    )
    
    # Diagnose (LLM chain-of-responsibility)
    from handler_remediation import diagnose_and_get_action
    
    diagnosis, action, tier_used = diagnose_and_get_action(
        alarm_name=alarm.alarm_name,
        metric_name=alarm.metric_name,
        instance_id=alarm.instance_id
    )
    
    # Remediate via SSM
    ssm_result = {"status": "skipped"}
    if alarm.instance_id and action:
        ssm_document = resolve_ssm_document(diagnosis)
        
        if ssm_document:
            try:
                ssm_command = execute_ssm_document(
                    instance_id=alarm.instance_id,
                    document_name=ssm_document,
                    parameters={"Action": [action]},
                    timeout_seconds=60
                )
                
                ssm_result = wait_for_ssm_completion(
                    command_id=ssm_command["command_id"],
                    instance_id=alarm.instance_id
                )
            except RuntimeError as e:
                logger.error(f"SSM execution failed: {e}")
                ssm_result = {"status": "Failed", "error": str(e)}
    
    # Publish audit event
    duration_ms = (time.time() - start_time) * 1000
    publish_remediation_event(
        instance_id=alarm.instance_id or "unknown",
        alarm_name=alarm.alarm_name,
        diagnosis=diagnosis,
        action=action,
        status=ssm_result.get("status", "unknown"),
        duration_ms=duration_ms
    )
    
    logger.info(
        "aIOps_engine_complete",
        extra={
            "alarm_name": alarm.alarm_name,
            "tier_used": tier_used,
            "ssm_status": ssm_result.get("status"),
            "duration_ms": duration_ms
        }
    )
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "alarm_name": alarm.alarm_name,
            "instance_id": alarm.instance_id,
            "diagnosis": diagnosis,
            "action": action,
            "tier_used": tier_used,
            "ssm_status": ssm_result.get("status"),
            "duration_ms": duration_ms
        })
    }

def resolve_ssm_document(diagnosis: str) -> Optional[str]:
    """Map diagnosis to SSM document name."""
    document_map = {
        "high_cpu": "AIOps-KillHighCPUProcess",
        "disk_full": "AIOps-CleanupDisk",
        "service_down": "AIOps-RestartService",
        "memory_leak": "AIOps-RestartApp",
        "network_saturation": "AIOps-NetworkDiagnostics"
    }
    
    for key, doc in document_map.items():
        if key in diagnosis.lower():
            return doc
    
    logger.warning(f"No SSM document found for diagnosis: {diagnosis}")
    return None
```

---

### 7. Event-Driven Anti-Patterns to Avoid

```
❌ Lambda calling Lambda directly
   → Use SQS + EventBridge for decoupling

❌ No Dead Letter Queue (DLQ)
   → Every EventBridge target must have DLQ configured

❌ Infinite recursive loops
   → EventBridge rule that triggers Lambda that publishes to same bus
   → Always check event source before publishing

❌ Processing without idempotency
   → EventBridge delivers at-least-once; duplicates possible
   → Always implement idempotency key check

❌ Blocking main thread for SSM polling
   → Use async Step Functions for long-running operations

❌ Missing event schema validation
   → Always validate required fields before processing
```

---

### 8. Testing Event-Driven Systems

```python
# tests/test_event_driven.py

import pytest
from unittest.mock import patch, MagicMock
from handler import parse_cloudwatch_event, execute_ssm_document

def test_parse_cloudwatch_event_valid():
    """Parse valid CloudWatch alarm event."""
    event = {
        "source": "aws.cloudwatch",
        "time": "2026-05-04T10:30:00Z",
        "detail": {
            "alarmName": "EC2-HighCPU-i-1234567890",
            "state": {"value": "ALARM"},
            "configuration": {
                "metrics": [{
                    "metricStat": {
                        "metric": {
                            "name": "CPUUtilization",
                            "dimensions": {
                                "InstanceId": "i-1234567890abcdef0"
                            }
                        }
                    }
                }]
            }
        }
    }
    
    alarm = parse_cloudwatch_event(event)
    
    assert alarm.alarm_name == "EC2-HighCPU-i-1234567890"
    assert alarm.instance_id == "i-1234567890abcdef0"
    assert alarm.metric_name == "CPUUtilization"

def test_parse_cloudwatch_event_missing_detail():
    """Reject event with no detail."""
    with pytest.raises(ValueError, match="no detail field"):
        parse_cloudwatch_event({"source": "aws.cloudwatch"})

@patch("boto3.client")
def test_ssm_command_execution(mock_boto3):
    """SSM command starts correctly."""
    mock_ssm = MagicMock()
    mock_boto3.return_value = mock_ssm
    mock_ssm.send_command.return_value = {
        "Command": {"CommandId": "cmd-123"}
    }
    
    result = execute_ssm_document(
        instance_id="i-1234567890abcdef0",
        document_name="AIOps-RestartService",
        parameters={"Action": ["restart nginx"]}
    )
    
    assert result["command_id"] == "cmd-123"
    assert result["status"] == "running"
    mock_ssm.send_command.assert_called_once()

@patch("boto3.client")
def test_ssm_invalid_instance(mock_boto3):
    """Raise RuntimeError on invalid instance."""
    mock_ssm = MagicMock()
    mock_boto3.return_value = mock_ssm
    mock_ssm.send_command.side_effect = mock_ssm.exceptions.InvalidInstanceId("Invalid")
    
    with pytest.raises(RuntimeError, match="Instance"):
        execute_ssm_document(
            instance_id="i-invalid",
            document_name="AIOps-RestartService",
            parameters={}
        )
```

---

## Keywords

Event-driven architecture, AWS EventBridge, Lambda, SSM, CloudWatch alarms, SQS, dead-letter queue, event routing, decoupling, async processing, AIOps, self-healing, auto-remediation, auto-shutdown
