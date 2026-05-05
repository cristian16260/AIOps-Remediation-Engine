---
name: observability-monitoring-incident-response
description: Design and implement comprehensive observability, monitoring systems, and incident response procedures. Use when building logging infrastructure, defining metrics, setting up alerting, configuring dashboards, or establishing incident response playbooks. Based on observability best practices and industry standards.
license: Cristian Custom
---

# Observability, Monitoring & Incident Response

## When to use this skill

Use this skill when:
- Designing logging and metric strategies
- Setting up monitoring dashboards
- Defining alerting rules and thresholds
- Establishing SLO/SLI targets
- Planning incident response procedures
- Implementing distributed tracing
- Debugging production issues
- Building observability into new systems

## How to use this skill

### 1. The Three Pillars of Observability

Observability = Logs + Metrics + Traces (correlated together)

#### Logs: "What happened?"
Detailed events from your application.

```python
import logging
import json
from datetime import datetime

# Configure structured logging
logger = logging.getLogger(__name__)

class JSONFormatter(logging.Formatter):
    """Emit logs as JSON for easy parsing."""
    def format(self, record):
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        # Add custom fields if present
        if hasattr(record, "user_id"):
            log_data["user_id"] = record.user_id
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id
        if hasattr(record, "duration_ms"):
            log_data["duration_ms"] = record.duration_ms
        
        return json.dumps(log_data)

# Setup logging
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Usage with structured context
def process_payment(user_id, amount):
    logger.info(
        "payment_started",
        extra={
            "user_id": user_id,
            "amount": amount,
            "request_id": get_request_id()
        }
    )
    
    try:
        result = charge_card(user_id, amount)
        logger.info(
            "payment_succeeded",
            extra={
                "user_id": user_id,
                "amount": amount,
                "duration_ms": elapsed_time()
            }
        )
        return result
    except Exception as e:
        logger.error(
            "payment_failed",
            exc_info=True,
            extra={
                "user_id": user_id,
                "error": str(e)
            }
        )
        raise
```

**Log Levels:**
- **DEBUG**: Dev info (variable values, flow)
- **INFO**: State changes (user created, payment succeeded)
- **WARNING**: Recoverable issues (retry attempt, fallback used)
- **ERROR**: Failures (payment failed, API unreachable)
- **CRITICAL**: System-wide failures (database down)

#### Metrics: "How is it performing?"
Quantifiable measurements over time.

```python
from prometheus_client import Counter, Histogram, Gauge
import time

# Counter: monotonically increasing
payments_total = Counter(
    "payments_total",
    "Total payments processed",
    ["status", "currency"]
)

# Histogram: distribution of values
payment_duration_seconds = Histogram(
    "payment_duration_seconds",
    "Payment processing time",
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
)

# Gauge: point-in-time value
active_users = Gauge(
    "active_users",
    "Number of currently active users"
)

def process_payment(user_id, amount, currency):
    start_time = time.time()
    
    try:
        result = charge_card(user_id, amount)
        
        # Record metrics
        payments_total.labels(status="success", currency=currency).inc()
        payment_duration_seconds.observe(time.time() - start_time)
        
        return result
    except Exception as e:
        payments_total.labels(status="error", currency=currency).inc()
        raise

# Update gauge (e.g., in background task)
def update_active_users():
    count = db.count_active_users()
    active_users.set(count)
```

**Key Metrics to Track:**
- Request rate (requests/sec)
- Error rate (errors/sec)
- Latency (p50, p95, p99)
- Throughput (items processed/sec)
- Resource usage (CPU, memory, disk)
- Business metrics (payments/sec, conversions)

#### Traces: "How did it flow?"
Request journey through the system.

```python
from opentelemetry import trace, metrics
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure tracing
jaeger_exporter = JaegerExporter(
    agent_host_name="localhost",
    agent_port=6831,
)
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(jaeger_exporter)
)
tracer = trace.get_tracer(__name__)

def process_payment(user_id, amount):
    with tracer.start_as_current_span("process_payment") as span:
        span.set_attribute("user_id", user_id)
        span.set_attribute("amount", amount)
        
        # Span for validation
        with tracer.start_as_current_span("validate_payment") as child_span:
            child_span.set_attribute("step", "validation")
            validate_card(user_id)
        
        # Span for charging
        with tracer.start_as_current_span("charge_card") as child_span:
            child_span.set_attribute("step", "charge")
            result = charge_card(user_id, amount)
        
        # Span for notification
        with tracer.start_as_current_span("send_notification") as child_span:
            child_span.set_attribute("step", "notification")
            send_confirmation_email(user_id, amount)
        
        return result
```

