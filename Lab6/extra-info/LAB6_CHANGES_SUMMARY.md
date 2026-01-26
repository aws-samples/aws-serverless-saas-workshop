# Lab6 Changes Summary

## Overview

This document summarizes all modifications made to Lab6 for proper resource isolation and improved deployment experience.

## Resource Naming Updates

All Lab6 resources have been updated with the `-lab6` suffix to prevent conflicts with other lab environments.

### DynamoDB Tables

| Original Name | Updated Name |
|--------------|--------------|
| `ServerlessSaaS-TenantDetails` | `ServerlessSaaS-TenantDetails-lab6` |
| `ServerlessSaaS-Settings` | `ServerlessSaaS-Settings-lab6` |
| `ServerlessSaaS-TenantUserMapping` | `ServerlessSaaS-TenantUserMapping-lab6` |
| `ServerlessSaaS-TenantStackMapping` | `ServerlessSaaS-TenantStackMapping-lab6` |
| `ServerlessSaas-TenantConfig` (index) | `ServerlessSaas-TenantConfig-lab6` |

### Cognito User Pools

| Original Name | Updated Name |
|--------------|--------------|
| `PooledTenant-ServerlessSaaS-UserPool` | `PooledTenant-ServerlessSaaS-lab6-UserPool` |
| `OperationUsers-ServerlessSaas-UserPool` | `OperationUsers-ServerlessSaas-lab6-UserPool` |
| `{tenantId}-ServerlessSaaSUserPool` | `{tenantId}-ServerlessSaaSUserPool-lab6` |

### Lambda Functions

All Lambda functions now include the `lab6` suffix:
- `serverless-saas-lab6-shared-services-authorizer`
- `serverless-saas-lab6-business-services-authorizer`
- `serverless-saas-lab6-create-tenant`
- `serverless-saas-lab6-get-tenant`
- `serverless-saas-lab6-update-tenant`
- `serverless-saas-lab6-create-user`
- `serverless-saas-lab6-get-users`
- `serverless-saas-lab6-get-product`
- `serverless-saas-lab6-get-products`
- `serverless-saas-lab6-create-product`
- `serverless-saas-lab6-update-product`
- `serverless-saas-lab6-delete-product`
- `serverless-saas-lab6-get-orders`
- `serverless-saas-lab6-get-order`
- `serverless-saas-lab6-create-order`
- `serverless-saas-lab6-update-order`
- `serverless-saas-lab6-delete-order`
- `serverless-saas-lab6-update-usage-plan`
- `serverless-saas-lab6-update-tenant-api-gateway-url`

### S3 Buckets

| Original Pattern | Updated Pattern |
|-----------------|-----------------|
| `${AWS::StackName}-adminappbucket` | `${AWS::StackName}-adminappbucket-lab6` |
| `${AWS::StackName}-appbucket` | `${AWS::StackName}-appbucket-lab6` |
| `${AWS::StackName}-landingappbucket` | `${AWS::StackName}-landingappbucket-lab6` |

### IAM Roles

All IAM roles now include the `lab6` suffix:
- `{tenantId}-product-function-execution-role-lab6`
- `{tenantId}-order-function-execution-role-lab6`
- `{tenantId}-update-usage-plan-role-lab6`
- `{tenantId}-apigwurl-lambda-exec-role-lab6`

### Lambda Layers

- `serverless-saas-dependencies-{tenantId}-lab6`

## Files Modified

### Python Files

1. **server/Resources/shared_service_authorizer.py**
   - Updated `table_tenant_details` to use `ServerlessSaaS-TenantDetails-lab6`

2. **server/Resources/tenant_authorizer.py**
   - Updated `table_tenant_details` to use `ServerlessSaaS-TenantDetails-lab6`

3. **server/TenantManagementService/user-management.py**
   - Updated `table_tenant_user_map` to use `ServerlessSaaS-TenantUserMapping-lab6`
   - Updated `table_tenant_details` to use `ServerlessSaaS-TenantDetails-lab6`
   - Updated user pool name to include `-lab6` suffix

