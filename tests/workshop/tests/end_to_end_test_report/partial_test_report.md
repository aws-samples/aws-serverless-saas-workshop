# End-to-End AWS Testing Report

**Generated:** 2026-01-31 21:55:35

## Summary

**Status:** ✅ All 10 test steps completed successfully in 1:49:36.611861

- **Start Time:** 2026-01-31 20:05:58
- **End Time:** 2026-01-31 21:55:35
- **Total Duration:** 1:49:36.611861
- **Total Steps:** 10
- **Successful Steps:** 10
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
| Step 1: Initial Cleanup | 0:13:48.509357 | 828.51s |
| Step 2: Full Deployment | 0:21:26.257700 | 1286.26s |
| Step 3: Lab1 Isolation Test | 0:05:41.971725 | 341.97s |
| Step 4: Lab2 Isolation Test | 0:07:36.172409 | 456.17s |
| Step 5: Lab3 Isolation Test | 0:08:50.535859 | 530.54s |
| Step 6: Lab4 Isolation Test | 0:08:45.063352 | 525.06s |
| Step 7: Lab5 Isolation Test | 0:09:29.653094 | 569.65s |
| Step 8: Lab6 Isolation Test | 0:10:59.689510 | 659.69s |
| Step 9: Lab7 Isolation Test | 0:03:28.458742 | 208.46s |
| Step 10: Final Cleanup | 0:01:30.228621 | 90.23s |

### Slowest Operations

