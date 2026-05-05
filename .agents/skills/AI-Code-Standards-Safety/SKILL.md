---
name: ai-code-standards
description: Enforce production-grade code standards for AI projects. Use when generating code, reviewing implementations, or setting up code quality pipelines. Ensures type safety, error handling, security, testability, and observability across any project.
license: Cristian Custom
---

# AI Code Standards & Safety

## When to use this skill

Generate or review code when:
- Writing new features, agents, APIs, or utilities
- Reviewing existing implementations
- Setting up linting, type checking, or CI validation
- Documenting code quality expectations for teams

## How to use this skill

### 1. Code Generation Checklist

Always generate code that satisfies:

#### Type Safety
- **Python**: Use type hints on all functions (args + return) → enables LSP, IDE autocomplete, mypy validation
- **TypeScript**: Strict mode, no `any` except documented exceptions
- **Go/Rust**: Leverage compiler guarantees; no unsafe code without justification
- **Rule**: If code runs in production and handles data, it must be typed end-to-end

#### Error Handling
- Use typed exceptions/errors (not generic `Exception`)
- Never silently fail (logs required when catching exceptions)
- Propagate errors upstream with context: `raise CustomError(f"Failed to parse {doc_id}: {e}") from e`
- Distinguish recoverable errors (retry) from fatal errors (fail fast)
- **For API/LLM calls**: Always catch rate limits, token limits, timeouts with exponential backoff

#### Logging & Observability
- Log at 4 levels: DEBUG (dev), INFO (state changes), WARN (recoverable issues), ERROR (failures)
- Include structured context: `logger.info("payment_processed", user_id=123, amount=50.5, status="success")`
- **No sensitive data in logs**: mask PII (emails, names), redact API keys, tokens
- **For LLM/AI calls**: Log prompts (truncated if > 1000 chars), model version, token usage, latency
- **Pattern**: `{"timestamp": iso8601, "event": "name", "level": "INFO", "context": {...}}`

#### Security
- Never hardcode secrets → use env vars or secrets manager
- Validate all inputs (type + range + format)
- Sanitize before using in prompts/SQL/commands
- For APIs: require auth, rate limit, validate request size
- **For AI systems**: Don't expose model internals, version prompts, audit decision trails
- Prevent injection attacks: SQL injection, prompt injection, command injection

#### Testing
- Unit tests for logic (80%+ coverage for core paths)
- Mock external calls (LLM APIs, DBs, services) → deterministic tests
- Integration tests for happy paths + edge cases
- **For AI**: Test prompt robustness (adversarial inputs, edge cases)
- Test infrastructure: pytest (Python), vitest/jest (TypeScript), go test (Go)
- Test error paths explicitly

#### Code Structure
- Single responsibility: functions do one thing
- DRY principle: no copy-paste
- Avoid deep nesting (max 3 levels) → extract helpers
- Function length: max 50 lines (code smell if longer)
- Naming: be explicit (`validate_credit_score` not `check`)
- Comments explain "why", not "what" (code explains what)

#### Dependencies
- Minimize external libraries (dependency hell in production)
- Pin versions in lock files (`requirements.lock`, `package-lock.json`)
- Prefer stdlib + stable libraries (avoid beta versions in production)
- **For LLM/AI projects**: Use official SDKs (Anthropic, OpenAI) not wrappers
- Regular dependency audits for security vulnerabilities

---

### 2. Code Review Checklist

When reviewing code, flag if missing:

- [ ] Type hints on all public functions
- [ ] Exception handling (catch, log, propagate or retry)
- [ ] Structured logging with context (no PII)
- [ ] No hardcoded secrets or sensitive data
- [ ] Input validation (type + range + format)
- [ ] Unit tests for business logic (80%+ coverage)
- [ ] API/LLM calls have retry logic + timeouts
- [ ] No dead code or commented-out blocks
- [ ] Documentation for non-obvious behavior
- [ ] Security: no SQL injection, prompt injection, auth bypasses
- [ ] Error messages are user-friendly (no stack traces)
- [ ] Logging is structured, not ad-hoc strings

