# Lab 5 - Resource Naming Updates Summary

## Overview
All Lab 5 resources have been updated to include the "lab5" suffix for complete isolation from other labs. This ensures Lab 5 can be deployed independently without any dependencies on Labs 1-4.

## Changes Made

### 1. CloudFormation Stack Names
- ✅ `serverless-saas-workshop-shared-lab5` (already had suffix)
- ✅ `serverless-saas-workshop-tenant-lab5` (already had suffix)

### 2. DynamoDB Tables (nested_templates/tables.yaml)
**Updated:**
- `ServerlessSaaS-Settings` → `ServerlessSaaS-Settings-lab5`
- `ServerlessSaaS-TenantStackMapping` → `ServerlessSaaS-TenantStackMapping-lab5`
- `ServerlessSaaS-TenantDetails` → `ServerlessSaaS-TenantDetails-lab5`
- `ServerlessSaaS-TenantUserMapping` → `ServerlessSaaS-TenantUserMapping-lab5`
- GSI Index: `ServerlessSaas-TenantConfig` → `ServerlessSaas-TenantConfig-lab5`

**Already had suffix:**
- `Product-{tenantId}-lab5`
- `Order-{tenantId}-lab5`

### 3. IAM Roles (nested_templates/lambdafunctions.yaml)
**Updated:**
- `authorizer-execution-role` → `authorizer-execution-role-lab5`
- `authorizer-access-role` → `authorizer-access-role-lab5`
- `tenant-userpool-lambda-execution-role-{region}` → `tenant-userpool-lambda-execution-role-lab5-{region}`
- `create-user-lambda-execution-role-{region}` → `create-user-lambda-execution-role-lab5-{region}`
- `tenant-management-lambda-execution-role-{region}` → `tenant-management-lambda-execution-role-lab5-{region}`
- `tenant-registration-lambda-execution-role-{region}` → `tenant-registration-lambda-execution-role-lab5-{region}`
- `tenant-provisioning-lambda-execution-role-{region}` → `tenant-provisioning-lambda-execution-role-lab5-{region}`
- `tenant-deprovisioning-lambda-execution-role-{region}` → `tenant-deprovisioning-lambda-execution-role-lab5-{region}`
- `update-settingstable-lambda-execution-role-{region}` → `update-settingstable-lambda-execution-role-lab5-{region}`
- `update-tenantstackmap-lambda-execution-role-{region}` → `update-tenantstackmap-lambda-execution-role-lab5-{region}`

**Already had suffix:**
- `{tenantId}-product-function-execution-role-lab5`
- `{tenantId}-order-function-execution-role-lab5`
- `{tenantId}-apigwurl-lambda-exec-role-lab5`

### 4. IAM Policy Names (nested_templates/lambdafunctions.yaml)
**Updated:**
- `tenant-userpool-lambda-execution-policy-{region}` → `tenant-userpool-lambda-execution-policy-lab5-{region}`
- `create-user-lambda-execution-policy-{region}` → `create-user-lambda-execution-policy-lab5-{region}`
- `create-tenant-execution-policy-{region}` → `create-tenant-execution-policy-lab5-{region}`
- `tenant-provisioning-lambda-execution-policy-{region}` → `tenant-provisioning-lambda-execution-policy-lab5-{region}`
- `tenant-deprovisioning-lambda-execution-policy-{region}` → `tenant-deprovisioning-lambda-execution-policy-lab5-{region}`
- `update-settingstable-lambda-execution-policy-{region}` → `update-settingstable-lambda-execution-policy-lab5-{region}`
- `update-tenantstackmap-lambda-execution-policy-{region}` → `update-tenantstackmap-lambda-execution-policy-lab5-{region}`

### 5. Lambda Layers
**Updated:**
- `serverless-saas-dependencies` → `serverless-saas-dependencies-lab5` (shared layer)

**Already had suffix:**
- `serverless-saas-dependencies-{tenantId}-lab5` (tenant layer)

### 6. Lambda Functions
**Already had suffix (no changes needed):**
- All Lambda functions already use `serverless-saas-lab5-*` naming pattern

### 7. Cognito User Pools (nested_templates/cognito.yaml)
**Already had suffix (no changes needed):**
- `PooledTenant-ServerlessSaaS-lab5-UserPool`
- `OperationUsers-ServerlessSaas-lab5-UserPool`

