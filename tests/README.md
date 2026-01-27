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

### Property 1: Lab Cleanup Isolation

**File**: `test_cleanup_lab_isolation.py`

**Property**: For any lab N and set of other labs M, cleaning up lab N should not affect resources in any lab M (where N ≠ M).

**Validates**: Requirements 1.1, 1.2 (Lab Cleanup Isolation)

This test:
- Simulates deployment of multiple labs simultaneously
- Simulates cleanup of one lab
- Verifies other labs' resources remain intact
- Tests all lab combinations (Lab1-Lab7)
- Specifically validates the critical bug fix: Lab5 cleanup does NOT delete Lab6 or Lab7 resources

**Key Tests**:
1. `test_cleanup_lab_isolation_property` - General isolation property (100 examples)
2. `test_cleanup_lab_pair_isolation_property` - All lab pairs (21 combinations)
3. `test_lab5_cleanup_does_not_affect_lab6_lab7_property` - Critical bug validation
4. `test_sequential_cleanup_all_labs` - Sequential cleanup simulation
5. `test_all_lab_combinations_isolation` - Comprehensive validation

### Property 2: Complete Cleanup

**File**: `test_cleanup_completeness.py`

**Property**: Cleanup of Lab N must delete ALL resources belonging to Lab N.

**Validates**: Requirements 1.3 (Complete Cleanup)

This test:
- Simulates deployment of a lab (generates all resources)
- Records all created resources (stacks, S3 buckets, CloudWatch logs, DynamoDB tables, etc.)
- Simulates cleanup execution
- Verifies all recorded resources are deleted
- Tests all labs (Lab1-Lab7)
- Validates complete cleanup across all resource types

**Key Tests**:
1. `test_cleanup_completeness_property` - Complete cleanup for any single lab (100 examples)
2. `test_cleanup_all_resource_types_property` - Validates all resource types are deleted (100 examples)
3. `test_cleanup_completeness_multi_lab_property` - Multi-lab environment testing (100 examples)
4. `test_sequential_cleanup_completeness_all_labs` - Sequential cleanup workflow
5. `test_lab5_cleanup_completeness` - Critical test for Lab5 (most complex architecture)

**Resource Types Tracked**:
- CloudFormation stacks (main, shared, tenant, pipeline)
- S3 buckets (artifacts, pipeline, CUR)
- CloudWatch log groups (Lambda, API Gateway)
- Cognito user pools
- CodeCommit repositories
- DynamoDB tables

### Property 3: Python Runtime Consistency

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
