# End-to-End AWS Testing Report

**Generated:** 2026-01-31 15:44:40

## Summary

**Status:** ❌ 1 of 10 test steps failed (Duration: 1:52:04.715582)

- **Start Time:** 2026-01-31 13:52:35
- **End Time:** 2026-01-31 15:44:40
- **Total Duration:** 1:52:04.715582
- **Total Steps:** 10
- **Successful Steps:** 9
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
| Step 1: Initial Cleanup | 0:12:58.037759 | 778.04s |
| Step 2: Full Deployment | 0:21:18.913546 | 1278.91s |
| Step 3: Lab1 Isolation Test | 0:05:21.804092 | 321.80s |
| Step 4: Lab2 Isolation Test | 0:08:02.935622 | 482.94s |
| Step 5: Lab3 Isolation Test | 0:12:39.596042 | 759.60s |
| Step 6: Lab4 Isolation Test | 0:08:16.152856 | 496.15s |
| Step 7: Lab5 Isolation Test | 0:08:50.549146 | 530.55s |
| Step 8: Lab6 Isolation Test | 0:12:02.087489 | 722.09s |
| Step 9: Lab7 Isolation Test | 0:03:14.071880 | 194.07s |
| Step 10: Final Cleanup | 0:01:20.550559 | 80.55s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:21:18.913546 (1278.91s)
2. **Step 1: Initial Cleanup**: 0:12:58.037759 (778.04s)
3. **Step 5: Lab3 Isolation Test**: 0:12:39.596042 (759.60s)
4. **Step 8: Lab6 Isolation Test**: 0:12:02.087489 (722.09s)
5. **Step 7: Lab5 Isolation Test**: 0:08:50.549146 (530.55s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:12:42.472788
- **Start Time:** 2026-01-31 13:52:48
- **End Time:** 2026-01-31 14:05:30

### ✅ Step 2: Full Deployment

- **Status:** Success
- **Duration:** 0:21:02.120560
- **Start Time:** 2026-01-31 14:07:36
- **End Time:** 2026-01-31 14:28:38

### ✅ Step 3: Lab1 Isolation Test

- **Status:** Success
- **Duration:** 0:04:53.878701
- **Start Time:** 2026-01-31 14:31:05
- **End Time:** 2026-01-31 14:35:59

### ❌ Step 4: Lab2 Isolation Test

- **Status:** Failed
- **Duration:** 0:07:34.783953
- **Start Time:** 2026-01-31 14:38:29
- **End Time:** 2026-01-31 14:46:04

### ✅ Step 5: Lab3 Isolation Test

- **Status:** Success
- **Duration:** 0:12:15.694448
- **Start Time:** 2026-01-31 14:48:30
- **End Time:** 2026-01-31 15:00:45

### ✅ Step 6: Lab4 Isolation Test

- **Status:** Success
- **Duration:** 0:07:57.467007
- **Start Time:** 2026-01-31 15:03:06
- **End Time:** 2026-01-31 15:11:04

### ✅ Step 7: Lab5 Isolation Test

- **Status:** Success
- **Duration:** 0:08:37.063938
- **Start Time:** 2026-01-31 15:13:20
- **End Time:** 2026-01-31 15:21:57

### ✅ Step 8: Lab6 Isolation Test

- **Status:** Success
- **Duration:** 0:11:50.401492
- **Start Time:** 2026-01-31 15:24:10
- **End Time:** 2026-01-31 15:36:00

### ✅ Step 9: Lab7 Isolation Test

- **Status:** Success
- **Duration:** 0:03:05.751752
- **Start Time:** 2026-01-31 15:38:11
- **End Time:** 2026-01-31 15:41:16

### ✅ Step 10: Final Cleanup

- **Status:** Success
- **Duration:** 0:01:15.298070
- **Start Time:** 2026-01-31 15:43:22
- **End Time:** 2026-01-31 15:44:37

## Resource State Changes

### Step 1: Initial Cleanup

**Deleted Resources:** 244
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
- *(and 234 more)*

### Step 2: Full Deployment

**Created Resources:** 257
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-PC37ZGS2S0G1
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-DFJ3Q77K0XGC
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-1X313TAO8THST
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-1HE2ERMRH1TP1
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-1P05712QCSGPB
- CloudFormation::Stack: serverless-saas-shared-lab4-APIGatewayLambdaPermissions-DSHFTZCRRREZ
- *(and 247 more)*

### Step 3: Lab1 Isolation Test

**Deleted Resources:** 13
- CloudFormation::Stack: serverless-saas-lab1
- S3::Bucket: serverless-saas-lab1-app-7f2975e0
- Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-workshop-lab1-api
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-CreateOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-CreateProductFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-DeleteOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-DeleteProductFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetOrderFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetOrdersFunction
- Logs::LogGroup: /aws/lambda/serverless-saas-lab1-GetProductFunction
- *(and 3 more)*

### Step 4: Lab2 Isolation Test

**Deleted Resources:** 35
- CloudFormation::Stack: serverless-saas-lab2-APIGatewayLambdaPermissions-5A81E3NV79VO
- CloudFormation::Stack: serverless-saas-lab2-APIs-IPBL2L6SY4ZR
- CloudFormation::Stack: serverless-saas-lab2-LambdaFunctions-MNY2PF2MNL9L
- CloudFormation::Stack: serverless-saas-lab2-Cognito-QIBSU1KQXEC6
- CloudFormation::Stack: serverless-saas-lab2-UserInterface-GWXA2UU7MQ7V
- CloudFormation::Stack: serverless-saas-lab2-DynamoDBTables-1VUPZI0F29M77
- CloudFormation::Stack: serverless-saas-lab2
- S3::Bucket: serverless-saas-lab2-admin-45957860
- S3::Bucket: serverless-saas-lab2-landing-45957860
- Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-lab2-admin-api
- *(and 25 more)*

### Step 5: Lab3 Isolation Test

**Deleted Resources:** 44
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-shared-lab3-APIGatewayLambdaPermissions-HGL7FTCH7MFH
- CloudFormation::Stack: serverless-saas-shared-lab3-APIs-8B7S8WZQHDO3
- CloudFormation::Stack: serverless-saas-shared-lab3-LambdaFunctions-13Z8VDF54INF6
- CloudFormation::Stack: serverless-saas-shared-lab3-Cognito-ZZWV1XT4YS9R
- CloudFormation::Stack: serverless-saas-shared-lab3-DynamoDBTables-THAK8KKSTIP6
- CloudFormation::Stack: serverless-saas-shared-lab3-UserInterface-1EPRGVQKI4FRT
- CloudFormation::Stack: serverless-saas-shared-lab3
- S3::Bucket: serverless-saas-shared-lab3-useri-landingappbucket-tiop9pajrr3f
- S3::Bucket: serverless-saas-shared-lab3-userint-adminappbucket-dpvxxvfyrvdr
- *(and 34 more)*

### Step 6: Lab4 Isolation Test

**Deleted Resources:** 44
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-shared-lab4-APIGatewayLambdaPermissions-DSHFTZCRRREZ
- CloudFormation::Stack: serverless-saas-shared-lab4-APIs-PX87TUB9DJZJ
- CloudFormation::Stack: serverless-saas-shared-lab4-LambdaFunctions-1MCCZDT9AZKVP
- CloudFormation::Stack: serverless-saas-shared-lab4-Cognito-1QTNBPBED61VU
- CloudFormation::Stack: serverless-saas-shared-lab4-DynamoDBTables-QRB9I0J2A6PG
- CloudFormation::Stack: serverless-saas-shared-lab4-UserInterface-JUIKJHKS6IKW
- CloudFormation::Stack: serverless-saas-shared-lab4
- S3::Bucket: serverless-saas-lab4-admin-6022cd90
- S3::Bucket: serverless-saas-lab4-app-6022cd90
- *(and 34 more)*

### Step 7: Lab5 Isolation Test

**Deleted Resources:** 50
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-PC37ZGS2S0G1
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-DFJ3Q77K0XGC
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-1X313TAO8THST
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-1HE2ERMRH1TP1
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-1P05712QCSGPB
- CloudFormation::Stack: serverless-saas-shared-lab5-DynamoDBTables-3YI1RMTF48RU
- CloudFormation::Stack: serverless-saas-shared-lab5-UserInterface-15C593N1PFZCG
- CloudFormation::Stack: serverless-saas-shared-lab5
- CloudFormation::Stack: serverless-saas-pipeline-lab5
- S3::Bucket: serverless-saas-lab5-admin-f1c73240
- *(and 40 more)*

### Step 8: Lab6 Isolation Test

**Deleted Resources:** 65
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab6-CustomResources-XR92PQ4B1K52
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-1D6JAZ2L7335B
- CloudFormation::Stack: serverless-saas-shared-lab6-APIs-1NMHMAFLWMJ4W
- CloudFormation::Stack: serverless-saas-shared-lab6-LambdaFunctions-109FUALYTT8OH
- CloudFormation::Stack: serverless-saas-shared-lab6-Cognito-OZVD4SNDS53F
- CloudFormation::Stack: serverless-saas-shared-lab6-UserInterface-8IZVCA5XC24J
- CloudFormation::Stack: serverless-saas-shared-lab6-DynamoDBTables-1JA9CXDTAN59A
- CloudFormation::Stack: serverless-saas-shared-lab6
- *(and 55 more)*

### Step 9: Lab7 Isolation Test

**Deleted Resources:** 6
- CloudFormation::Stack: stack-pooled-lab7
- CloudFormation::Stack: serverless-saas-lab7
- S3::Bucket: serverless-saas-lab7-cur-2a51f290
- Logs::LogGroup: /aws/lambda/serverless-saas-lab7-aws-cur-initializer
- Logs::LogGroup: /aws/lambda/serverless-saas-lab7-dynamodb-cost
- Logs::LogGroup: /aws/lambda/serverless-saas-lab7-lambda-cost

### Step 10: Final Cleanup

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
## Lab Isolation Verification

### ✅ Lab1

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes
- **Orphaned Resources Found:** 41
  - CloudFormation::Stack: stack-lab6-pooled
  - CloudFormation::Stack: stack-pooled-lab7
  - Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-admin-api-lab3
  - Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-admin-api-lab4
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-BusinessServicesAuthorizerFunction

### ✅ Lab3

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes
- **Orphaned Resources Found:** 32
  - CloudFormation::Stack: stack-lab6-pooled
  - CloudFormation::Stack: stack-pooled-lab7
  - Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-admin-api-lab4
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-BusinessServicesAuthorizerFunction
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-CreateOrderFunction

### ✅ Lab4

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes
- **Orphaned Resources Found:** 27
  - CloudFormation::Stack: stack-lab6-pooled
  - CloudFormation::Stack: stack-pooled-lab7
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-BusinessServicesAuthorizerFunction
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-CreateOrderFunction
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-CreateProductFunction

### ✅ Lab5

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes
- **Orphaned Resources Found:** 21
  - CloudFormation::Stack: stack-lab6-pooled
  - CloudFormation::Stack: stack-pooled-lab7
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-BusinessServicesAuthorizerFunction
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-CreateOrderFunction
  - Logs::LogGroup: /aws/lambda/stack-lab6-pooled-CreateProductFunction

### ✅ Lab6

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes
- **Orphaned Resources Found:** 1
  - CloudFormation::Stack: stack-pooled-lab7

### ✅ Lab7

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

## ⚠️ Failures

### Step 4: Lab2 Isolation Test

