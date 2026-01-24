# Lab 5 Resource Naming Changes

This document summarizes all resource naming changes made to ensure Lab 5 resources are unique and independent from other labs.

## Summary

All Lab 5 resources have been updated to include the `lab5` suffix to prevent naming conflicts with other labs and ensure lab independence.

## Changes Made

### 1. CodePipeline Resources

**File: `workshop/Lab5/server/TenantPipeline/lib/serverless-saas-stack.ts`**
- Pipeline name: `serverless-saas-pipeline` → `serverless-saas-pipeline-lab5`

**File: `workshop/Lab5/server/TenantPipeline/bin/pipeline.ts`**
- Stack ID: Already set to `serverless-saas-pipeline-lab5` ✓

### 2. Tenant Stack Naming

**File: `workshop/Lab5/server/TenantManagementService/tenant-provisioning.py`**
- Stack name pattern: `stack-{0}` → `stack-{0}-lab5`
- Pipeline reference: `serverless-saas-pipeline` → `serverless-saas-pipeline-lab5`

This ensures each tenant's CloudFormation stack has a unique name like `stack-tenant1-lab5`, `stack-tenant2-lab5`, etc.

### 3. Script Updates

**File: `workshop/Lab5/scripts/deployment.sh`**
- Updated pipeline monitoring URL to reference `serverless-saas-pipeline-lab5`

**File: `workshop/Lab5/scripts/cleanup.sh`**
- Updated pipeline bucket search pattern to `serverless-saas-pipeline-lab5-artifactsbucket`
- Updated stack deletion to reference `serverless-saas-pipeline-lab5`
- Updated remaining stacks query to include `serverless-saas-pipeline-lab5`

### 4. Documentation Updates

**File: `workshop/Lab5/DEPLOYMENT_FIXES.md`**
- Updated pipeline monitoring commands
- Updated log group references
- Updated S3 bucket references
- Updated stack deletion commands

**File: `workshop/Lab5/DEPLOYMENT_GUIDE.md`**
- Updated pipeline execution commands

**File: `workshop/Lab5/TROUBLESHOOTING.md`**
- Updated stack deletion commands

## Verification

All Lab 5 resources now include the `lab5` suffix:

### Shared Infrastructure (already had lab5 suffix)
- DynamoDB Tables: `ServerlessSaaS-*-lab5`
- Lambda Functions: `serverless-saas-lab5-*`
- Lambda Layer: `serverless-saas-dependencies-lab5`
- IAM Roles: `*-lab5`
- Cognito User Pools: `*-lab5-*`
- API Gateway: `serverless-saas-admin-api-lab5`
- Log Groups: `/aws/api-gateway/access-logs-serverless-saas-lab5-*`

### Tenant Resources (already had lab5 suffix)
- Lambda Functions: `*-lab5-{TenantId}`
- DynamoDB Tables: `*-{TenantId}-lab5`
- IAM Roles: `{TenantId}-*-lab5`
- Log Groups: `/aws/api-gateway/access-logs-serverless-saas-lab5-tenant-api-{TenantId}`

### CI/CD Pipeline (newly updated)
- Pipeline: `serverless-saas-pipeline-lab5`
- Stack: `serverless-saas-pipeline-lab5`
- Artifact Bucket: `serverless-saas-pipeline-lab5-artifactsbucket*`

### Tenant Stacks (newly updated)
- Stack naming pattern: `stack-{tenantId}-lab5`

## Requirements Satisfied

✅ **Requirement 6.1 (Lab Independence)**: All Lab 5 resources are now uniquely named with lab5 suffix, preventing conflicts with other labs.

✅ **Requirement 6.2 (Unique Naming)**: 
- CodePipeline name includes lab5 suffix
- Tenant stack names include lab5 suffix
- All shared infrastructure already had lab5 suffix
- All tenant-specific resources already had lab5 suffix

## Testing Recommendations

1. Deploy Lab 5 infrastructure and verify all resources are created with lab5 suffix
2. Create a test tenant and verify the tenant stack is named `stack-{tenantId}-lab5`
3. Verify the pipeline is named `serverless-saas-pipeline-lab5`
4. Run cleanup script and verify all lab5 resources are properly identified and deleted
5. Deploy multiple labs simultaneously to verify no naming conflicts occur
