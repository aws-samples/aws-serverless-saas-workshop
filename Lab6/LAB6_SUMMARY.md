# Lab 6 Summary

## Overview
Lab 6 introduces tenant-based throttling and rate limiting using API Gateway usage plans. This lab demonstrates how to apply different throttling policies based on tenant tiers to ensure fair resource usage.

## Architecture

### Shared Stack (serverless-saas-shared-lab6)
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: TenantDetails-lab6, TenantUserMapping-lab6
- **Cognito User Pools**: PooledTenant, OperationUsers
- **Admin API Gateway**: Handles tenant/user management
- **CloudFront**: 3 distributions (Admin, Landing, Application)
- **S3**: Static website hosting for all three applications

### Pipeline Stack (CDK)
- **CodePipeline**: Automated deployment pipeline for tenant infrastructure
- **CodeBuild**: Builds and deploys tenant-specific stacks with throttling
- **CodeCommit**: Source repository for tenant templates
- **Lambda Function**: Triggers pipeline and handles empty tenant table
- **S3 Bucket**: Pipeline artifacts with predictable naming pattern
- **CloudWatch Logs**: Pipeline execution logs with 60-day retention

## Key Features
- **Tenant-Based Throttling**: Different rate limits for Basic, Standard, Premium, Platinum tiers
- **API Gateway Usage Plans**: Enforces throttling at API Gateway level
- **Automated Pipeline**: CodePipeline deploys tenant stacks with tier-specific throttling
- **Python 3.14 Runtime**: All Lambda functions use latest Python runtime
- **Predictable S3 Naming**: `serverless-saas-pipeline-lab6-artifacts-${ShortId}`
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Fixes Applied
1. **Stack Naming Standardization**: Removed "workshop" keyword from stack names
2. **Parameter Duplication Fix**: Fixed duplicate parameter passing in shared-template.yaml
3. **CloudWatch Log Groups**: Added 60-day retention for Lambda and CodeBuild
4. **Predictable S3 Bucket Naming**: Added ShortId suffix for uniqueness
5. **CodeBuild Image Update**: Updated from `AMAZON_LINUX_2_4` to `AMAZON_LINUX_2023_5`
6. **Python Runtime Update**: Updated buildspec from Python 3.9 to 3.11
7. **Empty Tenant Handling**: Lambda function handles empty tenant table gracefully
8. **Application UI Deployment Fix**: Fixed stack name query in deployment script
9. **Python 3.14 Compatibility**: Added `--use-container` flag to tenant-buildspec.yml
10. **Deploy Stage Parameter Fix**: Added required CloudFormation parameters to lambda-deploy-tenant-stack.py

## Deployment
```
cd workshop/Lab6/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**Deployment Time**: ~20-25 minutes

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Admin Site URL (CloudFront)
- Landing Site URL (CloudFront)
- App Site URL (CloudFront)
- Pipeline Name

## Testing Throttling
1. Create tenants with different tiers (Basic, Standard, Premium, Platinum)
2. Use test script to generate API requests
3. Verify throttling behavior based on tier limits
4. Check API Gateway metrics for throttled requests

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab6 --profile serverless-saas-demo
```

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
