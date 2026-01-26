# Lab 4 Resource Naming Updates

## Summary
Updated Lab 4 CloudFormation templates to ensure all resources have unique `-lab4` identifiers to prevent conflicts with other labs when deployed simultaneously.

## Changes Made

### 1. IAM Roles (lambdafunctions.yaml)
- **AuthorizerExecutionRole**: Added region suffix
  - Before: `authorizer-execution-role-lab4`
  - After: `authorizer-execution-role-lab4-${AWS::Region}`

- **AuthorizerAccessRole**: Added region suffix
  - Before: `authorizer-access-role-lab4`
  - After: `authorizer-access-role-lab4-${AWS::Region}`

- **ApiGatewayCloudWatchLogRole** (apigateway.yaml): Added region suffix
  - Before: `apigateway-cloudwatch-publish-role-lab4`
  - After: `apigateway-cloudwatch-publish-role-lab4-${AWS::Region}`

### 2. IAM Policies (lambdafunctions.yaml)
- **authorizer-execution-policy**: Added region suffix
  - Before: `authorizer-execution-policy`
  - After: `authorizer-execution-policy-lab4-${AWS::Region}`

- **authorizer-access-role-policy**: Added region suffix
  - Before: `authorizer-access-role-policy`
  - After: `authorizer-access-role-policy-lab4-${AWS::Region}`

- **tenant-userpool-lambda-execution-policy**: Added lab4 identifier
  - Before: `tenant-userpool-lambda-execution-policy-${AWS::Region}`
  - After: `tenant-userpool-lambda-execution-policy-lab4-${AWS::Region}`

- **create-user-lambda-execution-policy**: Added lab4 identifier
  - Before: `create-user-lambda-execution-policy-${AWS::Region}`
  - After: `create-user-lambda-execution-policy-lab4-${AWS::Region}`

- **create-tenant-execution-policy**: Added lab4 identifier
  - Before: `create-tenant-execution-policy-${AWS::Region}`
  - After: `create-tenant-execution-policy-lab4-${AWS::Region}`

### 3. S3 Buckets (userinterface.yaml)
Added AWS Account ID suffix to ensure global uniqueness:

- **AdminAppBucket**:
  - Before: `serverless-saas-lab4-adminappbucket`
  - After: `serverless-saas-lab4-adminappbucket-${AWS::AccountId}`

- **LandingAppBucket**:
  - Before: `serverless-saas-lab4-landingappbucket`
  - After: `serverless-saas-lab4-landingappbucket-${AWS::AccountId}`

- **AppBucket**:
  - Before: `serverless-saas-lab4-appbucket`
  - After: `serverless-saas-lab4-appbucket-${AWS::AccountId}`

### 4. CloudWatch Log Groups (tenant-template.yaml)
- **TenantApiGatewayAccessLogs**: Added TenantId suffix
  - Before: `/aws/api-gateway/access-logs-serverless-saas-tenant-api-pooled-lab4`
  - After: `/aws/api-gateway/access-logs-serverless-saas-tenant-api-pooled-lab4-${TenantId}`

## Resources Already Properly Named

The following resources already had unique `-lab4` identifiers:

### Lambda Functions (lambdafunctions.yaml)
- All Lambda functions use `serverless-saas-lab4-*` prefix
- Lambda layer: `serverless-saas-dependencies-lab4`

### DynamoDB Tables (tenant-template.yaml)
- `Product-pooled-lab4`
- `Order-pooled-lab4`

### DynamoDB Tables (tables.yaml)
- `ServerlessSaaS-TenantDetails-lab4`
- `ServerlessSaaS-TenantUserMapping-lab4`

### Cognito Resources (cognito.yaml)
- User pools: `PooledTenant-ServerlessSaaS-lab4-UserPool`, `OperationUsers-ServerlessSaas-lab4-UserPool`
- User pool domains: `pooledtenant-serverlesssaas-lab4`, `operationsusers-serverlesssaas-lab4-${AWS::AccountId}`

### API Gateway (tenant-template.yaml)
- `pooled-serverless-saas-tenant-api-lab4`

### IAM Roles (tenant-template.yaml)
- `pooled-product-function-execution-role-lab4`
- `pooled-order-function-execution-role-lab4`

## Validation

All CloudFormation templates maintain valid YAML syntax with CloudFormation intrinsic functions (!Ref, !GetAtt, !Sub, !Not).

## Requirements Satisfied

- **Requirement 6.1**: Lab independence - All Lab 4 resources now have unique identifiers
- **Requirement 6.2**: Resource naming uniqueness - No conflicts with other labs (Labs 1-7)