4. **server/TenantManagementService/tenant-management.py**
   - Updated `table_tenant_details` to use `ServerlessSaaS-TenantDetails-lab6`
   - Updated `table_system_settings` to use `ServerlessSaaS-Settings-lab6`
   - Updated index name to `ServerlessSaas-TenantConfig-lab6`

5. **server/layers/auth_manager.py**
   - Updated DynamoDB table ARNs to include `-lab6` suffix

6. **server/TenantPipeline/resources/lambda-deploy-tenant-stack.py**
   - Updated all DynamoDB table names to include `-lab6` suffix

### YAML Templates

All YAML templates already had the `-lab6` suffix applied:
- `server/shared-template.yaml`
- `server/tenant-template.yaml`
- `server/nested_templates/*.yaml`

## New Files Added

### Scripts

1. **scripts/cleanup.sh**
   - Comprehensive cleanup script for all Lab6 resources
   - Handles tenant stacks, shared infrastructure, S3 buckets, and Cognito pools
   - Includes versioned bucket cleanup
   - Provides verification of cleanup completion

2. **scripts/deploy-with-screen.sh**
   - Runs deployment in persistent screen session
   - Prevents connection timeout issues
   - Provides clear instructions for reconnecting

### Documentation

1. **DEPLOYMENT_GUIDE.md**
   - Complete deployment instructions
   - Throttling tier details
   - Testing procedures
   - Troubleshooting guide
   - Architecture diagram

2. **LAB6_CHANGES_SUMMARY.md** (this file)
   - Summary of all changes
   - Resource naming conventions
   - File modifications

### Configuration

1. **.gitignore**
   - Excludes build artifacts (.aws-sam/)
   - Excludes node_modules and package-lock.json
   - Excludes environment-specific configuration files
   - Excludes Python cache files

## Usage Plan Configuration

Lab6 introduces tier-based throttling with the following limits:

| Tier | Daily Quota | Rate Limit | Burst Limit |
|------|-------------|------------|-------------|
| Basic | 50 | 10 req/sec | 20 |
| Standard | 1,000 | 50 req/sec | 100 |
| Premium | 5,000 | 100 req/sec | 200 |
| Platinum | 10,000 | 300 req/sec | 300 |

## Testing

### Throttling Test Script

The `test-basic-tier-throttling.sh` script:
- Sends 1000 concurrent requests to the tenant API
- Demonstrates throttling behavior for Basic tier
- Shows 429 (Too Many Requests) responses when limits are exceeded

Usage:
```
./test-basic-tier-throttling.sh <JWT_TOKEN>
```

## Deployment Flow

```
1. Code Validation (pylint)
   ↓
2. Build Shared Infrastructure (SAM)
   ↓
3. Deploy Shared Infrastructure
   - DynamoDB tables
   - Cognito User Pools
   - S3 + CloudFront
   - API Gateway with Usage Plans
   - Lambda functions
   ↓
4. Build Pooled Tenant Stack (SAM)
   ↓
5. Deploy Pooled Tenant Stack
   - Product/Order services
   - Tenant API Gateway
   - Associate Usage Plans
   ↓
6. Display URLs
```

## Key Differences from Lab5

| Aspect | Lab5 | Lab6 |
|--------|------|------|
| **Primary Focus** | CI/CD Pipeline | Tier-based Throttling |
| **Deployment Method** | CodePipeline + CodeCommit | Direct SAM deploy |
| **Complexity** | High (pipeline setup) | Medium (usage plans) |
| **New Concepts** | Automated deployments | API Gateway throttling |
| **DynamoDB Wait** | Required (pipeline timing) | Not required |
| **Git Push** | Required (triggers pipeline) | Not required |

## Benefits of Lab6 Approach

1. **Simpler Deployment**: No pipeline complexity
2. **Faster Iteration**: Direct SAM deploy is quicker
3. **Clear Throttling**: Visible rate limiting per tier
4. **Cost Control**: Prevents runaway API usage
5. **Fair Usage**: Ensures equitable resource distribution

## Next Steps

After completing Lab6:
1. Test different tier behaviors
2. Monitor CloudWatch metrics for throttling
3. Experiment with custom usage plan configurations
4. Proceed to Lab7 for advanced features