---

### 3. Project-Level Standards

Establish in each project:

```
/project
├── .env.example          # Template for required env vars (no secrets)
├── .env.local            # Local overrides (git-ignored)
├── src/
│   ├── core/             # Business logic (agents, validators, models)
│   ├── api/              # HTTP endpoints / RPCs
│   ├── llm/              # LLM orchestration, prompts, configs
│   ├── data/             # Validation, serialization, schemas
│   ├── observability/    # Logging, metrics, tracing, monitoring
│   └── utils/            # Shared helpers, common functions
├── tests/                # Mirror src/ structure + integration tests
├── pyproject.toml        # (Python) or package.json (Node)
├── requirements.lock     # (Python) or package-lock.json (Node)
├── Makefile or justfile  # Common tasks: test, lint, type-check, run
├── .gitignore            # Exclude .env, __pycache__, node_modules
├── README.md             # How to run, env vars, architecture diagram
└── SECURITY.md           # Guidelines: auth, secrets, data handling
```

---

### 4. Linting & Type Checking Commands

**Python:**
```bash
# Type checking
mypy src/ --strict

# Code quality & style
ruff check src/ --select E,W,F  # syntax, whitespace, undefined names
black src/ --check              # code formatting
isort src/ --check-only         # import sorting

# Security linting
bandit -r src/                  # detect security issues

# All in one
make lint  # or: mypy src/ && ruff check src/ && black src/ --check
```

**TypeScript:**
```bash
# Type checking (built-in)
tsc --noEmit

# Linting
eslint src/ --fix
prettier src/ --check

# Security linting
npm audit
npm outdated

# All in one
npm run lint
```

**General:**
```bash
# Run tests with coverage
pytest --cov=src tests/  # Python
npm run test -- --coverage  # TypeScript

# Check for TODO/FIXME
grep -r "TODO\|FIXME" src/
```

---

### 5. Example: Production-Grade Function

**Before (bad):**
```python
def process_document(doc):
    content = doc['text']
    extracted = llm_extract(content)
    data.save(extracted)
    return extracted
```

**Problems:**
- No type hints
- Silent failures (what if LLM call fails?)
- No validation
- No logging
- No error handling
- Secrets might be logged

