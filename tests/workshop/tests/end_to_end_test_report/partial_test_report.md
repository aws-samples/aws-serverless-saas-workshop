# End-to-End AWS Testing Report

**Generated:** 2026-01-31 16:11:55

## Summary

**Status:** ❌ 1 of 2 test steps failed (Duration: 0:21:58.580339)

- **Start Time:** 2026-01-31 15:49:56
- **End Time:** 2026-01-31 16:11:55
- **Total Duration:** 0:21:58.580339
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
| Step 1: Initial Cleanup | 0:01:22.099022 | 82.10s |
| Step 2: Full Deployment | 0:16:36.460058 | 996.46s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:16:36.460058 (996.46s)
2. **Step 1: Initial Cleanup**: 0:01:22.099022 (82.10s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:01:17.327349
- **Start Time:** 2026-01-31 15:49:59
- **End Time:** 2026-01-31 15:51:16

### ❌ Step 2: Full Deployment

- **Status:** Failed
- **Duration:** 0:16:21.146515
- **Start Time:** 2026-01-31 15:53:21
- **End Time:** 2026-01-31 16:09:42

## Resource State Changes

### Step 1: Initial Cleanup

### Step 2: Full Deployment

**Created Resources:** 142
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab6-CustomResources-14BRNUQQ5YIZN
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-M75QJ4QTDMB1
- CloudFormation::Stack: serverless-saas-lab2-APIGatewayLambdaPermissions-4CGTNPOQYH0X
- CloudFormation::Stack: serverless-saas-shared-lab6-APIs-J4CM6DB87AWM
- CloudFormation::Stack: serverless-saas-lab2-APIs-1SQM0UH5TNDBD
- CloudFormation::Stack: serverless-saas-shared-lab6-LambdaFunctions-QHJFZHFCUFT7
- CloudFormation::Stack: serverless-saas-lab2-LambdaFunctions-1X2ICDN3CNB11
- CloudFormation::Stack: serverless-saas-shared-lab5
- *(and 132 more)*

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
## ⚠️ Failures

### Step 2: Full Deployment

