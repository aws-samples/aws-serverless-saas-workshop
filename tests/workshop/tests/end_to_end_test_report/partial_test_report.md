# End-to-End AWS Testing Report

**Generated:** 2026-01-31 07:40:42

## Summary

**Status:** ❌ 1 of 2 test steps failed (Duration: 0:27:30.902323)

- **Start Time:** 2026-01-31 07:13:11
- **End Time:** 2026-01-31 07:40:42
- **Total Duration:** 0:27:30.902323
- **Total Steps:** 2
- **Successful Steps:** 1
- **Failed Steps:** 1

## Configuration

```yaml
aws_profile: serverless-saas-demo
aws_region: us-east-1
email: lancdieg@amazon.com
tenant_email: None
parallel_mode: True
timeout_hours: 6
log_directory: workshop/tests/end_to_end_test_report/logs
report_directory: workshop/tests/end_to_end_test_report
```

## Timing Metrics

| Operation | Duration | Duration (seconds) |
|-----------|----------|--------------------|
| Step 1: Initial Cleanup | 0:01:42.714725 | 102.71s |
| Step 2: Full Deployment | 0:21:48.161672 | 1308.16s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:21:48.161672 (1308.16s)
2. **Step 1: Initial Cleanup**: 0:01:42.714725 (102.71s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:01:37.695009
- **Start Time:** 2026-01-31 07:13:13
- **End Time:** 2026-01-31 07:14:51

### ❌ Step 2: Full Deployment

- **Status:** Failed
- **Duration:** 0:21:31.212013
- **Start Time:** 2026-01-31 07:16:56
- **End Time:** 2026-01-31 07:38:27

## Resource State Changes

### Step 1: Initial Cleanup

### Step 2: Full Deployment

**Created Resources:** 242
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-1KRN9HP5320I1
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-GP00TK28EJP6
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-1L7H6SW6T530G
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-1C58JH1V41XAQ
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-1NYHGG56S4RWZ
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-13A30GC51F7FT
- CloudFormation::Stack: serverless-saas-shared-lab6-CustomResources-P5OFR691BGFC
- *(and 232 more)*

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
## ⚠️ Failures

### Step 2: Full Deployment

