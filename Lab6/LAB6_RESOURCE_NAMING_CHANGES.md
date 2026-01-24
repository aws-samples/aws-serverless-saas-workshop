# Lab 6 Resource Naming Changes

## Overview
This document details the resource naming changes made to Lab 6 to ensure uniqueness and prevent conflicts with other labs in the workshop.

## Changes Made

### 1. Lambda Layer
**File**: `workshop/Lab6/server/nested_templates/lambdafunctions.yaml`

- **Before**: `serverless-saas-dependencies`
- **After**: `serverless-saas-dependencies-lab6`
- **Reason**: Ensures the Lambda layer name is unique across all labs

### 2. API Keys (Already Unique)
**File**: `workshop/Lab6/server/nested_templates/apigateway.yaml`

All API keys already have lab6 suffix:
- `serverless-saas-lab6-sysadmin-apikey`
- `serverless-saas-lab6-platinum-apikey`
- `serverless-saas-lab6-premium-apikey`
- `serverless-saas-lab6-standard-apikey`
- `serverless-saas-lab6-basic-apikey`

### 3. Usage Plans (Already Unique)
**File**: `workshop/Lab6/server/nested_templates/apigateway.yaml`

All usage plans already have lab6 suffix:
- `serverless-saas-lab6-platinum-plan`
- `serverless-saas-lab6-premium-plan`
- `serverless-saas-lab6-standard-plan`
- `serverless-saas-lab6-basic-plan`
- `serverless-saas-lab6-sysadmin-plan`

### 4. IAM Roles (Already Unique)
**File**: `workshop/Lab6/server/nested_templates/lambdafunctions.yaml`

All IAM roles already have lab6 suffix and region suffix where needed:
- `authorizer-execution-role-lab6`
- `authorizer-access-role-lab6`
- `tenant-userpool-lambda-execution-role-lab6-${AWS::Region}`
- `create-user-lambda-execution-role-lab6-${AWS::Region}`
- `tenant-management-lambda-execution-role-lab6-${AWS::Region}`
- `tenant-registration-lambda-execution-role-lab6-${AWS::Region}`
- `tenant-provisioning-lambda-execution-role-lab6-${AWS::Region}`
- `tenant-deprovisioning-lambda-execution-role-lab6-${AWS::Region}`
- `update-settingstable-lambda-execution-role-lab6-${AWS::Region}`
- `update-tenantstackmap-lambda-execution-role-lab6-${AWS::Region}`

### 5. CloudWatch Log Groups (Already Unique)
**Files**: 
- `workshop/Lab6/server/nested_templates/apigateway.yaml`
- `workshop/Lab6/server/tenant-template.yaml`

All log groups already have lab6 suffix:
- `/aws/api-gateway/access-logs-serverless-saas-lab6-admin-api`
- `/aws/api-gateway/access-logs-serverless-saas-lab6-tenant-api-{TenantId}`

### 6. API Gateway (Already Unique)
**Files**:
- `workshop/Lab6/server/nested_templates/apigateway.yaml`
- `workshop/Lab6/server/tenant-template.yaml`

All API Gateways already have lab6 suffix:
- `serverless-saas-admin-api-lab6`
- `{TenantId}-serverless-saas-tenant-api-lab6`

### 7. DynamoDB Tables (Already Unique)
**Files**:
- `workshop/Lab6/server/nested_templates/tables.yaml`
- `workshop/Lab6/server/tenant-template.yaml`

All DynamoDB tables already have lab6 suffix:
- `ServerlessSaaS-TenantDetails-lab6`
- `ServerlessSaaS-TenantUserMapping-lab6`
- `ServerlessSaaS-Settings-lab6`
- `ServerlessSaaS-TenantStackMapping-lab6`
- `Product-{TenantId}-lab6`
- `Order-{TenantId}-lab6`

### 8. Lambda Functions (Already Unique)
All Lambda functions already have lab6 prefix:
- Shared services: `serverless-saas-lab6-*`
- Tenant-specific: `serverless-saas-lab6-*`

### 9. Cognito Resources (Already Unique)
**File**: `workshop/Lab6/server/nested_templates/cognito.yaml`

All Cognito resources already have lab6 suffix:
- User Pools: `PooledTenant-ServerlessSaaS-lab6-UserPool`, `OperationUsers-ServerlessSaaS-lab6-UserPool`
- Domains: `serverless-saas-lab6-pool-${ShortId}`, `serverless-saas-lab6-ops-${ShortId}`

### 10. S3 Buckets (Already Unique)
**File**: `workshop/Lab6/server/nested_templates/userinterface.yaml`

All S3 buckets already have lab6 suffix and account ID:
- `serverless-saas-lab6-admin-${AWS::AccountId}`
- `serverless-saas-lab6-landing-${AWS::AccountId}`
- `serverless-saas-lab6-app-${AWS::AccountId}`

## Verification

All Lab 6 resources now have unique identifiers that prevent conflicts with other labs:

1. ✅ Lambda layers include lab6 suffix
2. ✅ API keys include lab6 suffix
3. ✅ Usage plans include lab6 suffix
4. ✅ IAM roles include lab6 suffix and region suffix where needed
5. ✅ CloudWatch log groups include lab6 suffix
6. ✅ API Gateways include lab6 suffix
7. ✅ DynamoDB tables include lab6 suffix
8. ✅ Lambda functions include lab6 prefix
9. ✅ Cognito resources include lab6 suffix
10. ✅ S3 buckets include lab6 suffix and account ID

## Impact

These changes ensure that:
- Lab 6 can be deployed independently without conflicts
- Multiple labs can coexist in the same AWS account
- Resources are easily identifiable by lab number
- Cleanup operations target only Lab 6 resources

## Requirements Satisfied

- ✅ **Requirement 6.1 (Lab Independence)**: All Lab 6 resources have unique identifiers
- ✅ **Requirement 6.2 (Unique Naming)**: Usage plans and API keys have lab6 suffix to prevent conflicts

## Notes

- Most Lab 6 resources already had proper lab6 naming from previous work
- Only the Lambda layer name needed updating
- All other resources were verified to have correct lab6 suffixes
- Region-specific suffixes are used for IAM roles to ensure global uniqueness
- Account ID is used for S3 buckets to ensure global uniqueness
