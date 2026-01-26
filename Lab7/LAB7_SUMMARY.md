# Lab 7 Summary

## Overview
Lab 7 demonstrates cost attribution in a pooled multi-tenant model. This lab shows how to track and attribute costs to individual tenants using CloudWatch metrics, Lambda layers, and Cost and Usage Reports (CUR).

## Architecture

### Main Stack (serverless-saas-lab7)
- **Lambda Functions**: Product service functions (Python 3.14 runtime)
- **DynamoDB Table**: Product table for sample data
- **Lambda Layer**: Metrics publishing layer for cost tracking
- **CloudWatch Metrics**: Custom metrics for tenant usage tracking
- **S3 Bucket**: Sample CUR data storage

### Tenant Stack (serverless-saas-tenant-lab7)
- **Lambda Functions**: Tenant-specific product operations
- **CloudWatch Metrics**: Tenant-level usage metrics
- **Cost Attribution**: Tracks Lambda invocations, duration, and DynamoDB operations per tenant

## Key Features
- **Cost Attribution**: Track costs per tenant in pooled architecture
- **Custom Metrics**: CloudWatch metrics for tenant usage patterns
- **Lambda Layers**: Reusable metrics publishing layer
- **Sample CUR Data**: Pre-populated Cost and Usage Report data
- **Tenant Usage Analysis**: Analyze tenant-level resource consumption
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Critical Fixes Applied
1. **Region Mismatch**: Updated tenant-samconfig.toml from us-west-2 to us-east-1
2. **Lambda Tags Format**: Converted Tags from map to array format for native Lambda functions
3. **S3 Bucket Configuration**: Added explicit s3_bucket to tenant-samconfig.toml
4. **CloudFormation Parameters**: Added Owner, CostCenter, Environment parameters to tenant stack
5. **Retry Logic Removed**: Simplified deployment script by removing S3 retry logic

## Deployment
```
cd workshop/Lab7/scripts
./deployment.sh --profile serverless-saas-demo
```

**Deployment Time**: ~10-15 minutes

**Important**: Wait 5-10 minutes after cleanup before redeploying due to S3 eventual consistency.

## Verification
Check CloudFormation outputs:
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab7 \
  --query 'Stacks[0].Outputs' \
  --profile serverless-saas-demo
```

## Testing Cost Attribution
1. Invoke product Lambda functions with different tenant IDs
2. Check CloudWatch metrics for tenant-specific usage
3. Analyze custom metrics dashboard
4. Review sample CUR data for cost breakdown

## Cleanup
```
echo "yes" | ./cleanup.sh --profile serverless-saas-demo
```

**Note**: Wait 5-10 minutes before redeploying to allow S3 bucket deletion to propagate.

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