**After (good):**
```python
from typing import Optional
from dataclasses import dataclass
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

@dataclass
class ExtractedData:
    """Validated extraction result."""
    entity_type: str
    confidence: float
    value: str
    raw_response: Optional[str] = None

def process_document(
    doc_id: str,
    content: str,
    model: str = "claude-3-sonnet",
    max_retries: int = 3,
) -> ExtractedData:
    """
    Extract structured data from document text.
    
    Args:
        doc_id: Unique document identifier (required)
        content: Document text (validated < 100KB)
        model: LLM model to use for extraction
        max_retries: Exponential backoff retries on rate limit
        
    Returns:
        ExtractedData with confidence score + raw response
        
    Raises:
        ValidationError: If content fails validation (length, format)
        APIError: If LLM call exhausts retries
        
    Example:
        >>> result = process_document(
        ...     doc_id="doc_123",
        ...     content="Invoice from Acme Corp...",
        ...     model="claude-3-sonnet"
        ... )
        >>> print(result.confidence)
        0.92
    """
    # Input validation
    if not doc_id or not isinstance(doc_id, str):
        raise ValidationError("doc_id must be non-empty string")
    
    if not content or not isinstance(content, str):
        raise ValidationError("content must be non-empty string")
    
    if len(content) > 100_000:
        raise ValidationError(
            f"doc_id={doc_id}: content length {len(content)} exceeds 100KB limit"
        )
    
    logger.info(
        "document_extraction_started",
        doc_id=doc_id,
        content_length=len(content),
        model=model
    )
    
    # Call LLM with retry logic
    extraction = None
    last_error = None
    
    for attempt in range(max_retries):
        try:
            extraction = llm_extract(
                content=content,
                model=model
            )
            logger.info(
                "document_extraction_succeeded",
                doc_id=doc_id,
                confidence=extraction.get("confidence", 0),
                attempt=attempt + 1
            )
            break
        except RateLimitError as e:
            last_error = e
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # exponential backoff
                logger.warning(
                    "document_extraction_rate_limited",
                    doc_id=doc_id,
                    attempt=attempt + 1,
                    retry_after_seconds=wait_time
                )
                time.sleep(wait_time)
            else:
                logger.error(
                    "document_extraction_failed",
                    doc_id=doc_id,
                    error="rate_limit_exhausted",
                    max_retries=max_retries
                )
                raise APIError(f"Rate limit exceeded after {max_retries} retries") from e
        except APIError as e:
            last_error = e
            logger.error(
                "document_extraction_failed",
                doc_id=doc_id,
                error=str(e),
                attempt=attempt + 1
            )
            # Don't retry on API errors (non-rate-limit)
            raise APIError(f"LLM API error: {str(e)}") from e
        except Exception as e:
            last_error = e
            logger.error(
                "document_extraction_unexpected_error",
                doc_id=doc_id,
                error=str(e),
                error_type=type(e).__name__
            )
            raise ProcessingError(f"Unexpected error during extraction: {str(e)}") from e
    
    if extraction is None:
        raise APIError(f"Failed to extract after {max_retries} attempts")
    
    # Validate extracted data structure
    try:
        result = ExtractedData(
            entity_type=extraction.get("entity_type", "unknown"),
            confidence=float(extraction.get("confidence", 0.0)),
            value=extraction.get("value", ""),
            raw_response=extraction.get("raw_response")
        )
    except (TypeError, ValueError, KeyError) as e:
        logger.error(
            "extraction_validation_failed",
            doc_id=doc_id,
            error=str(e),
            extraction_keys=list(extraction.keys()) if isinstance(extraction, dict) else "not_dict"
        )
        raise ValidationError(f"Invalid extraction structure: {str(e)}") from e
    
    # Sanity check: confidence must be 0-1
    if not (0.0 <= result.confidence <= 1.0):
        logger.warning(
            "extraction_confidence_out_of_range",
            doc_id=doc_id,
            confidence=result.confidence
        )
        result.confidence = max(0.0, min(1.0, result.confidence))
    
    # Persist with audit trail
    try:
        data.save(
            doc_id=doc_id,
            result=result,
            timestamp=datetime.utcnow().isoformat(),
            model_used=model
        )
        logger.info(
            "extraction_saved",
            doc_id=doc_id,
            confidence=result.confidence
        )
    except Exception as e:
        logger.error(
            "extraction_save_failed",
            doc_id=doc_id,
            error=str(e)
        )
        # Raise but include the successful extraction
        raise PersistenceError(f"Failed to save extraction: {str(e)}") from e
    
    return result
```

**What improved:**
- ✅ Full type hints (args, return, dataclass)
- ✅ Input validation (type, length, format)
- ✅ Structured logging (context, no secrets)
- ✅ Retry logic with exponential backoff
- ✅ Typed exceptions (ValidationError, APIError, etc.)
- ✅ Error context preserved (`from e`)
- ✅ Docstring with examples
- ✅ No hardcoded values (configurable)
- ✅ Audit trail (timestamp, model used)

---

### 6. Common Pitfalls to Avoid

| Pitfall | Bad | Good |
|---------|-----|------|
| **Silent failures** | `try: ... except: pass` | `except Exception as e: logger.error(...); raise` |
| **Generic exceptions** | `except Exception` | `except RateLimitError, APIError` |
| **Logging PII** | `logger.info(f"User: {email}")` | `logger.info("user_action", user_id=hash(email))` |
| **Hardcoded secrets** | `api_key = "sk-abc123"` | `api_key = os.getenv("ANTHROPIC_API_KEY")` |
| **No timeouts** | `requests.get(url)` | `requests.get(url, timeout=30)` |
| **Async ignored** | `llm_call()` blocks | Use async/await or thread pool |
| **No validation** | `data = request.json()` | `data = UserSchema.parse_obj(request.json())` |
| **Commented code** | `# old_approach()` | Delete it; use git history |