**Trace Benefits:**
- See request path through all services
- Identify bottlenecks (which service is slow?)
- Understand service dependencies
- Correlate logs + metrics across the request

---

### 2. SLO/SLI Definition & Monitoring

**SLI (Service Level Indicator)**: Measured metric
**SLO (Service Level Objective)**: Target for that metric

```python
# Example SLOs for a payment system

slos = {
    "availability": {
        "description": "System available for API calls",
        "sli": "successful_requests / total_requests",
        "slo": 0.99,  # 99% uptime
        "window": "30 days"
    },
    "latency_p99": {
        "description": "99th percentile response time",
        "sli": "p99_latency_ms",
        "slo": 500,  # < 500ms
        "window": "1 minute"
    },
    "error_rate": {
        "description": "Percentage of requests that error",
        "sli": "error_requests / total_requests",
        "slo": 0.001,  # < 0.1%
        "window": "5 minutes"
    }
}

# Calculate SLI values from metrics
def calculate_sli_availability(start_time, end_time):
    total_requests = count_requests(start_time, end_time)
    successful = count_successful(start_time, end_time)
    
    availability = successful / total_requests if total_requests > 0 else 0
    
    return {
        "sli_value": availability,
        "slo_target": 0.99,
        "is_healthy": availability >= 0.99,
        "error_budget_remaining": (availability - 0.99) / 0.01  # How much "degradation" left
    }
```

---

### 3. Alerting Strategy

Alert on **business-critical issues**, not noise:

```python
# ❌ BAD: Alert on every error
# Too many false alarms, people ignore alerts

# ✅ GOOD: Alert on SLO violation + context
alerting_rules = {
    "payment_system_down": {
        "condition": "error_rate > 0.05 for 5 minutes",
        "severity": "critical",
        "action": "page on-call immediately",
        "channels": ["pagerduty", "slack"]
    },
    "payment_latency_degraded": {
        "condition": "p99_latency > 2000ms for 10 minutes",
        "severity": "warning",
        "action": "notify team, investigate",
        "channels": ["slack"]
    },
    "database_connection_pool_exhausted": {
        "condition": "db_connections == max_connections for 2 minutes",
        "severity": "critical",
        "action": "auto-scale or page on-call",
        "channels": ["pagerduty"]
    },
    "high_memory_usage": {
        "condition": "memory_percent > 90 for 5 minutes",
        "severity": "warning",
        "action": "investigate memory leak",
        "channels": ["slack"]
    }
}

# Prometheus alerting rules (YAML format)
"""
groups:
  - name: payment_alerts
    rules:
      - alert: PaymentSystemDown
        expr: rate(payment_errors_total[5m]) > 0.05
        for: 5m
        annotations:
          summary: "Payment system error rate > 5%"
          description: "Immediate action required"
          
      - alert: HighLatency
        expr: histogram_quantile(0.99, payment_duration_seconds) > 2
        for: 10m
        annotations:
          summary: "Payment p99 latency > 2s"
"""
```

---

### 4. Monitoring Dashboard Setup

Build dashboards for different audiences:

