# Lab 3 Summary

## Overview
Lab 3 adds multi-tenancy to microservices with a pooled architecture. This lab introduces tenant-specific business logic (products and orders) while maintaining shared infrastructure for tenant management.

## Architecture

### Shared Stack (serverless-saas-shared-lab3)
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: TenantDetails-lab3, TenantUserMapping-lab3
- **Cognito User Pools**: PooledTenant, OperationUsers
- **Admin API Gateway**: Handles tenant/user management
- **CloudFront**: 3 distributions (Admin, Landing, Application)
- **S3**: Static website hosting for all three applications

### Tenant Stack (serverless-saas-tenant-lab3)
- **Lambda Functions**: 10 functions for product/order operations (Python 3.14 runtime)
- **DynamoDB Tables**: Product-lab3, Order-lab3 (pooled tables)
- **Tenant API Gateway**: Handles product/order operations
- **Business Services Authorizer**: Lambda authorizer for tenant context

## Key Features
- **Pooled Multi-Tenant Architecture**: Single set of resources shared across all tenants
- **Two API Gateways**: 
  - Admin API Gateway (tenant/user management)
  - Tenant API Gateway (product/order operations)
- **Tenant Isolation**: Data partitioned by tenant ID in pooled DynamoDB tables
- **Sample Tenants**: Automatically creates 3 tenants for testing
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Fixes Applied
1. **YAML Syntax Error**: Fixed unquoted colon in tenant-template.yaml Description field
2. **Duplicate CloudWatch Log Groups**: Removed duplicate log group definitions (lines 169-267)
3. **Tenant Creation Logic**: Modified deployment.sh to create tenants only when both stacks deployed
4. **Automatic Tenant Creation**: Updated condition to prevent errors when tenant stack not deployed

## Deployment
```
cd workshop/Lab3/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

**Deployment Time**: ~13-15 minutes

**Important**: The `-s` flag deploys **BOTH** shared and tenant stacks for full functionality.

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Admin Site URL (CloudFront)
- Landing Site URL (CloudFront)
- App Site URL (CloudFront)

## Sample Tenants Created
- Default tenant: tenant-admin (lancdieg@amazon.com)
- Tenant One: tenant1-admin (lancdieg+lab3tenant1@amazon.com)
- Tenant Two: tenant2-admin (lancdieg+lab3tenant2@amazon.com)

## Testing
- Access Admin Site to manage tenants
- Access Landing Site to register new tenants
- Access Application Site to manage products and orders
- Verify tenant isolation in pooled DynamoDB tables

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile serverless-saas-demo
```

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