1. **Step 2: Full Deployment**: 0:21:26.257700 (1286.26s)
2. **Step 1: Initial Cleanup**: 0:13:48.509357 (828.51s)
3. **Step 8: Lab6 Isolation Test**: 0:10:59.689510 (659.69s)
4. **Step 7: Lab5 Isolation Test**: 0:09:29.653094 (569.65s)
5. **Step 5: Lab3 Isolation Test**: 0:08:50.535859 (530.54s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:13:37.881596
- **Start Time:** 2026-01-31 20:06:06
- **End Time:** 2026-01-31 20:19:44

### ✅ Step 2: Full Deployment

- **Status:** Success
- **Duration:** 0:21:10.674534
- **Start Time:** 2026-01-31 20:21:49
- **End Time:** 2026-01-31 20:43:00

### ✅ Step 3: Lab1 Isolation Test

- **Status:** Success
- **Duration:** 0:05:02.692005
- **Start Time:** 2026-01-31 20:45:26
- **End Time:** 2026-01-31 20:50:29

### ✅ Step 4: Lab2 Isolation Test

- **Status:** Success
- **Duration:** 0:07:06.770006
- **Start Time:** 2026-01-31 20:53:11
- **End Time:** 2026-01-31 21:00:18

### ✅ Step 5: Lab3 Isolation Test

- **Status:** Success
- **Duration:** 0:08:28.441774
- **Start Time:** 2026-01-31 21:02:43
- **End Time:** 2026-01-31 21:11:12

### ✅ Step 6: Lab4 Isolation Test

- **Status:** Success
- **Duration:** 0:08:25.644791
- **Start Time:** 2026-01-31 21:13:32
- **End Time:** 2026-01-31 21:21:57

### ✅ Step 7: Lab5 Isolation Test

- **Status:** Success
- **Duration:** 0:09:15.044282
- **Start Time:** 2026-01-31 21:24:15
- **End Time:** 2026-01-31 21:33:30

### ✅ Step 8: Lab6 Isolation Test

- **Status:** Success
- **Duration:** 0:10:51.429076
- **Start Time:** 2026-01-31 21:35:42
- **End Time:** 2026-01-31 21:46:33

### ✅ Step 9: Lab7 Isolation Test

- **Status:** Success
- **Duration:** 0:03:23.200165
- **Start Time:** 2026-01-31 21:48:39
- **End Time:** 2026-01-31 21:52:02

### ✅ Step 10: Final Cleanup

- **Status:** Success
- **Duration:** 0:01:25.114320
- **Start Time:** 2026-01-31 21:54:07
- **End Time:** 2026-01-31 21:55:33

## Resource State Changes

### Step 1: Initial Cleanup

**Deleted Resources:** 119
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-1U12SWWZAVK55
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-69B7LKSYGTSS
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-1PR0GF2V0BYU2
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-MUR4YHF3ED2J
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-18BS13DUI2CFW
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-6XJ4IN3YPYAZ
- CloudFormation::Stack: serverless-saas-shared-lab6-CustomResources-17KOMJUTGESOB
- CloudFormation::Stack: serverless-saas-shared-lab6-APIs-17JWJHR57YALJ
- *(and 109 more)*

### Step 2: Full Deployment

**Created Resources:** 257
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-5CAORS2DNUV8
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-184TD2LW6K59T
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-LLE6VQT0GG71
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-HKKUCORAF7ZH
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-8GEE5P43QP1A
- CloudFormation::Stack: serverless-saas-shared-lab4-APIGatewayLambdaPermissions-1JAL2K55KOLLU
- *(and 247 more)*

### Step 3: Lab1 Isolation Test

**Deleted Resources:** 13
- CloudFormation::Stack: serverless-saas-lab1
- S3::Bucket: serverless-saas-lab1-app-d5e7e400
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
- CloudFormation::Stack: serverless-saas-lab2-APIGatewayLambdaPermissions-WG4OW68J492W
- CloudFormation::Stack: serverless-saas-lab2-APIs-1UJA1WU7Q53NT
- CloudFormation::Stack: serverless-saas-lab2-LambdaFunctions-1C9STSWG6L9NO
- CloudFormation::Stack: serverless-saas-lab2-Cognito-1NKRJAQ054YOX
- CloudFormation::Stack: serverless-saas-lab2-UserInterface-NPG90IATINXT
- CloudFormation::Stack: serverless-saas-lab2-DynamoDBTables-9R5UDHCGOXXN
- CloudFormation::Stack: serverless-saas-lab2
- S3::Bucket: serverless-saas-lab2-admin-94584a70
- S3::Bucket: serverless-saas-lab2-landing-94584a70
- Logs::LogGroup: /aws/api-gateway/access-logs-serverless-saas-lab2-admin-api
- *(and 25 more)*

### Step 5: Lab3 Isolation Test

**Deleted Resources:** 44
- CloudFormation::Stack: serverless-saas-tenant-lab3
- CloudFormation::Stack: serverless-saas-shared-lab3-APIGatewayLambdaPermissions-4AW7FLEZL1V
- CloudFormation::Stack: serverless-saas-shared-lab3-APIs-WE8IHXYF4VDX
- CloudFormation::Stack: serverless-saas-shared-lab3-LambdaFunctions-VDDTG1T6XPH5
- CloudFormation::Stack: serverless-saas-shared-lab3-Cognito-J8Y6KVEW1G4Y
- CloudFormation::Stack: serverless-saas-shared-lab3-UserInterface-1B8TVIMGPPIHL
- CloudFormation::Stack: serverless-saas-shared-lab3-DynamoDBTables-1J498FHLUJCO3
- CloudFormation::Stack: serverless-saas-shared-lab3
- S3::Bucket: serverless-saas-shared-lab3-useri-landingappbucket-mzzv3olytypf
- S3::Bucket: serverless-saas-shared-lab3-userint-adminappbucket-ddltsr0x3kmp
- *(and 34 more)*

### Step 6: Lab4 Isolation Test

**Deleted Resources:** 44
- CloudFormation::Stack: serverless-saas-tenant-lab4
- CloudFormation::Stack: serverless-saas-shared-lab4-APIGatewayLambdaPermissions-1JAL2K55KOLLU
- CloudFormation::Stack: serverless-saas-shared-lab4-APIs-3AMIAPI9M7AP
- CloudFormation::Stack: serverless-saas-shared-lab4-LambdaFunctions-1K4TWYNMURFS9
- CloudFormation::Stack: serverless-saas-shared-lab4-Cognito-1SQH8J78840KA
- CloudFormation::Stack: serverless-saas-shared-lab4-UserInterface-13UQFUAC7I5EE
- CloudFormation::Stack: serverless-saas-shared-lab4-DynamoDBTables-W2FYEYP7SBA7
- CloudFormation::Stack: serverless-saas-shared-lab4
- S3::Bucket: serverless-saas-lab4-admin-a675e500
- S3::Bucket: serverless-saas-lab4-app-a675e500
- *(and 34 more)*

### Step 7: Lab5 Isolation Test

**Deleted Resources:** 50
- CloudFormation::Stack: serverless-saas-shared-lab5-CustomResources-5CAORS2DNUV8
- CloudFormation::Stack: serverless-saas-shared-lab5-APIGatewayLambdaPermissions-184TD2LW6K59T
- CloudFormation::Stack: serverless-saas-shared-lab5-APIs-LLE6VQT0GG71
- CloudFormation::Stack: serverless-saas-shared-lab5-LambdaFunctions-HKKUCORAF7ZH
- CloudFormation::Stack: serverless-saas-shared-lab5-Cognito-8GEE5P43QP1A
- CloudFormation::Stack: serverless-saas-shared-lab5-UserInterface-64RCU28QCVFV
- CloudFormation::Stack: serverless-saas-shared-lab5-DynamoDBTables-1S57UIV4C2LYF
- CloudFormation::Stack: serverless-saas-shared-lab5
- CloudFormation::Stack: serverless-saas-pipeline-lab5
- S3::Bucket: serverless-saas-lab5-admin-332c62d0
- *(and 40 more)*

### Step 8: Lab6 Isolation Test

**Deleted Resources:** 65
- CloudFormation::Stack: stack-lab6-pooled
- CloudFormation::Stack: serverless-saas-pipeline-lab6
- CloudFormation::Stack: serverless-saas-shared-lab6-APIGatewayLambdaPermissions-MKRPHGHWPP6W
- CloudFormation::Stack: serverless-saas-shared-lab6-CustomResources-4R1XGVOC3C18
- CloudFormation::Stack: serverless-saas-shared-lab6-APIs-7TK39MSHVXPU
- CloudFormation::Stack: serverless-saas-shared-lab6-LambdaFunctions-5II26K6XCBZG
- CloudFormation::Stack: serverless-saas-shared-lab6-Cognito-1A4LPMGBUIJAH
- CloudFormation::Stack: serverless-saas-shared-lab6-UserInterface-16MQOT6XZWBYI
- CloudFormation::Stack: serverless-saas-shared-lab6-DynamoDBTables-1C1KRY49QLMCW
- CloudFormation::Stack: serverless-saas-shared-lab6
- *(and 55 more)*

### Step 9: Lab7 Isolation Test

**Deleted Resources:** 6
- CloudFormation::Stack: stack-pooled-lab7
- CloudFormation::Stack: serverless-saas-lab7
- S3::Bucket: serverless-saas-lab7-cur-96f53c70
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

### ✅ Lab2

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

### ✅ Lab3

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

### ✅ Lab4

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

### ✅ Lab5

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

### ✅ Lab6

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

### ✅ Lab7

- **Deleted Lab Resources Removed:** Yes
- **Other Labs Unaffected:** Yes

