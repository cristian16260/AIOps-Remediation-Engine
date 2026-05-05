---
name: aws-lambda-resilience-patterns
description: Implement resilient AWS Lambda functions with multi-tier failover, circuit breaker patterns, retry logic, and error handling. Use when designing fault-tolerant Lambda architectures, managing external API dependencies, and building self-healing systems. For both architecture (Antigravity) and implementation (Claude Code).
license: Cristian Custom
---

# AWS Lambda + Resilience Patterns

## When to use this skill

Use this skill when:
- Designing Lambda functions with external dependencies (APIs, LLMs)
- Implementing failover strategies (Tier 1 → Tier 2 → Tier 3)
- Building circuit breaker patterns for fault tolerance
- Handling timeouts and retries intelligently
- Managing Lambda execution in VPCs with security groups
- Implementing idempotency to prevent duplicate processing
- Building self-healing systems with automatic recovery

## Architecture Level (Antigravity)

### 1. Multi-Tier Failover Design

Define the architecture BEFORE coding:

```
┌─────────────────────────────────────────────────┐
│ CloudWatch Alarm → Lambda Invocation            │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │  Lambda Handler      │
        │ (Chain of Resp)      │
        └──────────┬───────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
    ┌────────────┐    ┌────────────┐
    │ Tier 1     │    │ Circuit    │
    │ (OpenAI)   │    │ Breaker    │
    │ Timeout: 2s│    │ (DynamoDB) │
    └────┬───────┘    └────────────┘
         │ FAIL
         ▼
    ┌────────────┐
    │ Tier 2     │
    │ (Bedrock)  │
    │ Timeout: 2s│
    └────┬───────┘
         │ FAIL
         ▼
    ┌────────────┐
    │ Tier 3     │
    │ (Local)    │
    │ Timeout: 2s│
    └────┬───────┘
         │ ALL FAIL
         ▼
    ┌────────────────┐
    │ Fallback       │
    │ (Rule-based)   │
    │ No LLM needed  │
    └────────────────┘
```

**Key Design Decisions:**

| Decision | Rationale |
|----------|-----------|
| **Timeout: 2-3 seconds per tier** | Lambda max execution 30s; 3 tiers × 3s = 9s buffer |
| **State in DynamoDB** | Circuit breaker persistence across invocations |
| **Async health checks** | Background validation without blocking requests |
| **Idempotent operations** | Retries shouldn't cause duplicates |

---

### 2. Circuit Breaker State Machine

Design state transitions BEFORE coding:

```
┌─────────┐
│ CLOSED  │ ← Normal operation (Tier is healthy)
│ (✓ 200) │
└────┬────┘
     │ 3 consecutive failures?
     ▼
┌─────────────────┐
│ OPEN            │ ← Tier is failing; block requests
│ (✗ reject)      │   TTL: 30-60 seconds
└────┬────────────┘
     │ TTL expired?
     ▼
┌──────────────┐
│ HALF_OPEN    │ ← Test: 1 request allowed
│ (? probing)  │
└────┬─────────┘
     │
     ├─ Success → CLOSED (traffic flows)
     └─ Failure → OPEN (block again)
```

**State Persistence:**
```
DynamoDB Table: "circuit-status"
{
  "service_name": "openai",            # Partition key
  "timestamp": "2026-05-04T10:30:00Z", # Sort key
  "status": "OPEN" | "CLOSED" | "HALF_OPEN",
  "failure_count": 3,
  "last_failure": "RateLimitError",
  "ttl": 1715330400                     # Expires in 60s
}
```

---

### 3. Retry Strategy

Define retry policy per tier:

| Tier | Max Retries | Backoff | Retryable Errors |
|------|-------------|---------|------------------|
| **Tier 1 (API)** | 2 | 2^n × 100ms | RateLimitError, TimeoutError |
| **Tier 2 (Bedrock)** | 1 | 2^n × 50ms | ThrottlingError, TimeoutError |
| **Tier 3 (Local)** | 0 | N/A | None (fail fast) |

```
Time: 0ms    - Tier 1 attempt 1 (2s timeout)
Time: 2000ms - TIMEOUT → Tier 1 attempt 2 (2s timeout, wait 200ms before)
Time: 4200ms - TIMEOUT → Tier 2 attempt 1 (2s timeout)
Time: 6200ms - TIMEOUT → Tier 3 attempt 1 (2s timeout)
Time: 8200ms - TIMEOUT → Fallback (rule-based decision)
```

---

### 4. Idempotency Design

Every request must be SAFE to retry:

