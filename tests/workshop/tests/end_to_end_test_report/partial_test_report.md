# End-to-End AWS Testing Report

**Generated:** 2026-01-31 09:18:50

## Summary

**Status:** ✅ All 3 test steps completed successfully in 0:44:08.095963

- **Start Time:** 2026-01-31 08:34:41
- **End Time:** 2026-01-31 09:18:50
- **Total Duration:** 0:44:08.095963
- **Total Steps:** 3
- **Successful Steps:** 3
- **Failed Steps:** 0

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
| Step 1: Initial Cleanup | 0:13:47.710915 | 827.71s |
| Step 2: Full Deployment | 0:19:47.685605 | 1187.69s |
| Step 3: Lab1 Isolation Test | 0:04:32.671998 | 272.67s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:19:47.685605 (1187.69s)
2. **Step 1: Initial Cleanup**: 0:13:47.710915 (827.71s)
3. **Step 3: Lab1 Isolation Test**: 0:04:32.671998 (272.67s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:13:32.271645
- **Start Time:** 2026-01-31 08:34:55
- **End Time:** 2026-01-31 08:48:27

### ✅ Step 2: Full Deployment

- **Status:** Success
- **Duration:** 0:19:31.782358
- **Start Time:** 2026-01-31 08:50:32
- **End Time:** 2026-01-31 09:10:03

### ✅ Step 3: Lab1 Isolation Test

- **Status:** Success
- **Duration:** 0:04:07.111967
- **Start Time:** 2026-01-31 09:12:30
- **End Time:** 2026-01-31 09:16:37

## Resource State Changes

### Step 1: Initial Cleanup

**Deleted Resources:** 257
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-1QFPYZOMLE6L4
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-ERPDNBONAC8Q
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-47ZLP6PL6NN
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-147JT35N9ZWLJ
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-17KPYHCHQTM98
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab3-APIGatewayLambdaPermissions-EAMFD2ZEEXMP
- *(and 247 more)*

### Step 2: Full Deployment

**Created Resources:** 257
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-1PC30BZ1Y8NCX
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-1C5LGRK2QMJWR
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-60RANNEFZX5M
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-GXCGQ2LX1CX9
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-NFK1M7LNZ8U4
- CloudFormation::Stack: serverless-saas-shared-lab4-APIGatewayLambdaPermissions-OL7ZVCOU2GAR
- *(and 247 more)*

### Step 3: Lab1 Isolation Test

**Deleted Resources:** 13
- CloudFormation::Stack: serverless-saas-lab1
- S3::Bucket: serverless-saas-lab1-app-2cd0d940
- Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-workshop-lab1-api
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-CreateOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-CreateProductFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-DeleteOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-DeleteProductFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetOrdersFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetProductFunction
- *(and 3 more)*

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