```python
# Dashboard for engineers (detailed debugging)
engineering_dashboard = {
    "name": "Payment Service - Engineering",
    "sections": [
        {
            "title": "Request Flow",
            "panels": [
                {
                    "name": "Requests/sec by endpoint",
                    "metric": "rate(http_requests_total[1m])",
                    "type": "timeseries"
                },
                {
                    "name": "Error rate by endpoint",
                    "metric": "rate(http_errors_total[1m])",
                    "type": "timeseries"
                },
                {
                    "name": "Latency distribution",
                    "metric": "histogram_quantile(0.95, http_duration_seconds)",
                    "type": "graph"
                }
            ]
        },
        {
            "title": "Database",
            "panels": [
                {
                    "name": "Active connections",
                    "metric": "db_active_connections",
                    "type": "gauge",
                    "alert_threshold": 90  # % of max
                },
                {
                    "name": "Query latency",
                    "metric": "db_query_duration_seconds",
                    "type": "histogram"
                },
                {
                    "name": "Slow queries",
                    "metric": "rate(db_slow_queries_total[1m])",
                    "type": "counter"
                }
            ]
        },
        {
            "title": "Infrastructure",
            "panels": [
                {
                    "name": "CPU usage",
                    "metric": "node_cpu_percent",
                    "type": "gauge"
                },
                {
                    "name": "Memory usage",
                    "metric": "node_memory_percent",
                    "type": "gauge"
                },
                {
                    "name": "Disk space",
                    "metric": "node_disk_free_bytes",
                    "type": "gauge"
                }
            ]
        }
    ]
}

# Dashboard for on-call (incident response)
on_call_dashboard = {
    "name": "Payment Service - On-Call",
    "refresh_rate": "10s",
    "sections": [
        {
            "title": "🚨 CRITICAL METRICS",
            "panels": [
                {
                    "name": "System Status",
                    "metric": "is_healthy",
                    "type": "big_number",
                    "thresholds": {"red": 0, "green": 1}
                },
                {
                    "name": "Error Rate %",
                    "metric": "error_rate * 100",
                    "type": "big_number",
                    "unit": "%",
                    "alert_if_above": 1.0
                },
                {
                    "name": "P99 Latency (ms)",
                    "metric": "p99_latency_ms",
                    "type": "big_number",
                    "alert_if_above": 2000
                }
            ]
        },
        {
            "title": "Latest Errors",
            "panels": [
                {
                    "name": "Recent errors (last 5 min)",
                    "query": "select * from logs where level='ERROR' order by timestamp desc limit 50",
                    "type": "table"
                }
            ]
        }
    ]
}
```

---

### 5. Incident Response Runbook

Create playbooks for common incidents:

```markdown
# Incident Runbook: Payment System High Error Rate

## Detection
- Alert: `PaymentSystemDown` triggered
- Error rate > 5% for > 5 minutes

## Immediate Actions (First 2 minutes)

1. **Acknowledge the incident**
   - [ ] Acknowledge PagerDuty alert
   - [ ] Open incident channel in Slack
   - [ ] Tag on-call lead + database owner

2. **Assess scope**
   - [ ] Check payment dashboard: error rate, affected endpoints
   - [ ] Query: `SELECT COUNT(*) FROM payment_errors WHERE timestamp > NOW() - INTERVAL 5 MINUTES`
   - [ ] Check: is this one payment type or all?
   - [ ] Estimate: how many customers affected?

3. **Check recent deployments**
   - [ ] When was last deploy? `git log --oneline -5`
   - [ ] What changed? `git diff HEAD~1..HEAD src/payment/`
   - [ ] Correlation: error rate spike aligned with deploy?

## Investigation (Next 5-10 minutes)

### If database is slow:
```bash
# Check active queries
SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;

# Check connections
SELECT count(*) FROM pg_stat_activity;

# Check disk space
SELECT * FROM pg_tablespace;
```

### If external API failing:
```bash
# Check API health
curl -v https://payment-gateway.com/health

# Check logs for timeout/connection errors
grep -i "timeout\|connection" /var/log/payment-service.log | tail -50
```

### If code is stuck in loop:
```bash
# Check for goroutine/thread leaks
curl localhost:6060/debug/pprof/goroutine?debug=1

# Memory usage trend
curl localhost:6060/debug/pprof/heap | go tool pprof - | top
```

## Recovery Options (Escalating)

### Option 1: Rollback (5 minutes, low risk)
```bash
# If recent deploy caused issue
git revert HEAD
git push
./deploy.sh  # Redeploy
```

### Option 2: Enable circuit breaker (2 minutes, immediate effect)
```python
# If external service failing
CIRCUIT_BREAKER_ENABLED=true
# Requests fail-open instead of failing to external service
```

### Option 3: Scale up services (3-5 minutes)
```bash
# If load-related
kubectl scale deployment payment-service --replicas=10
```

### Option 4: Database failover (10 minutes, highest risk)
```bash
# Only if primary database is down
kubectl exec -it primary-db -- /switch-to-standby.sh
```

## Validation

After taking action:

- [ ] Error rate returns to < 0.1% (give 2 min)
- [ ] P99 latency < 500ms
- [ ] No new errors in logs
- [ ] Customer reports normalized

```sql
-- Validate fix
SELECT 
  AVG(CASE WHEN status='error' THEN 1 ELSE 0 END) as error_rate,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99_latency,
  COUNT(*) as total_requests
