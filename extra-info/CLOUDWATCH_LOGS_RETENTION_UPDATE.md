# CloudWatch Logs Retention Update Summary

## Overview
Updated all CloudWatch log groups across Labs 1-7 to have a 60-day retention policy and enhanced the cleanup script to properly delete all workshop-related log groups.

## Changes Made

### 1. API Gateway Access Logs (60-day retention)
Updated retention from 30 days to 60 days for all API Gateway access log groups:

- **Lab1**: 1 log group (API Gateway access logs)
- **Lab2**: 1 log group (Admin API Gateway access logs)
- **Lab3**: 2 log groups (Admin API + Tenant API access logs)
- **Lab4**: 2 log groups (Admin API + Tenant API access logs)
- **Lab5**: 2 log groups (Admin API + Tenant API access logs)
- **Lab6**: 2 log groups (Admin API + Tenant API access logs)
- **Lab7**: No explicit API Gateway log groups

**Total API Gateway Access Log Groups**: 10

### 2. API Gateway Execution Logs (60-day retention) - TECHNICAL LIMITATION

**Background**: API Gateway creates execution logs automatically when `MethodSettings.LoggingLevel` is set to `INFO` or `ERROR`. These logs follow the pattern `API-Gateway-Execution-Logs_{api-id}/prod` and contain detailed execution traces, Lambda integration logs, and errors. Without explicit log group definitions, AWS creates them with infinite retention (NEVER_EXPIRE).

**CRITICAL LIMITATION**: Cannot pre-create execution log groups in CloudFormation due to circular dependency:
- Log group name requires API Gateway ID: `API-Gateway-Execution-Logs_${AdminApiGatewayApi}/prod`
- This creates a reference from log group to API Gateway
- Adding `DependsOn: AdminApiGatewayExecutionLogs` to API Gateway creates circular dependency
- CloudFormation deployment fails with: "Circular dependency between resources"

**Current Implementation**: 
- Execution logs are created by AWS with infinite retention (NEVER_EXPIRE)
- Cleanup scripts properly delete them using `AdminApiGatewayId` output (fixed in Task 27.2)
- See `workshop/CLOUDWATCH_LOGS_CLEANUP_ORDER_FIX.md` for detailed analysis and solution options

**Labs Affected**:
- **Lab2**: 1 execution log group (Admin API)
- **Lab3**: 2 execution log groups (Admin API + Tenant API)
- **Lab4**: 2 execution log groups (Admin API + Tenant API)
- **Lab5**: 2 execution log groups (Admin API + Tenant API)
- **Lab6**: 2 execution log groups (Admin API + Tenant API)

**Total API Gateway Execution Log Groups**: 9 (all with infinite retention by default, properly cleaned up)

### 3. Lambda Function Logs (60-day retention)
Added explicit CloudWatch log groups with 60-day retention for all Lambda functions:

- **Lab1**: 10 Lambda functions
  - Product Service: GetProduct, GetProducts, CreateProduct, UpdateProduct, DeleteProduct
  - Order Service: GetOrders, GetOrder, CreateOrder, UpdateOrder, DeleteOrder

- **Lab2**: 16 Lambda functions
  - User Management: CreateUser, UpdateUser, DisableUser, GetUser, GetUsers, DisableUsersByTenant, EnableUsersByTenant, CreateTenantAdminUser
  - Tenant Management: CreateTenant, ActivateTenant, GetTenant, DeactivateTenant, UpdateTenant, GetTenants, RegisterTenant
  - Authorization: SharedServicesAuthorizer

- **Lab3**: 11 Lambda functions
  - Product Service: GetProduct, GetProducts, CreateProduct, UpdateProduct, DeleteProduct
  - Order Service: GetOrders, GetOrder, CreateOrder, UpdateOrder, DeleteOrder
  - Authorization: BusinessServicesAuthorizer

- **Lab4**: 10 Lambda functions
  - Product Service: GetProduct, GetProducts, CreateProduct, UpdateProduct, DeleteProduct
  - Order Service: GetOrders, GetOrder, CreateOrder, UpdateOrder, DeleteOrder

- **Lab5**: 12 Lambda functions
  - Product Service: GetProduct, GetProducts, CreateProduct, UpdateProduct, DeleteProduct
  - Order Service: GetOrders, GetOrder, CreateOrder, UpdateOrder, DeleteOrder
  - Authorization: BusinessServicesAuthorizer
  - Utility: UpdateTenantApiGatewayUrl

