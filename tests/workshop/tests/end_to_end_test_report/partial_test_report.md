# End-to-End AWS Testing Report

**Generated:** 2026-01-31 08:20:10

## Summary

**Status:** ❌ 1 of 2 test steps failed (Duration: 0:38:23.159127)

- **Start Time:** 2026-01-31 07:41:47
- **End Time:** 2026-01-31 08:20:10
- **Total Duration:** 0:38:23.159127
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
| Step 1: Initial Cleanup | 0:12:45.701607 | 765.70s |
| Step 2: Full Deployment | 0:21:37.444381 | 1297.44s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:21:37.444381 (1297.44s)
2. **Step 1: Initial Cleanup**: 0:12:45.701607 (765.70s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:12:28.985762
- **Start Time:** 2026-01-31 07:42:01
- **End Time:** 2026-01-31 07:54:30

### ❌ Step 2: Full Deployment

- **Status:** Failed
- **Duration:** 0:21:21.762108
- **Start Time:** 2026-01-31 07:56:35
- **End Time:** 2026-01-31 08:17:57

## Resource State Changes

### Step 1: Initial Cleanup

**Deleted Resources:** 242
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

### Step 2: Full Deployment

**Created Resources:** 242
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-1QFPYZOMLE6L4
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-ERPDNBONAC8Q
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-47ZLP6PL6NN
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-147JT35N9ZWLJ
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-17KPYHCHQTM98
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab3-APIGatewayLambdaPermissions-EAMFD2ZEEXMP
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-12J6105LY9GHE
- *(and 232 more)*

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
## ⚠️ Failures

### Step 2: Full Deployment