FROM payment_logs
WHERE timestamp > NOW() - INTERVAL '5 MINUTES'
AND timestamp < NOW() - INTERVAL '2 MINUTES';
```

## Post-Incident

- [ ] Document root cause (what really happened?)
- [ ] Owner: create bug/ticket for fix
- [ ] Timeline: log exact times for blameless post-mortem
- [ ] Monitoring: did we catch this fast enough? Add alerts if not
```

---

### 6. Log Analysis Patterns

Query logs to debug issues:

```python
# Example: Find slow payments
logs_query = """
SELECT 
  user_id,
  payment_id,
  duration_ms,
  status,
  timestamp
FROM logs
WHERE 
  event='payment_succeeded'
  AND duration_ms > 5000
  AND timestamp > NOW() - INTERVAL '1 hour'
ORDER BY duration_ms DESC
LIMIT 50
"""

# Find errors for specific user
user_errors = """
SELECT 
  timestamp,
  error,
  request_id,
  function_name
FROM logs
WHERE 
  user_id = 'user_123'
  AND level = 'ERROR'
ORDER BY timestamp DESC
LIMIT 20
"""

# Trace request through system
request_trace = """
SELECT 
  service,
  timestamp,
  duration_ms,
  status,
  message
FROM logs
WHERE 
  request_id = '550e8400-e29b-41d4-a716-446655440000'
ORDER BY timestamp ASC
"""
```

---

### 7. Observability Checklist

Ensure comprehensive coverage:

- [ ] **Logging**
  - [ ] Structured JSON format (not plain text)
  - [ ] Log levels used correctly (INFO, WARNING, ERROR)
  - [ ] No PII in logs (email, passwords, credit cards)
  - [ ] Correlation IDs propagated across services
  - [ ] Log retention configured (30-90 days typical)

- [ ] **Metrics**
  - [ ] Request rate, error rate, latency tracked
  - [ ] Business metrics (payments/sec, conversions)
  - [ ] Resource metrics (CPU, memory, disk)
  - [ ] Custom application metrics
  - [ ] Metrics exported to monitoring system

- [ ] **Tracing**
  - [ ] Request IDs generated and propagated
  - [ ] Key spans instrumented (important operations)
  - [ ] Distributed tracing across services
  - [ ] Sampling configured (don't trace every request)

- [ ] **Alerts**
  - [ ] SLO-based alerts (not noisy)
  - [ ] Multiple alert channels (Slack, PagerDuty)
  - [ ] Runbooks attached to critical alerts
  - [ ] Alert history reviewed for false positives

- [ ] **Dashboards**
  - [ ] Engineering dashboard (detailed metrics)
  - [ ] On-call dashboard (critical metrics only)
  - [ ] Business dashboard (revenue, errors, uptime)
  - [ ] Auto-refresh enabled

- [ ] **On-Call**
  - [ ] Runbooks for top 10 incidents
  - [ ] Escalation policy defined
  - [ ] On-call rotation scheduled
  - [ ] Incident response drills quarterly

---

### 8. Observability Tools Overview

| Use Case | Best Tools | Notes |
|----------|-----------|-------|
| **Metrics** | Prometheus + Grafana | OSS, no cost, widely adopted |
| **Logs** | ELK Stack / Loki | ELK = mature but heavy; Loki = lighter |
| **Traces** | Jaeger / Zipkin | Jaeger more popular; both OSS |
| **LLM Observability** | Langfuse / OpenLLMetry | Track LLM calls, prompts, latency |
| **Integrations** | OpenTelemetry | Vendor-neutral standard |

---

### 9. Common Observability Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| **Logging everything** | Storage costs, noise | Log only important events |
| **No correlation IDs** | Can't trace requests | Generate + propagate request IDs |
| **Alerts on everything** | Alert fatigue, ignored | Alert on SLO violations only |
| **No context in logs** | Can't debug issues | Include user_id, request_id, etc |
| **PII in logs** | Compliance violations | Sanitize sensitive data |
| **No runbooks** | Slow incident response | Document playbooks for top issues |
| **Manual dashboard creation** | High maintenance | Use infrastructure-as-code |

---

## Keywords

observability, monitoring, logging, metrics, tracing, SLO, SLI, alerting, incident response, dashboards, Prometheus, Grafana, ELK, Jaeger, OpenTelemetry, structured logging, distributed tracing, runbooks, on-call