---

### 7. Environment Variables Template

Create `.env.example` in your project root:

```bash
# LLM Configuration
ANTHROPIC_API_KEY=your_api_key_here
LLM_MODEL=claude-3-sonnet
LLM_MAX_TOKENS=2000

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp_db
DB_USER=app_user
# DB_PASSWORD should be in .env.local only (git-ignored)

# API
API_PORT=8000
API_HOST=0.0.0.0
API_LOG_LEVEL=INFO

# Secrets Manager (if using)
SECRETS_MANAGER_REGION=us-east-1
SECRETS_MANAGER_SECRET_NAME=myapp/prod

# Feature Flags
FEATURE_EXPERIMENTAL_AI=false
DEBUG_MODE=false

# Observability
LOG_FORMAT=json  # or "text"
METRICS_ENABLED=true
TRACE_SAMPLE_RATE=0.1
```

---

### 8. Testing Example

```python
import pytest
from unittest.mock import Mock, patch, MagicMock

class TestProcessDocument:
    """Test suite for process_document function."""
    
    def test_valid_extraction(self):
        """Happy path: valid document processing."""
        with patch("llm_extract") as mock_llm:
            mock_llm.return_value = {
                "entity_type": "invoice",
                "confidence": 0.95,
                "value": "INV-123"
            }
            
            result = process_document(
                doc_id="doc_1",
                content="Invoice number INV-123"
            )
            
            assert result.confidence == 0.95
            assert result.entity_type == "invoice"
            mock_llm.assert_called_once()
    
    def test_content_too_long(self):
        """Edge case: content exceeds max length."""
        long_content = "x" * 100_001
        
        with pytest.raises(ValidationError, match="exceeds 100KB"):
            process_document(
                doc_id="doc_1",
                content=long_content
            )
    
    def test_rate_limit_retry(self):
        """Error case: rate limit with successful retry."""
        with patch("llm_extract") as mock_llm:
            # First call fails with rate limit, second succeeds
            mock_llm.side_effect = [
                RateLimitError("Rate limited"),
                {
                    "entity_type": "invoice",
                    "confidence": 0.92,
                    "value": "INV-456"
                }
            ]
            
            result = process_document(
                doc_id="doc_2",
                content="Invoice content",
                max_retries=2
            )
            
            assert result.confidence == 0.92
            assert mock_llm.call_count == 2  # Called twice
    
    def test_rate_limit_exhausted(self):
        """Error case: rate limit persists."""
        with patch("llm_extract") as mock_llm:
            mock_llm.side_effect = RateLimitError("Rate limited")
            
            with pytest.raises(APIError, match="exhausted"):
                process_document(
                    doc_id="doc_3",
                    content="Invoice content",
                    max_retries=2
                )
    
    def test_invalid_extraction_structure(self):
        """Error case: LLM returns malformed data."""
        with patch("llm_extract") as mock_llm:
            mock_llm.return_value = {"unexpected_field": "value"}
            
            with pytest.raises(ValidationError, match="Invalid extraction"):
                process_document(
                    doc_id="doc_4",
                    content="Invoice content"
                )
    
    def test_confidence_normalization(self):
        """Edge case: confidence > 1.0 gets clamped."""
        with patch("llm_extract") as mock_llm:
            mock_llm.return_value = {
                "entity_type": "invoice",
                "confidence": 1.5,  # Invalid, > 1.0
                "value": "INV-789"
            }
            
            result = process_document(
                doc_id="doc_5",
                content="Invoice content"
            )
            
            assert result.confidence == 1.0  # Clamped
```

---

## Keywords

type safety, error handling, logging, security, code quality, linting, testing, production code, safety, Python, TypeScript, validation, observability, monitoring, best practices