- **Lab6**: 13 Lambda functions
  - Product Service: GetProduct, GetProducts, CreateProduct, UpdateProduct, DeleteProduct
  - Order Service: GetOrders, GetOrder, CreateOrder, UpdateOrder, DeleteOrder
  - Authorization: BusinessServicesAuthorizer
  - Utility: UpdateUsagePlan, UpdateTenantApiGatewayUrl

- **Lab7**: 2 Lambda functions
  - Cost Analysis: GetDynamoDBUsageAndCostByTenant, GetLambdaUsageAndCostByTenant

**Total Lambda Function Log Groups**: 74

### 3. Enhanced Cleanup Script
Updated `workshop/scripts/cleanup.sh` to delete all workshop-related CloudWatch log groups:

**New patterns added**:
- API Gateway access logs: `/aws/api-gateway/access-logs-serverless-saas-*`
- Lab-specific Lambda logs: `/aws/lambda/.*-lab[1-7]`
- Product service logs: `/aws/lambda/create-product-pooled-lab*`, `/aws/lambda/update-product-pooled-lab*`, `/aws/lambda/get-products-pooled-lab*`

**Existing patterns retained**:
- Lambda function logs: `/aws/lambda/stack-*`, `/aws/lambda/serverless-saas-*`

## Implementation Details

### Log Group Naming Convention
All Lambda function log groups follow this pattern:
```
/aws/lambda/${AWS::StackName}-<FunctionName>
```

This ensures:
- Unique log group names per stack deployment
- Easy identification of logs by stack
- Automatic cleanup when stacks are deleted

### Retention Policy
All log groups now have:
```yaml
RetentionInDays: 60
```

This provides:
- 60 days of log history for troubleshooting
- Automatic log expiration to control costs
- Compliance with data retention requirements

### Dependencies
Each Lambda function now depends on its log group:
```yaml
FunctionName:
  Type: AWS::Serverless::Function
  DependsOn: FunctionNameLogGroup
  Properties:
    ...
```

This ensures log groups are created before functions, preventing automatic log group creation with infinite retention.

## Files Modified

### Templates Updated
1. `workshop/Lab1/server/template.yaml`
2. `workshop/Lab2/server/nested_templates/apigateway.yaml`
3. `workshop/Lab2/server/nested_templates/lambdafunctions.yaml`
4. `workshop/Lab3/server/nested_templates/apigateway.yaml`
5. `workshop/Lab3/server/tenant-template.yaml`
6. `workshop/Lab4/server/nested_templates/apigateway.yaml`
7. `workshop/Lab4/server/tenant-template.yaml`
8. `workshop/Lab5/server/nested_templates/apigateway.yaml`
9. `workshop/Lab5/server/tenant-template.yaml`
10. `workshop/Lab6/server/nested_templates/apigateway.yaml`
11. `workshop/Lab6/server/tenant-template.yaml`
12. `workshop/Lab7/template.yaml`

### Scripts Updated
1. `workshop/scripts/cleanup.sh` - Enhanced log group cleanup

### Scripts Created
1. `workshop/scripts/add_lambda_log_retention.py` - Automated log group addition
2. `workshop/scripts/remove_duplicate_log_groups.py` - Cleanup utility

## Total Impact

- **84 log groups** now have explicit 60-day retention policies
  - 10 API Gateway access log groups (completed)
  - 74 Lambda function log groups (completed)
- **9 API Gateway execution log groups** have infinite retention (technical limitation - cannot fix in CloudFormation)
  - Properly cleaned up by cleanup scripts (fixed in Task 27.2)
  - See `workshop/CLOUDWATCH_LOGS_CLEANUP_ORDER_FIX.md` for solution options
- **All labs (1-7)** covered
- **Cleanup script** enhanced to remove all workshop log groups (including execution logs)

## Benefits

1. **Cost Control**: Automatic log expiration after 60 days prevents unbounded log storage costs
2. **Compliance**: Consistent retention policy across all workshop resources
3. **Clean Cleanup**: Enhanced cleanup script ensures no orphaned log groups remain
4. **Predictable Behavior**: Explicit log groups prevent AWS from creating them with infinite retention
5. **Better Organization**: Structured naming convention makes logs easy to identify and manage

## Testing Recommendations

1. Deploy a lab stack and verify log groups are created with 60-day retention
2. Run the cleanup script and verify all log groups are properly deleted
3. Check CloudWatch Logs console to confirm no orphaned log groups remain
4. Verify Lambda functions can write logs successfully to the pre-created log groups
