# Lab 4 Summary

## Overview
Lab 4 demonstrates tenant data isolation in a pooled model using IAM policies and STS credentials. This lab builds upon Lab 3 by adding fine-grained access control to prevent cross-tenant data access.

## Architecture

### Shared Stack (serverless-saas-shared-lab4)
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: TenantDetails-lab4, TenantUserMapping-lab4
- **Cognito User Pools**: PooledTenant, OperationUsers
- **Admin API Gateway**: Handles tenant/user management
- **CloudFront**: 3 distributions (Admin, Landing, Application)
- **S3**: Static website hosting for all three applications

### Tenant Stack (serverless-saas-tenant-lab4)
- **Lambda Functions**: 11 functions including Business Services Authorizer (Python 3.14 runtime)
- **DynamoDB Tables**: Product-lab4, Order-lab4 (pooled tables with tenant isolation)
- **Tenant API Gateway**: Handles product/order operations
- **IAM Roles**: 3 roles for tenant data isolation
  - AuthorizerAccessRole: Generates tenant-scoped STS credentials
  - ProductFunctionRole: Scoped access to Product table
  - OrderFunctionRole: Scoped access to Order table

## Key Features
- **Tenant Data Isolation**: IAM policies enforce row-level security in DynamoDB
- **STS Credentials**: Business Services Authorizer generates temporary credentials scoped to tenant ID
- **Pooled Architecture**: Single set of resources with fine-grained access control
- **Cross-Tenant Protection**: IAM policies prevent access to other tenants' data
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Enhancements
1. **IAM Policy-Based Isolation**: DynamoDB access restricted by tenant ID using IAM conditions
2. **STS Credential Generation**: Authorizer creates temporary credentials with tenant-specific permissions
3. **Role-Based Access Control**: Separate IAM roles for product and order operations
4. **Tenant Context Propagation**: Tenant ID passed through API Gateway to Lambda functions

## Deployment
```
cd workshop/Lab4/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

**Deployment Time**: ~18-20 minutes

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Admin Site URL (CloudFront)
- Landing Site URL (CloudFront)
- App Site URL (CloudFront)

## Testing Tenant Isolation
1. Create products/orders for Tenant A
2. Attempt to access Tenant A's data using Tenant B's credentials
3. Verify access denied (IAM policy enforcement)
4. Check CloudWatch logs for authorization decisions

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab4 --profile serverless-saas-demo
```

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
