---
name: testing-strategy-qa
description: Design and implement comprehensive testing strategies, quality assurance processes, and continuous validation. Use when planning test architecture, writing test code, setting up CI/CD gates, managing defects, or ensuring code reliability. Based on ISTQB standards and industry best practices.
license: Cristian Custom
---

# Testing Strategy & Quality Assurance

## When to use this skill

Use this skill when:
- Designing test strategies and test plans
- Writing test code (unit, integration, e2e tests)
- Setting up automated testing in CI/CD pipelines
- Defining quality gates and acceptance criteria
- Managing test coverage and metrics
- Creating defect management processes
- Establishing testing standards for teams

## How to use this skill

### 1. Testing Pyramid & Coverage Strategy

Build tests at multiple levels with right distribution:

```
        E2E Tests (5-10%)
       /                \
    Integration Tests (20-30%)
    /                      \
Unit Tests (60-70%)
```

**Unit Tests (Core)**
- Test individual functions/methods in isolation
- Mock external dependencies (APIs, DBs, services)
- Fast execution (< 1 second each)
- No side effects, deterministic
- Coverage target: 80%+ for business logic

**Integration Tests**
- Test multiple components working together
- Use test databases or in-memory services
- Verify data flow between layers
- Slower than unit tests (1-10 seconds each)
- Focus on critical paths

**End-to-End Tests (E2E)**
- Test complete user workflows
- Use staging/test environment
- Slowest but most realistic (10+ seconds each)
- Test happy paths + critical failure scenarios
- Cover 20-30% of critical features only

---

### 2. Test Types by Purpose

#### Functional Testing
Verify that features work as specified.

```python
import pytest
from user_service import create_user, get_user

def test_create_user_success():
    """User creation with valid data succeeds."""
    result = create_user(email="test@example.com", name="John")
    assert result.status == "success"
    assert result.user_id is not None

def test_create_user_duplicate_email():
    """Duplicate email rejection."""
    create_user(email="test@example.com", name="John")
    
    with pytest.raises(ValueError, match="Email already exists"):
        create_user(email="test@example.com", name="Jane")

def test_get_user_not_found():
    """Getting non-existent user returns None."""
    result = get_user(user_id="nonexistent")
    assert result is None
```

#### Boundary Value Testing
Test edge cases and limits.

```python
def test_age_validation():
    """Age must be 0-150."""
    # Valid boundaries
    assert validate_age(0) == True
    assert validate_age(150) == True
    
    # Invalid boundaries
    assert validate_age(-1) == False
    assert validate_age(151) == False

def test_string_length_limits():
    """Name must be 1-100 characters."""
    assert validate_name("A") == True
    assert validate_name("A" * 100) == True
    assert validate_name("") == False
    assert validate_name("A" * 101) == False
```

#### State Transition Testing
Test state changes and workflows.

```python
def test_order_state_transitions():
    """Order follows valid state transitions."""
    order = Order(state="created")
    
    # Valid: created -> processing
    order.transition("processing")
    assert order.state == "processing"
    
    # Valid: processing -> shipped
    order.transition("shipped")
    assert order.state == "shipped"
    
    # Invalid: shipped -> created
    with pytest.raises(ValueError, match="Invalid transition"):
        order.transition("created")
```

#### Property-Based Testing
Generate random inputs to find edge cases.

```python
from hypothesis import given, strategies as st

@given(
    amount=st.floats(min_value=0.01, max_value=1_000_000),
    tax_rate=st.floats(min_value=0, max_value=1)
)
def test_tax_calculation_properties(amount, tax_rate):
    """Tax is always non-negative and <= amount."""
    tax = calculate_tax(amount, tax_rate)
    assert tax >= 0
    assert tax <= amount
    # Tax with rate 0 should be 0
    assert calculate_tax(amount, 0) == 0
```

---

### 3. Test Quality Checklist

Ensure tests are reliable and maintainable:

- [ ] **Independence**: Each test runs alone, no shared state
- [ ] **Determinism**: Same input always gives same output (use fixed random seeds)
- [ ] **Speed**: Unit tests < 1s, integration < 10s, E2E < 60s
- [ ] **Clarity**: Test names describe what is being tested, not how
  - ✅ `test_create_user_with_invalid_email_fails`
  - ❌ `test_create_user_1`