```
Request ID: "req_550e8400-e29b-41d4"
  ↓
DynamoDB: "idempotency-cache"
  Key: request_id
  Value: {
    "result": { "remediation": "restart_service_X" },
    "timestamp": "2026-05-04T10:30:00Z",
    "ttl": 1715330400  # Expires in 1 hour
  }
  ↓
Return SAME result (no duplicate action)
```

---

## Implementation Level (Claude Code)

### 5. Lambda Handler Structure

```python
import json
import logging
import time
from typing import Dict, Any, Optional
from enum import Enum
from dataclasses import dataclass
from datetime import datetime, timedelta
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS Clients
dynamodb = boto3.resource("dynamodb")
secrets = boto3.client("secretsmanager")

# Constants
CIRCUIT_STATUS_TABLE = "circuit-status"
IDEMPOTENCY_TABLE = "idempotency-cache"
TIER_TIMEOUTS = {"tier1": 2.0, "tier2": 2.0, "tier3": 2.0}

class CircuitStatus(Enum):
    CLOSED = "CLOSED"
    OPEN = "OPEN"
    HALF_OPEN = "HALF_OPEN"

@dataclass
class RemediationResult:
    status: str        # "success" or "fail"
    tier_used: str     # "tier1", "tier2", "tier3", or "fallback"
    duration_ms: float
    diagnosis: str
    action: str

class CircuitBreaker:
    """Manage health state of external services."""
    
    def __init__(self, service_name: str, table_name: str):
        self.service_name = service_name
        self.table = dynamodb.Table(table_name)
    
    def get_status(self) -> CircuitStatus:
        """Check if circuit is open/closed."""
        try:
            response = self.table.get_item(
                Key={"service_name": self.service_name}
            )
            
            if "Item" not in response:
                # No record = circuit is closed (healthy)
                return CircuitStatus.CLOSED
            
            item = response["Item"]
            status = CircuitStatus[item["status"]]
            
            # Check if TTL expired
            if "ttl" in item and int(item["ttl"]) < int(time.time()):
                # Expired → reset to HALF_OPEN (test the service)
                return CircuitStatus.HALF_OPEN
            
            return status
        except Exception as e:
            logger.error(f"Circuit breaker check failed: {e}")
            # Fail open: assume service works
            return CircuitStatus.CLOSED
    
    def record_failure(self, error: str):
        """Record a failure; open circuit if threshold exceeded."""
        try:
            item = self.table.get_item(
                Key={"service_name": self.service_name}
            ).get("Item", {})
            
            failure_count = int(item.get("failure_count", 0)) + 1
            
            # Open circuit after 3 failures
            new_status = CircuitStatus.OPEN if failure_count >= 3 else CircuitStatus.CLOSED
            
            self.table.put_item(
                Item={
                    "service_name": self.service_name,
                    "status": new_status.value,
                    "failure_count": failure_count,
                    "last_failure": error,
                    "timestamp": int(time.time()),
                    "ttl": int(time.time()) + 60  # Expire in 60s
                }
            )
            
            logger.warning(
                f"Circuit breaker recorded failure",
                extra={
                    "service": self.service_name,
                    "failure_count": failure_count,
                    "new_status": new_status.value
                }
            )
        except Exception as e:
            logger.error(f"Failed to record circuit breaker failure: {e}")
    
    def record_success(self):
        """Reset circuit to CLOSED on success."""
        try:
            self.table.delete_item(Key={"service_name": self.service_name})
            logger.info(f"Circuit breaker reset for {self.service_name}")
        except Exception as e:
            logger.error(f"Failed to reset circuit breaker: {e}")

class IdempotencyManager:
    """Prevent duplicate processing of same request."""
    
    def __init__(self, request_id: str, table_name: str, ttl_seconds: int = 3600):
        self.request_id = request_id
        self.table = dynamodb.Table(table_name)
        self.ttl_seconds = ttl_seconds
    
    def get_cached_result(self) -> Optional[RemediationResult]:
        """Return cached result if request was already processed."""
        try:
            response = self.table.get_item(Key={"request_id": self.request_id})
            
            if "Item" in response:
                item = response["Item"]
                logger.info(
                    f"Returning cached result for request {self.request_id}"
                )
                return RemediationResult(**item["result"])
            return None
        except Exception as e:
            logger.error(f"Idempotency check failed: {e}")
            return None
    
    def cache_result(self, result: RemediationResult):
        """Cache result for future duplicate requests."""
        try:
            self.table.put_item(
                Item={
                    "request_id": self.request_id,
                    "result": result.__dict__,
                    "timestamp": int(time.time()),
                    "ttl": int(time.time()) + self.ttl_seconds
                }
            )
        except Exception as e:
            logger.error(f"Failed to cache result: {e}")

def call_tier1_openai(
    diagnosis: str,
    timeout_seconds: float
) -> Optional[str]:
    """Tier 1: Call OpenAI API (external, most reliable)."""
    import requests
    
    start_time = time.time()
    circuit_breaker = CircuitBreaker("openai", CIRCUIT_STATUS_TABLE)
    
    # Check if circuit is open
    if circuit_breaker.get_status() == CircuitStatus.OPEN:
        logger.info("Tier 1 circuit is OPEN; skipping")
        return None
    
    try:
        # Get API key from Secrets Manager
        secret = secrets.get_secret_value(SecretId="anthropic-api-key")
        api_key = json.loads(secret["SecretString"])["key"]
        
        # Call OpenAI
        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4",
                "messages": [{"role": "user", "content": f"Diagnosis: {diagnosis}"}]
            },
            timeout=timeout_seconds
        )
        
        if response.status_code == 200:
            circuit_breaker.record_success()
            elapsed = time.time() - start_time
            logger.info(
                "Tier 1 succeeded",
                extra={"latency_ms": elapsed * 1000}
            )
            return response.json()["choices"][0]["message"]["content"]
        else:
            raise Exception(f"API returned {response.status_code}")
    
    except requests.exceptions.Timeout:
        circuit_breaker.record_failure("TimeoutError")
        logger.warning("Tier 1 timeout")
        return None
    except requests.exceptions.ConnectionError as e:
        circuit_breaker.record_failure("ConnectionError")
        logger.warning(f"Tier 1 connection error: {e}")
        return None
    except Exception as e:
        circuit_breaker.record_failure(str(e))
        logger.error(f"Tier 1 error: {e}")
        return None

def call_tier2_bedrock(
    diagnosis: str,
    timeout_seconds: float
) -> Optional[str]:
    """Tier 2: AWS Bedrock (internal, more reliable)."""
    import boto3
    
    start_time = time.time()
    circuit_breaker = CircuitBreaker("bedrock", CIRCUIT_STATUS_TABLE)
    
    if circuit_breaker.get_status() == CircuitStatus.OPEN:
        logger.info("Tier 2 circuit is OPEN; skipping")
        return None
    
    try:
        bedrock = boto3.client("bedrock-runtime")
        
        response = bedrock.invoke_model(
            modelId="anthropic.claude-3-sonnet-20240229-v1:0",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-06-01",
                "max_tokens": 1024,
                "messages": [
                    {"role": "user", "content": f"Diagnosis: {diagnosis}"}
                ]
            })
        )
        
        result = json.loads(response["body"].read())
        circuit_breaker.record_success()
        elapsed = time.time() - start_time
        logger.info(
            "Tier 2 succeeded",
            extra={"latency_ms": elapsed * 1000}
        )
        return result["content"][0]["text"]
    
    except Exception as e:
        circuit_breaker.record_failure(str(e))
        logger.error(f"Tier 2 error: {e}")
        return None

def call_tier3_local(
    diagnosis: str,
    timeout_seconds: float
) -> Optional[str]:
    """Tier 3: Local on-premise inference (last resort)."""
    import http.client
    
    try:
        # Connect to on-premise local LLM (via VPN/SSM Hybrid)
        conn = http.client.HTTPConnection(
            "10.100.0.10",  # On-prem local address
            8000,
            timeout=timeout_seconds
        )
        
        conn.request("POST", "/infer", json.dumps({
            "prompt": f"Diagnosis: {diagnosis}"
        }))
        
        response = conn.getresponse()
        data = json.loads(response.read())
        
        logger.info("Tier 3 succeeded")
        return data.get("result")
    
    except Exception as e:
        logger.error(f"Tier 3 error: {e}")
        return None

def fallback_rule_based_decision(diagnosis: str) -> str:
    """Fallback: Rule-based decision (no LLM needed)."""
    # Simple rule-based remediation
    rules = {
        "high_cpu": "Scale up EC2 instances",
        "high_memory": "Restart application service",
        "disk_full": "Archive old logs and clear cache",
        "db_slow": "Restart database connection pool"
    }
    
    for key, action in rules.items():
        if key in diagnosis.lower():
            logger.info(f"Fallback rule matched: {key} → {action}")
            return action
    
    # Default: escalate to human
    return "Escalate to on-call engineer for manual investigation"

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Main Lambda handler: Chain of Responsibility pattern."""
    
    request_id = event.get("request_id", context.request_id)
    diagnosis = event.get("diagnosis", "Unknown error")
    
    start_time = time.time()
    
    # Step 1: Check idempotency
    idempotency = IdempotencyManager(request_id, IDEMPOTENCY_TABLE)
    cached_result = idempotency.get_cached_result()
    if cached_result:
        return {
            "statusCode": 200,
            "body": json.dumps(cached_result.__dict__)
        }
    
    # Step 2: Try tiers in order
    remediation_result = None
    
    # Tier 1: External API (OpenAI)
    logger.info("Attempting Tier 1 (OpenAI)")
    action = call_tier1_openai(diagnosis, TIER_TIMEOUTS["tier1"])
    if action:
        remediation_result = RemediationResult(
            status="success",
            tier_used="tier1",
            duration_ms=(time.time() - start_time) * 1000,
            diagnosis=diagnosis,
            action=action
        )
    
    # Tier 2: AWS Bedrock
    if not remediation_result:
        logger.info("Attempting Tier 2 (Bedrock)")
        action = call_tier2_bedrock(diagnosis, TIER_TIMEOUTS["tier2"])
        if action:
            remediation_result = RemediationResult(
                status="success",
                tier_used="tier2",
                duration_ms=(time.time() - start_time) * 1000,
                diagnosis=diagnosis,
                action=action
            )
    
    # Tier 3: Local
    if not remediation_result:
        logger.info("Attempting Tier 3 (Local)")
        action = call_tier3_local(diagnosis, TIER_TIMEOUTS["tier3"])
        if action:
            remediation_result = RemediationResult(
                status="success",
                tier_used="tier3",
                duration_ms=(time.time() - start_time) * 1000,
                diagnosis=diagnosis,
                action=action
            )
    
    # Fallback: Rule-based
    if not remediation_result:
        logger.warning("All LLM tiers failed; using fallback")
        action = fallback_rule_based_decision(diagnosis)
        remediation_result = RemediationResult(
            status="fallback",
            tier_used="fallback",
            duration_ms=(time.time() - start_time) * 1000,
            diagnosis=diagnosis,
            action=action
        )
    
    # Step 3: Cache result for idempotency
    idempotency.cache_result(remediation_result)
    
    # Step 4: Log metrics
    logger.info(
        "Remediation completed",
        extra={
            "request_id": request_id,
            "tier_used": remediation_result.tier_used,
            "status": remediation_result.status,
            "duration_ms": remediation_result.duration_ms
        }
    )
    
    return {
        "statusCode": 200,
        "body": json.dumps(remediation_result.__dict__)
    }
```

