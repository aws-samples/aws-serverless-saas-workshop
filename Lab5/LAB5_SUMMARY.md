# Lab 5 Summary

## Overview
Lab 5 introduces tier-based deployment strategies using AWS CodePipeline and CDK. This lab demonstrates how to deploy different infrastructure configurations based on tenant tiers (Basic, Standard, Premium, Platinum).

## Architecture

### Shared Stack (serverless-saas-shared-lab5)
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: TenantDetails-lab5, TenantUserMapping-lab5
- **Cognito User Pools**: PooledTenant, OperationUsers
- **Admin API Gateway**: Handles tenant/user management
- **CloudFront**: 3 distributions (Admin, Landing, Application)
- **S3**: Static website hosting for all three applications

### Pipeline Stack (CDK)
- **CodePipeline**: Automated deployment pipeline for tenant infrastructure
- **CodeBuild**: Builds and deploys tenant-specific stacks
- **CodeCommit**: Source repository for tenant templates
- **Lambda Function**: Triggers pipeline on tenant creation
- **S3 Bucket**: Pipeline artifacts with predictable naming pattern
- **CloudWatch Logs**: Pipeline execution logs with 60-day retention

## Key Features
- **Tier-Based Deployment**: Different infrastructure for Basic, Standard, Premium, Platinum tiers
- **Automated Pipeline**: CodePipeline automatically deploys tenant stacks on creation
- **CDK Infrastructure**: Pipeline stack defined using AWS CDK
- **Predictable S3 Naming**: `serverless-saas-pipeline-lab5-artifacts-${ShortId}`
- **Python 3.14 Runtime**: All Lambda functions use latest Python runtime
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Enhancements
1. **CloudWatch Log Groups**: Added 60-day retention for Lambda and CodeBuild
2. **Predictable S3 Bucket Naming**: Added ShortId suffix for uniqueness
3. **CodeBuild Image Update**: Updated from `AMAZON_LINUX_2_4` to `AMAZON_LINUX_2023_5`
4. **Python Runtime Update**: Updated buildspec from Python 3.9 to 3.11
5. **Empty Tenant Handling**: Lambda function handles empty tenant table gracefully

## Deployment
```
cd workshop/Lab5/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**Deployment Time**: ~20-25 minutes (includes CDK bootstrap and pipeline deployment)

**Important**: CDK bootstrap is required for Lab 5 pipeline deployment.

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Admin Site URL (CloudFront)
- Landing Site URL (CloudFront)
- App Site URL (CloudFront)
- Pipeline Name

## Testing Pipeline
1. Create a Platinum tier tenant via Admin UI
2. Verify CodePipeline execution triggered automatically
3. Check CodeBuild logs for tenant stack deployment
4. Verify tenant-specific infrastructure created

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab5 --profile serverless-saas-demo
```

**Note**: Cleanup script removes pipeline stack, shared stack, and all tenant stacks.

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