- [ ] **Isolation**: Mock external calls (APIs, DBs, services)
- [ ] **Single responsibility**: One assertion per test (or related assertions)
- [ ] **Meaningful assertions**: Clear failure messages
  - ✅ `assert result.status == "success", f"Expected success, got {result.status}"`
  - ❌ `assert result`
- [ ] **No test interdependencies**: Tests can run in any order
- [ ] **Coverage of edge cases**: Boundary values, error paths, empty inputs
- [ ] **No hardcoded data**: Use fixtures or parameterization

---

### 4. Test Fixtures & Parameterization

Reduce code duplication:

```python
import pytest

# Fixture: reusable test data
@pytest.fixture
def valid_user_data():
    return {
        "email": "test@example.com",
        "name": "John Doe",
        "age": 30
    }

@pytest.fixture
def mock_database(mocker):
    """Mock database for testing without real DB."""
    db_mock = mocker.MagicMock()
    db_mock.save.return_value = True
    return db_mock

# Test using fixture
def test_create_user(valid_user_data, mock_database):
    result = create_user(**valid_user_data, db=mock_database)
    assert result.status == "success"
    mock_database.save.assert_called_once()

# Parameterization: test multiple scenarios
@pytest.mark.parametrize("amount,expected_fee", [
    (100, 0),        # < $100: no fee
    (100, 1),        # $100-1000: $1 fee
    (1000, 5),       # $1000+: $5 fee
])
def test_transaction_fees(amount, expected_fee):
    fee = calculate_fee(amount)
    assert fee == expected_fee
```

---

### 5. Mocking & Test Doubles

Isolate code under test:

```python
from unittest.mock import Mock, patch, MagicMock

def test_payment_processor_with_mock():
    """Test payment processing without calling real API."""
    
    # Create mock payment gateway
    mock_gateway = Mock()
    mock_gateway.charge.return_value = {"status": "success", "id": "tx_123"}
    
    # Test code that uses the mock
    processor = PaymentProcessor(gateway=mock_gateway)
    result = processor.process_payment(amount=50.00, card="4111...")
    
    # Verify the mock was called correctly
    mock_gateway.charge.assert_called_once_with(
        amount=50.00,
        card="4111..."
    )
    assert result["status"] == "success"

# Patch external service
@patch("requests.post")
def test_api_call_with_patch(mock_post):
    """Test code that calls external API without making real request."""
    mock_post.return_value.json.return_value = {"result": "ok"}
    
    response = fetch_external_data()
    
    assert response["result"] == "ok"
    mock_post.assert_called_once()
```

---

### 6. Test Organization & Structure

```
project/
├── src/
│   ├── core/
│   │   ├── user.py
│   │   ├── payment.py
│   │   └── __init__.py
│   └── __init__.py
│
├── tests/
│   ├── unit/
│   │   ├── test_user.py          # Tests for user.py
│   │   ├── test_payment.py        # Tests for payment.py
│   │   └── __init__.py
│   │
│   ├── integration/
│   │   ├── test_user_flow.py      # User creation to profile update
│   │   ├── test_payment_flow.py   # Payment to receipt
│   │   └── __init__.py
│   │
│   ├── e2e/
│   │   ├── test_checkout.py       # Full checkout workflow
│   │   ├── test_signup.py         # Registration to first order
│   │   └── __init__.py
│   │
│   ├── fixtures/                  # Shared test data
│   │   ├── users.py
│   │   ├── payments.py
│   │   └── __init__.py
│   │
│   └── conftest.py                # Pytest configuration & shared fixtures
│
├── pytest.ini                      # Pytest settings
├── .coveragerc                     # Coverage configuration
└── requirements-test.txt           # Test dependencies
```

**conftest.py** example:

```python
import pytest
from your_app import db

@pytest.fixture(scope="session")
def test_db():
    """Create test database once per session."""
    db.create_test_tables()
    yield db
    db.drop_test_tables()

@pytest.fixture
def client(test_db):
    """Provide API test client."""
    from your_app import app
    app.config["DATABASE"] = test_db
    return app.test_client()

@pytest.fixture(autouse=True)
def cleanup():
    """Clean up after each test."""
    yield
    test_db.clear()
```