---

### 6. Testing Resilience

```python
# tests/test_resilience.py

import pytest
from unittest.mock import patch, MagicMock
from handler import (
    CircuitBreaker,
    call_tier1_openai,
    lambda_handler,
    RemediationResult
)

def test_circuit_breaker_opens_after_failures():
    """Circuit should open after 3 failures."""
    cb = CircuitBreaker("test_service", "circuit-status")
    
    for i in range(3):
        cb.record_failure("TestError")
    
    assert cb.get_status().value == "OPEN"

@patch("requests.post")
def test_tier1_timeout(mock_post):
    """Tier 1 should timeout after 2 seconds."""
    mock_post.side_effect = TimeoutError()
    
    result = call_tier1_openai("high cpu", timeout_seconds=2.0)
    
    assert result is None

def test_lambda_failover_chain(mock_context):
    """Lambda should try Tier1 → Tier2 → Tier3 → Fallback."""
    event = {
        "request_id": "req_123",
        "diagnosis": "high_cpu"
    }
    
    with patch("call_tier1_openai", return_value=None), \
         patch("call_tier2_bedrock", return_value="Scale EC2"), \
         patch("cache_result"):
        
        response = lambda_handler(event, mock_context)
        
        assert response["statusCode"] == 200
        assert "tier2" in response["body"]

def test_idempotency():
    """Same request_id should return cached result."""
    request_id = "req_idempotent"
    
    # First call
    result1 = RemediationResult(
        status="success",
        tier_used="tier1",
        duration_ms=500,
        diagnosis="test",
        action="restart"
    )
    
    # Cache it
    idempotency = IdempotencyManager(request_id, "idempotency-cache")
    idempotency.cache_result(result1)
    
    # Second call should get cached
    result2 = idempotency.get_cached_result()
    
    assert result1.action == result2.action
```

---

## Keywords

AWS Lambda, resilience, failover, circuit breaker, retry logic, timeout, idempotency, DynamoDB, error handling, multi-tier, self-healing, fault tolerance, Chain of Responsibility
