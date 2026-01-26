# Lab 2 Summary

## Overview
Lab 2 introduces SaaS shared services including tenant management, user management, and authentication. This lab builds upon Lab 1 by adding multi-tenancy infrastructure and administrative capabilities.

## Architecture
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: TenantDetails, TenantUserMapping
- **Cognito User Pools**: PooledTenant (for tenants), OperationUsers (for admins)
- **API Gateway**: Admin API for tenant/user operations
- **CloudFront**: 2 distributions (Admin UI, Landing UI)
- **S3**: Static website hosting for Admin and Landing applications

## Key Features
- Tenant registration and management
- User management with Cognito authentication
- Admin portal for tenant operations
- Landing page for tenant sign-up
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Bugs Fixed
1. **Duplicate CloudWatch Log Groups**: Removed 176 lines of duplicate log group definitions
2. **DynamoDB Table Name Mismatch**: Added `TENANT_DETAILS_TABLE` environment variable
3. **API Gateway Execution Logs Cleanup**: Added `AdminApiGatewayId` output for proper cleanup
4. **Duplicate Admin User Creation**: Fixed CloudFormation to create only one admin user
5. **API Gateway Execution Logs Retention**: Documented technical limitation (circular dependency)

## Deployment
```
cd workshop/Lab2/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --profile serverless-saas-demo
```

**Deployment Time**: ~10-15 minutes

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Admin Site URL (CloudFront)
- Landing Site URL (CloudFront)
- Admin API URL

## Testing
- Access Admin Site to manage tenants
- Access Landing Site to register new tenants
- Verify tenant creation via `/registration` endpoint

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab2 --profile serverless-saas-demo
```

**Note**: Cleanup script properly deletes API Gateway execution logs using API Gateway ID.

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
