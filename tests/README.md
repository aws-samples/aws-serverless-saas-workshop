# Workshop Modernization Tests

This directory contains property-based tests and unit tests for the AWS Serverless SaaS Workshop modernization effort.

## Setup

Install test dependencies:

```
pip install -r requirements.txt
```

## Running Tests

Run all tests:

```
pytest -v
```

Run specific test file:

```
pytest test_python_runtime_consistency.py -v
```

Run with detailed output:

```
pytest test_python_runtime_consistency.py -v --tb=short
```

## Property-Based Tests

Property-based tests use Hypothesis to generate test cases and verify properties hold across all inputs. Each property test runs a minimum of 100 iterations.

### Property 2: Python Runtime Consistency

**File**: `test_python_runtime_consistency.py`

**Property**: For any Lambda function in any lab, the runtime should be python3.14.

**Validates**: Requirements 2.1

This test:
- Scans all SAM/CloudFormation templates across all 7 labs
- Extracts all Lambda function configurations
- Verifies each function uses Python 3.14 runtime
- Verifies Lambda layers are compatible with Python 3.14

## Test Structure

Each property test includes:
- A comment tag: `# Feature: workshop-modernization, Property N: [Property Name]`
- Hypothesis `@settings(max_examples=100)` decorator for 100 iterations
- Clear property statement in docstring
- Validation against specific requirements

## Troubleshooting

If tests fail:
1. Check the error message for specific violations
2. Review the template file mentioned in the error
3. Update the Lambda function runtime to python3.14
4. Re-run the tests to verify the fix