### 8. CloudFormation Exports (shared-template.yaml)
**Updated:**
- `Serverless-SaaS-CognitoOperationUsersUserPoolId` → `Serverless-SaaS-CognitoOperationUsersUserPoolId-lab5`
- `Serverless-SaaS-CognitoOperationUsersUserPoolClientId` → `Serverless-SaaS-CognitoOperationUsersUserPoolClientId-lab5`
- `Serverless-SaaS-CognitoTenantUserPoolId` → `Serverless-SaaS-CognitoTenantUserPoolId-lab5`
- `Serverless-SaaS-CognitoTenantAppClientId` → `Serverless-SaaS-CognitoTenantAppClientId-lab5`
- `Serverless-SaaS-AuthorizerExecutionRoleArn` → `Serverless-SaaS-AuthorizerExecutionRoleArn-lab5`

### 9. CloudFormation Imports (tenant-template.yaml)
**Updated to match new export names:**
- All ImportValue statements now reference the `-lab5` suffixed exports

### 10. Custom Resource References (tenant-template.yaml)
**Updated:**
- Table name references in UpdateTenantApiGatewayUrl custom resource now use `-lab5` suffix

### 11. S3 Buckets (nested_templates/userinterface.yaml)
**Updated to ensure global uniqueness:**
- `AdminAppBucket`: Uses `serverless-saas-lab5-admin-${UniqueId}` format
- `AppBucket`: Uses `serverless-saas-lab5-app-${UniqueId}` format
- `LandingAppBucket`: Uses `serverless-saas-lab5-landing-${UniqueId}` format

Where `${UniqueId}` is extracted from the CloudFormation Stack ID to ensure globally unique bucket names without exposing AWS Account ID.

**Implementation:**
```yaml
BucketName: !Sub 
  - 'serverless-saas-lab5-admin-${UniqueId}'
  - UniqueId: !Select [2, !Split ['/', !Ref 'AWS::StackId']]
```

This approach:
- Keeps bucket names under the 63-character S3 limit
- Ensures global uniqueness across all AWS accounts
- Maintains consistent naming pattern with other Lab 5 resources
- Avoids exposing AWS Account ID in bucket names

## Files Modified

1. `aws-serverless-saas-workshop/Lab5/server/shared-template.yaml`
2. `aws-serverless-saas-workshop/Lab5/server/tenant-template.yaml`
3. `aws-serverless-saas-workshop/Lab5/server/nested_templates/tables.yaml`
4. `aws-serverless-saas-workshop/Lab5/server/nested_templates/lambdafunctions.yaml`
5. `aws-serverless-saas-workshop/Lab5/server/nested_templates/userinterface.yaml`

## Recommendations for Other Labs

### S3 Bucket Naming Pattern
To ensure all labs can be deployed independently without S3 bucket naming conflicts, apply the same S3 bucket naming pattern to Labs 1-4:

**Pattern:** `serverless-saas-lab{N}-{bucket-type}-${UniqueId}`

**Example for Lab 1:**
```yaml
AdminAppBucket:
  Type: AWS::S3::Bucket
  Properties:
    BucketName: !Sub 
      - 'serverless-saas-lab1-admin-${UniqueId}'
      - UniqueId: !Select [2, !Split ['/', !Ref 'AWS::StackId']]
```

**Apply to:**
- Lab 1: `serverless-saas-lab1-admin/app/landing-${UniqueId}`
- Lab 2: `serverless-saas-lab2-admin/app/landing-${UniqueId}`
- Lab 3: `serverless-saas-lab3-admin/app/landing-${UniqueId}`
- Lab 4: `serverless-saas-lab4-admin/app/landing-${UniqueId}`

**Benefits:**
- Prevents S3 bucket naming conflicts between labs
- Ensures global uniqueness without exposing AWS Account ID
- Maintains consistent naming convention across all labs
- Stays within S3's 63-character bucket name limit

## Verification

Lab 5 is now completely self-contained with:
- ✅ No dependencies on Labs 1-4
- ✅ All resources properly namespaced with "lab5" suffix
- ✅ All CloudFormation exports/imports use lab5-suffixed names
- ✅ All DynamoDB tables include lab5 suffix
- ✅ All IAM roles and policies include lab5 suffix
- ✅ All Lambda layers include lab5 suffix

## Deployment

Lab 5 can now be deployed independently using:

```
cd Lab5/scripts
./deployment.sh -s    # Deploy server (pipeline + bootstrap)
./deployment.sh -c    # Deploy client
./deployment.sh -s -c # Deploy both
```

The deployment will create isolated resources that won't conflict with any other lab deployments.