---

### 7. Running Tests & Coverage

**Python:**
```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=src --cov-report=html

# Run specific test file
pytest tests/unit/test_user.py

# Run with verbose output
pytest -v

# Run only fast tests (skip slow E2E)
pytest -m "not slow"

# Run and stop on first failure
pytest -x
```

**TypeScript/JavaScript:**
```bash
# Run tests with Jest
npm test

# With coverage
npm test -- --coverage

# Watch mode (re-run on file changes)
npm test -- --watch

# Run specific test
npm test -- --testNamePattern="should create user"
```

---

### 8. CI/CD Integration

**GitHub Actions example:**

```yaml
name: Tests & Quality Gates

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-test.txt
      
      - name: Lint
        run: |
          ruff check src/
          black src/ --check
      
      - name: Run tests
        run: pytest --cov=src --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml
      
      - name: Check coverage threshold
        run: |
          coverage report --fail-under=80
```

---

### 9. Test Metrics & Reporting

Track these key metrics:

| Metric | Target | Tool |
|--------|--------|------|
| Code Coverage | 80%+ | coverage.py, Jest coverage |
| Pass Rate | 100% | CI/CD dashboard |
| Test Execution Time | < 5 min | GitHub Actions logs |
| Flaky Tests | 0% | Test dashboards |
| Defect Escape Rate | < 5% | Bug tracking system |

```python
# Generate coverage report
coverage run -m pytest
coverage report
coverage html  # Creates htmlcov/index.html

# Coverage badge for README
# ![Coverage](https://img.shields.io/badge/coverage-85%25-green)
```

---

### 10. Common Testing Pitfalls to Avoid

| Pitfall | Problem | Solution |
|---------|---------|----------|
| **Testing implementation** | Tests break when code refactors | Test behavior, not implementation |
| **Too many assertions** | Hard to tell what failed | One logical assertion per test |
| **Shared test state** | Tests fail when run together | Use fixtures, clean up after each test |
| **No mocking** | Tests hit real APIs/DBs | Mock external dependencies |
| **Sleep in tests** | Tests are slow, flaky | Use test doubles, avoid timing |
| **Hardcoded data** | Tests fail with different data | Parameterize, use factories |
| **Testing trivial code** | Wasted effort | Focus on business logic |
| **Ignoring edge cases** | Production bugs surprise you | Test boundaries, error paths |

---

### 11. Defect Management Process

When tests fail or bugs are found:

```python
# 1. Write test that reproduces the bug
def test_payment_over_limit_rejected():
    """Regression test: payment should reject amounts > $10,000."""
    with pytest.raises(ValueError, match="exceeds maximum"):
        process_payment(amount=15000)

# 2. Fix the bug
def process_payment(amount):
    if amount > 10000:
        raise ValueError("Amount exceeds maximum allowed")
    # ... rest of logic

# 3. Verify test passes
# pytest tests/integration/test_payment.py::test_payment_over_limit_rejected

# 4. Log in defect tracker with:
# - ID: BUG-234
# - Severity: High (payments affected)
# - Test: test_payment_over_limit_rejected
# - Fix commit: abc1234
```

---

### 12. Test Data Management

Create realistic test data without hardcoding:

```python
from factory import Factory
from faker import Faker

fake = Faker()

class UserFactory(Factory):
    """Factory for creating test users."""
    class Meta:
        model = User
    
    email = fake.email()
    name = fake.name()
    age = fake.random_int(min=18, max=80)
    is_active = True

# Use in tests
def test_user_creation():
    user = UserFactory()
    assert user.email is not None
    assert user.age >= 18

# Create multiple variations
def test_inactive_users_excluded():
    active_user = UserFactory(is_active=True)
    inactive_user = UserFactory(is_active=False)
    
    result = get_active_users()
    assert active_user in result
    assert inactive_user not in result
```

---

## Keywords

testing strategy, unit tests, integration tests, e2e tests, test coverage, pytest, jest, vitest, mocking, CI/CD, automation, quality assurance, defect management, test fixtures, ISTQB, coverage metrics, testing pyramid
