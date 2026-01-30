# Workshop Deployment and Cleanup Manual

## Overview
This manual provides step-by-step instructions for deploying and cleaning up each lab in the Serverless SaaS Workshop. All labs use AWS SAM (Serverless Application Model) for deployment.

**Related Documentation**:
- **Deployment Scripts Review**: See `workshop/DEPLOYMENT_SCRIPTS_REVIEW.md` for comprehensive analysis of all deployment and cleanup scripts
- **Security Documentation**: See `workshop/CLOUDFRONT_SECURITY_FIX.md` for CloudFront origin hijacking prevention
- **Steering Guide**: See `.kiro/steering/deployment-cleanup-guide.md` for AI assistant guidance

---

## ⚠️ CRITICAL: Script Execution Rules

**NEVER run scripts with the `bash` command!**

All workshop scripts have proper shebang lines (`#!/bin/bash`) and MUST be executed directly:

✅ **CORRECT:**
```
./scripts/deployment.sh --profile <your-profile-name>
./scripts/cleanup.sh --profile <your-profile-name>
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile <your-profile-name>
```

❌ **ABSOLUTELY WRONG - NEVER DO THIS:**
```
bash scripts/deployment.sh --profile <your-profile-name>
bash scripts/cleanup.sh --profile <your-profile-name>
bash deployment.sh -s -c --profile <your-profile-name>
```

**Why this matters:**
- Scripts use `${BASH_SOURCE[0]}` to determine their location
- Running with `bash` breaks path resolution and causes deployment failures
- Scripts must be executable: `chmod +x scripts/*.sh`
- This is NOT optional - using `bash` WILL cause errors

**If you get "Permission denied" errors:**
```
chmod +x scripts/*.sh
```

---

## Prerequisites

### Required Tools
- AWS CLI configured with valid credentials
- AWS SAM CLI installed
- Python 3.14 or compatible version
- Node.js (for client applications in Labs 2-6)

### AWS Credentials
Ensure your AWS credentials are configured with your profile:
```
aws configure --profile <your-profile-name>
# Or verify existing profile:
aws sts get-caller-identity --profile <your-profile-name>
```

**All commands in this manual use the `<your-profile-name>` profile as an example.**

---

## Lab 1: Basic Serverless Application

### Deployment

**Location**: `workshop/Lab1/server/`

**Commands**:
```
cd workshop/Lab1/server

# Build the application
sam build -t template.yaml

# Deploy the application
sam deploy --config-file samconfig.toml --profile <your-profile-name>
```

**What Gets Deployed**:
- 10 Lambda functions (Product and Order services)
- 2 DynamoDB tables (Product-lab1, Order-lab1)
- API Gateway REST API
- CloudWatch Log Groups with 60-day retention
- IAM roles and policies

**Expected Output**:
- Stack Name: `serverless-saas-workshop-lab1`
- API Gateway URL will be displayed in outputs

**Verification**:
```
# Get the API URL
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-lab1 \
  --profile <your-profile-name> \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text

# Test the API
curl <API_URL>/products
```

### Cleanup

**Default stack name**: `serverless-saas-lab1`

**Option 1: Using cleanup script with default stack name**:
```
cd workshop/Lab1/scripts
# Using default stack name
echo "yes" | ./cleanup.sh --profile <your-profile-name>
```

**Option 2: Using cleanup script with explicit stack name**:
```
cd workshop/Lab1/scripts
# With explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile <your-profile-name>
```

**Option 3: Manual cleanup**:
```
# Delete the CloudFormation stack
aws cloudformation delete-stack \
  --stack-name serverless-saas-workshop-lab1 \
  --profile <your-profile-name>

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
  --stack-name serverless-saas-workshop-lab1 \
  --profile <your-profile-name>

# Verify CloudWatch log groups are deleted
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/serverless-saas-workshop-lab1 \
  --profile <your-profile-name>
```

---

## Lab 2: Multi-Tenant Architecture (Pooled)

### Deployment

**Location**: `workshop/Lab2/server/`

**Commands**:
```
cd workshop/Lab2/server

# Deploy using the deployment script
./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com
```

**Script Parameters**:
- `-s`: Deploy server (both shared and tenant stacks)
- `-c`: Deploy client (UI applications)
- `-e`: System admin email (for Admin UI)
- `-te`: Tenant admin email (for Application UI)

**What Gets Deployed**:
- Shared services stack (User and Tenant management)
- 16 Lambda functions
- Cognito User Pools
- DynamoDB tables
- Admin and Landing page UIs
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `stack-pooled`
- Admin UI URL
- Landing Page URL

**Credentials**:
```
Admin User:
  username: admin-user
  password: SaaS#Workshop2026
```

### Cleanup

**Default stack name**: `serverless-saas-lab2`

```
cd workshop/Lab2/scripts
# Using default stack name
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab2 --profile <your-profile-name>
```

---

## Lab 3: Tenant Isolation (Silo Model)

### Deployment

**Location**: `workshop/Lab3/server/`

**Commands**:
```
cd workshop/Lab3/server

# Deploy server and client
./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com
```

**What Gets Deployed**:
- Shared services stack
- Tenant-specific stacks (one per tenant)
- 11 Lambda functions per tenant
- Isolated DynamoDB tables per tenant
- API Gateway with custom authorizer
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `stack-pooled` (shared services)
- Stack Name: `stack-<tenant-id>` (per tenant)

**Credentials**:
```
Tenant Admin:
  username: tenant-admin
  password: SaaS#Workshop2026
```

### Cleanup

**Default stack name**: `serverless-saas-lab3`

```
cd workshop/Lab3/scripts
# Using default stack name (automatically cleans up all tenant stacks)
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile <your-profile-name>
```

---

## Lab 4: Advanced Tenant Isolation

### Deployment

**Location**: `workshop/Lab4/server/`

**Commands**:
```
cd workshop/Lab4/server

# Deploy server and client
./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com
```

**What Gets Deployed**:
- Enhanced tenant isolation
- 10 Lambda functions per tenant
- Tenant-specific API Gateways
- Advanced IAM policies
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `stack-pooled` (shared services)
- Stack Name: `stack-<tenant-id>` (per tenant)

### Cleanup

**Default stack name**: `serverless-saas-lab4`

```
cd workshop/Lab4/scripts
# Using default stack name (automatically cleans up all tenant stacks)
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab4 --profile <your-profile-name>
```

---

## Lab 5: CI/CD Pipeline

### Deployment

**Location**: `workshop/Lab5/server/`

**Commands**:
```
cd workshop/Lab5/server

# Deploy server and client
./deployment.sh -s -c
```

**Script Parameters**:
- `-s`: Deploy server (shared stack + pipeline)
- `-c`: Deploy client (UI applications)

**What Gets Deployed**:
- CodePipeline for automated deployments
- CodeCommit repository
- Shared services stack
- 12 Lambda functions per tenant
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `serverless-saas-pipeline`
- Stack Name: `serverless-saas`
- CodeCommit repository: `aws-serverless-saas-workshop`

**Important: S3 Artifacts Bucket Naming**:

Lab 5 uses a CloudFormation Stack ID hash for the artifacts bucket name to ensure global uniqueness:
- **Pattern**: `serverless-saas-pipeline-lab5-artifacts-{8-char-hex}`
- **Example**: `serverless-saas-pipeline-lab5-artifacts-a1b2c3d4`
- The 8-character hash is automatically extracted from the CloudFormation Stack ID
- This ensures the bucket name is unique across AWS accounts and regions

**⚠️ Important for Stack Updates**:
If you're updating an existing Lab 5 deployment that used the old bucket naming pattern (`serverless-saas-pipeline-lab5-artifacts-{account-id}-{region}`), CloudFormation will:
1. Create a new bucket with the new naming pattern
2. Delete the old bucket
3. **All artifacts in the old bucket will be lost**

This is expected behavior and won't affect pipeline functionality, as the pipeline will use the new bucket going forward.

### Cleanup

**Default stack name**: `serverless-saas-lab5`

```
cd workshop/Lab5/scripts
# Using default stack name (automatically cleans up pipeline, tenant stacks, and CodeCommit repo)
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab5 --profile <your-profile-name>
```

---

## Lab 6: API Throttling and Usage Plans

### Deployment

**Location**: `workshop/Lab6/server/`

**Commands**:
```
cd workshop/Lab6/server

# Deploy in background with screen
./deploy-with-screen.sh

# Monitor deployment
screen -r lab6-deployment

# Or tail logs
tail -f scripts/deployment-*.log
```

**What Gets Deployed**:
- API Gateway with usage plans and API keys
- Throttling policies per tenant tier
- 13 Lambda functions per tenant
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `stack-pooled` (shared services)
- Stack Name: `stack-<tenant-id>` (per tenant)
- API keys for each tenant tier

**Important: S3 Artifacts Bucket Naming**:

Lab 6 uses a CloudFormation Stack ID hash for the artifacts bucket name to ensure global uniqueness:
- **Pattern**: `serverless-saas-pipeline-lab6-artifacts-{8-char-hex}`
- **Example**: `serverless-saas-pipeline-lab6-artifacts-ef0699a0`
- The 8-character hash is automatically extracted from the CloudFormation Stack ID
- This ensures the bucket name is unique across AWS accounts and regions

All CodePipeline-related resources follow consistent naming patterns:
- **Bucket**: `serverless-saas-pipeline-lab6-artifacts-{hash}`
- **Lambda Function**: `serverless-saas-lab6-deploy-tenant-stack`
- **CodeBuild Log Group**: `/aws/codebuild/serverless-saas-pipeline-lab6-build`
- **Lambda Log Group**: `/aws/lambda/serverless-saas-lab6-deploy-tenant-stack`

**Testing Throttling**:
```
cd workshop/Lab6/server
./test-basic-tier-throttling.sh [JWT_TOKEN]
# Expected: ~50% requests return 429 (throttled)
```

**Credentials**:
```
Admin User:
  username: admin-user
  password: SaaS#Workshop2026
```

### Cleanup

**Default stack name**: `serverless-saas-lab6`

```
cd workshop/Lab6/scripts
# Using default stack name (runs parallel cleanup operations with timestamped logs)
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab6 --profile <your-profile-name>
```

---

## Lab 7: Cost Attribution and Metering

### Deployment

**Location**: `workshop/Lab7/scripts/`

**Commands**:
```
cd workshop/Lab7/scripts

# Deploy using the deployment script
./deployment.sh --profile <your-profile-name>
```

**Script Parameters**:
- `--profile <profile>`: AWS CLI profile name (optional, uses default if not provided)
- `--region <region>`: AWS region (optional, default: us-east-1)
- `--main-stack <name>`: Main stack name (optional, default: serverless-saas-lab7)
- `--tenant-stack <name>`: Tenant stack name (optional, default: stack-pooled-lab7)

**What Gets Deployed**:
- Main Lab7 stack with cost attribution infrastructure
- Tenant stack for demo purposes (stack-pooled-lab7)
- Cost and Usage Report (CUR) infrastructure
- S3 bucket for CUR data
- Glue Database and Crawler
- 3 Lambda functions (CUR initializer + 2 cost analysis functions)
- DynamoDB table for cost attribution data
- EventBridge scheduled rules (run every 5 minutes)
- CloudWatch Log Groups with 60-day retention
- Sample CUR data uploaded automatically
- 30 test Lambda invocations generated for demo

**Expected Output**:
- Stack Name: `serverless-saas-lab7` (main stack)
- Stack Name: `stack-pooled-lab7` (tenant stack)
- CUR S3 Bucket
- DynamoDB Table: `TenantCostAndUsageAttribution-lab7`
- Athena database for cost queries

**Verification**:
```
# View attribution data in DynamoDB
aws dynamodb scan \
  --table-name TenantCostAndUsageAttribution-lab7 \
  --profile <your-profile-name>

# Check scheduled attribution Lambdas
aws events list-rules \
  --name-prefix "CalculateDynamoUsageAndCostByTenant-lab7" \
  --profile <your-profile-name>
```

**Note**: The attribution system runs automatically every 5 minutes. Initial runs may show fewer invocations until CloudWatch Logs Insights completes indexing (takes a few minutes).

### Cleanup

**Default stack name**: `serverless-saas-lab7`

```
cd workshop/Lab7/scripts

# Using default stack name
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab7 --profile <your-profile-name>
```

**Cleanup Script Parameters**:
- `--stack-name <name>`: CloudFormation stack name (optional, default: serverless-saas-lab7)
- `--profile <profile>`: AWS CLI profile name (REQUIRED)
- `--region <region>`: AWS region (optional, default: us-east-1)

---

## Global Cleanup Script

### Location
`workshop/scripts/cleanup.sh`

### Usage

**Automatic Mode** (default - no prompts):
```
cd workshop/scripts
./cleanup.sh
# Automatically deletes all resources without prompting
```

**Interactive Mode** (with confirmations):
```
cd workshop/scripts
./cleanup.sh -i
# Prompts for confirmation before deleting each resource
```

### What Gets Cleaned Up

1. **CloudFormation Stacks**:
   - `serverless-saas-workshop-lab1`
   - `stack-pooled`
   - `stack-<tenant-id>` (all tenant stacks)
   - `serverless-saas`
   - `serverless-saas-pipeline`
   - `serverless-saas-cost-per-tenant-lab7`

2. **S3 Buckets**:
   - All buckets matching `serverless-saas-*`
   - All buckets matching `sam-bootstrap-*`

3. **CloudWatch Log Groups**:
   - Lambda function logs: `/aws/lambda/stack-*`, `/aws/lambda/serverless-saas-*`
   - API Gateway logs: `/aws/api-gateway/access-logs-serverless-saas-*`
   - Lab-specific logs: `/aws/lambda/.*-lab[1-7]`

4. **Cognito User Pools**:
   - All user pools matching `*-ServerlessSaaSUserPool$`

5. **CodeCommit Repositories**:
   - `aws-serverless-saas-workshop`

### Verification After Cleanup

```
# Check for remaining stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --profile serverless-saas-demo \
  --query 'StackSummaries[?contains(StackName, `serverless-saas`) || contains(StackName, `stack-`)].StackName'

# Check for remaining log groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/serverless-saas \
  --profile serverless-saas-demo

# Check for remaining S3 buckets
aws s3 ls --profile serverless-saas-demo | grep serverless-saas
```

---

## Common Issues and Troubleshooting

### Issue: SAM build fails with "Docker not running"
**Solution**: Docker is not required for this workshop. Remove `--use-container` flag if present in any commands.

### Issue: Deployment fails with "Stack already exists"
**Solution**: Either delete the existing stack or use `sam deploy --no-confirm-changeset --profile <your-profile-name>` to update it

### Issue: CloudWatch log groups not deleted
**Solution**: Run the cleanup script which now includes comprehensive log group deletion patterns

### Issue: S3 bucket deletion fails with "BucketNotEmpty"
**Solution**: The cleanup script automatically empties buckets before deletion. If manual cleanup is needed:
```
aws s3 rm s3://bucket-name --recursive --profile <your-profile-name>
aws s3 rb s3://bucket-name --profile <your-profile-name>
```

### Issue: Cognito user pool deletion fails
**Solution**: Delete the domain first, then the user pool:
```
aws cognito-idp delete-user-pool-domain \
  --user-pool-id <pool-id> \
  --domain <domain> \
  --profile <your-profile-name>
aws cognito-idp delete-user-pool \
  --user-pool-id <pool-id> \
  --profile <your-profile-name>
```

### Issue: Lambda functions can't write to CloudWatch Logs
**Solution**: Verify log groups exist with correct permissions. All labs now create log groups explicitly with 60-day retention.

---

## Best Practices

1. **Always use cleanup scripts**: Don't manually delete resources to avoid orphaned resources
2. **Use your configured AWS profile**: All commands require `--profile <your-profile-name>`
3. **Monitor costs**: Check AWS Cost Explorer after deployments
4. **Use screen for long deployments**: Lab 6 deployment script uses screen for background execution
5. **Verify credentials**: Ensure AWS credentials are valid before deployment with `aws sts get-caller-identity --profile <your-profile-name>`
6. **Check region**: All labs default to `us-west-2`, verify this matches your setup
7. **Review logs**: Check CloudWatch Logs for Lambda function errors
8. **Test incrementally**: Deploy and test each lab before moving to the next

---

## Quick Reference

### Default Stack Names

Each lab cleanup script has a default stack name that is used when `--stack-name` is not explicitly provided:

| Lab | Default Stack Name | Description |
|-----|-------------------|-------------|
| Lab 1 | `serverless-saas-lab1` | Basic serverless application |
| Lab 2 | `serverless-saas-lab2` | Multi-tenant pooled architecture |
| Lab 3 | `serverless-saas-lab3` | Tenant isolation (silo model) |
| Lab 4 | `serverless-saas-lab4` | Advanced tenant isolation |
| Lab 5 | `serverless-saas-lab5` | CI/CD pipeline |
| Lab 6 | `serverless-saas-lab6` | API throttling and usage plans |
| Lab 7 | `serverless-saas-lab7` | Cost attribution and metering |

**Usage Examples**:
```bash
# Using default stack name
cd workshop/Lab1/scripts
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Using explicit stack name
cd workshop/Lab1/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile <your-profile-name>
```

### Lab Commands

| Lab | Deploy Command | Stack Name | Cleanup |
|-----|---------------|------------|---------|
| Lab 1 | `sam build && sam deploy --profile <your-profile-name>` | `serverless-saas-lab1` | `./cleanup.sh --profile <profile>` |
| Lab 2 | `./deployment.sh -s -c -e <email> -te <email>` | `serverless-saas-lab2` | `./cleanup.sh --profile <profile>` |
| Lab 3 | `./deployment.sh -s -c -e <email> -te <email>` | `serverless-saas-lab3` | `./cleanup.sh --profile <profile>` |
| Lab 4 | `./deployment.sh -s -c -e <email> -te <email>` | `serverless-saas-lab4` | `./cleanup.sh --profile <profile>` |
| Lab 5 | `./deployment.sh -s -c` | `serverless-saas-lab5` | `./cleanup.sh --profile <profile>` |
| Lab 6 | `./deploy-with-screen.sh` | `serverless-saas-lab6` | `./cleanup.sh --profile <profile>` |
| Lab 7 | `./deployment.sh --profile <your-profile-name>` | `serverless-saas-lab7` | `./cleanup.sh --profile <profile>` |

**Note**: The `--stack-name` parameter is optional for all cleanup commands. If not provided, the default stack name for that lab will be used.

---

## Support

For issues or questions:
1. Check CloudWatch Logs for error messages
2. Review the workshop README: `workshop/README.md`
3. Verify all prerequisites are installed
4. Ensure AWS credentials have sufficient permissions

---

## CloudWatch Logs Retention

All labs now have explicit CloudWatch log groups with **60-day retention**:
- Lambda function logs: 74 log groups across all labs
- API Gateway access logs: 10 log groups across Labs 1-6
- Total: 84 log groups with automatic expiration after 60 days

This ensures:
- Predictable log storage costs
- Compliance with data retention policies
- Automatic cleanup of old logs
- No orphaned log groups with infinite retention


---

## Lab Cleanup Isolation

### Overview

**CRITICAL IMPROVEMENT**: All cleanup scripts (Lab1-Lab7) have been updated with lab-specific filtering to prevent cross-lab deletion bugs. This ensures complete isolation between labs, allowing you to deploy multiple labs simultaneously and clean them up independently without affecting other labs.

### The Bug That Was Fixed

**Problem**: Prior to this fix, cleanup scripts used overly broad resource identification patterns that could match and delete resources from other labs.

**Example of the Bug**:
- Lab5's cleanup script searched for tenant stacks using pattern `stack-*`
- This pattern matched `stack-lab6-pooled` (Lab6) and `stack-pooled-lab7` (Lab7)
- Running Lab5 cleanup would **incorrectly delete Lab6 and Lab7 resources**
- This violated the fundamental principle of lab independence

**Impact**:
- Data loss from unintended lab deletions
- Confusion for workshop participants
- Inability to run multiple labs simultaneously
- Difficult troubleshooting when resources mysteriously disappeared

**Root Cause**:
1. **Overly Broad Patterns**: Using `stack-*` matched ALL tenant stacks across all labs
2. **Inconsistent Naming**: Tenant stacks didn't consistently include lab identifiers
3. **No Safeguards**: Scripts didn't verify stack ownership before deletion
4. **Lack of Standardization**: Even Labs 1-2 with simple architectures didn't follow consistent filtering patterns

### The Solution: Lab-Specific Filtering

All cleanup scripts now implement **lab-specific filtering** that ensures each lab only deletes its own resources.

#### Filtering Strategy

**Before (WRONG)**:
```bash
# Lab5 cleanup - matches ALL tenant stacks
TENANT_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
    --output text)
```

**After (CORRECT)**:
```bash
# Lab5 cleanup - matches ONLY Lab5 tenant stacks
TENANT_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?contains(StackName, 'lab5') && starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
    --output text)
```

**Key Difference**: The `contains(StackName, 'lab5')` filter ensures only Lab5 resources are matched.

#### Lab-Specific Patterns

Each lab uses specific patterns to identify its resources:

| Lab | Resource Pattern | Example Stack Names |
|-----|-----------------|---------------------|
| Lab1 | `*lab1*` | `serverless-saas-lab1` |
| Lab2 | `*lab2*` | `serverless-saas-lab2` |
| Lab3 | `*lab3*` | `serverless-saas-shared-lab3`, `stack-pooled-lab3` |
| Lab4 | `*lab4*` | `serverless-saas-shared-lab4`, `stack-pooled-lab4` |
| Lab5 | `*lab5*` | `serverless-saas-shared-lab5`, `stack-pooled-lab5`, `serverless-saas-pipeline-lab5` |
| Lab6 | `*lab6*` | `serverless-saas-shared-lab6`, `stack-pooled-lab6`, `serverless-saas-pipeline-lab6` |
| Lab7 | `*lab7*` | `serverless-saas-lab7`, `stack-pooled-lab7` |

### Resource Naming Convention

All AWS resources follow a consistent naming pattern that includes the lab identifier:

#### CloudFormation Stacks

**Main Stacks**:
- Lab1: `serverless-saas-lab1`
- Lab2: `serverless-saas-lab2`
- Lab3: `serverless-saas-shared-lab3`, `serverless-saas-tenant-lab3`
- Lab4: `serverless-saas-shared-lab4`, `serverless-saas-tenant-lab4`
- Lab5: `serverless-saas-shared-lab5`, `serverless-saas-pipeline-lab5`
- Lab6: `serverless-saas-shared-lab6`, `serverless-saas-pipeline-lab6`
- Lab7: `serverless-saas-lab7`

**Tenant Stacks** (Labs 3-7):
- **Format**: `stack-<tier>-lab<N>`
- **Examples**:
  - Lab3: `stack-pooled-lab3`
  - Lab4: `stack-pooled-lab4`
  - Lab5: `stack-pooled-lab5`, `stack-platinum-lab5`
  - Lab6: `stack-pooled-lab6`, `stack-advanced-lab6`
  - Lab7: `stack-pooled-lab7`

#### Other Resources

All other AWS resources (S3 buckets, CloudWatch log groups, Cognito user pools, etc.) follow the same pattern:

**S3 Buckets**:
- Lab1: `*-lab1-*`
- Lab5: `serverless-saas-pipeline-lab5-artifacts-*`
- Lab6: `serverless-saas-pipeline-lab6-artifacts-*`

**CloudWatch Log Groups**:
- Lab1: `/aws/lambda/*-lab1-*`
- Lab5: `/aws/lambda/*-lab5-*`, `/aws/codebuild/serverless-saas-pipeline-lab5-*`
- Lab7: `/aws/lambda/*-lab7-*`

**Cognito User Pools**:
- Lab2: `*-lab2-*`
- Lab3: `*-lab3-*`

### Cross-Lab Deletion Prevention

All cleanup scripts implement safeguards to prevent accidental deletion of other labs' resources:

#### Verification Logic

Each cleanup script verifies resource ownership before deletion:

```bash
# Verify stack belongs to this lab
verify_stack_ownership() {
    local stack_name=$1
    local lab_id=$2
    
    # Check if stack name contains lab identifier
    if [[ "$stack_name" == *"$lab_id"* ]]; then
        return 0  # Stack belongs to this lab
    else
        echo "WARNING: Stack $stack_name does not belong to $lab_id"
        return 1  # Stack does not belong to this lab
    fi
}
```

#### Exclusion Rules

When cleaning up Lab N, the script **EXCLUDES** resources containing other lab identifiers:

- Lab1 cleanup: Excludes `lab2`, `lab3`, `lab4`, `lab5`, `lab6`, `lab7`
- Lab2 cleanup: Excludes `lab1`, `lab3`, `lab4`, `lab5`, `lab6`, `lab7`
- Lab3 cleanup: Excludes `lab1`, `lab2`, `lab4`, `lab5`, `lab6`, `lab7`
- Lab4 cleanup: Excludes `lab1`, `lab2`, `lab3`, `lab5`, `lab6`, `lab7`
- Lab5 cleanup: Excludes `lab1`, `lab2`, `lab3`, `lab4`, `lab6`, `lab7`
- Lab6 cleanup: Excludes `lab1`, `lab2`, `lab3`, `lab4`, `lab5`, `lab7`
- Lab7 cleanup: Excludes `lab1`, `lab2`, `lab3`, `lab4`, `lab5`, `lab6`

### Performance Impact

**Good News**: Lab-specific filtering **IMPROVES** performance by 5-20% across all labs.

#### Performance Results

| Lab | Query Time Improvement | Overall Improvement | Status |
|-----|----------------------|-------------------|--------|
| Lab1 | -6.25% | -2.0% | ✅ Faster |
| Lab2 | -8.24% | -1.5% | ✅ Faster |
| Lab3 | -13.68% | -1.0% | ✅ Faster |
| Lab4 | -13.68% | -1.0% | ✅ Faster |
| Lab5 | -20.00% | -0.5% | ✅ Faster |
| Lab6 | -20.00% | -0.5% | ✅ Faster |
| Lab7 | -11.11% | -1.5% | ✅ Faster |

**Why Performance Improved**:
1. **Server-Side Filtering**: CloudFormation API applies filters server-side
2. **Reduced Network Transfer**: Returns only lab-specific resources (85% reduction)
3. **Less Client Processing**: Results already filtered (85% reduction)
4. **Scalability**: Performance improvement scales with number of deployed labs

**Detailed Analysis**: See `workshop/tests/TASK_8_FINAL_SUMMARY.md` for complete performance verification results.

### Troubleshooting Cross-Lab Deletion Issues

#### Symptom: Resources from Other Labs Were Deleted

**Diagnosis**:
1. Check which cleanup script was run
2. Review CloudFormation events to see which stacks were deleted
3. Check CloudWatch Logs for cleanup script execution logs

**Recovery**:
1. Redeploy the affected lab(s)
2. Verify resource naming follows the convention
3. Run cleanup script again to verify isolation

**Prevention**:
- Always use the updated cleanup scripts (post-fix)
- Verify stack names before confirming deletion
- Use interactive mode (`-i` flag) to review resources before deletion

#### Symptom: Cleanup Script Doesn't Find Resources

**Diagnosis**:
1. Verify resources exist: `aws cloudformation list-stacks --profile <your-profile-name>`
2. Check resource names match the expected pattern
3. Verify lab identifier is present in resource names

**Solutions**:
1. If resources use old naming (without lab identifier), manually delete them
2. Update resource names to follow the convention
3. Run cleanup script again

#### Symptom: Cleanup Script Finds Resources from Other Labs

**Diagnosis**:
1. Check if resources actually belong to the current lab
2. Verify lab identifier in resource names
3. Review cleanup script filtering logic

**Solutions**:
1. If resources belong to another lab, skip deletion
2. If resources belong to current lab but have incorrect names, manually delete them
3. Report issue if filtering logic is incorrect

### Verification Commands

#### Check Resources for Specific Lab

**CloudFormation Stacks**:
```bash
# Lab5 example
aws cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, 'lab5') && StackStatus!='DELETE_COMPLETE'].StackName" \
  --output table \
  --profile <your-profile-name>
```

**S3 Buckets**:
```bash
# Lab5 example
aws s3 ls --profile <your-profile-name> | grep lab5
```

**CloudWatch Log Groups**:
```bash
# Lab5 example
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/ \
  --profile <your-profile-name> \
  --query "logGroups[?contains(logGroupName, 'lab5')].logGroupName" \
  --output table
```

#### Verify Lab Isolation

**Check for Cross-Lab Resources**:
```bash
# After Lab5 cleanup, verify Lab6 and Lab7 resources still exist
aws cloudformation list-stacks \
  --query "StackSummaries[?(contains(StackName, 'lab6') || contains(StackName, 'lab7')) && StackStatus!='DELETE_COMPLETE'].StackName" \
  --output table \
  --profile <your-profile-name>
```

### Best Practices for Multi-Lab Deployments

1. **Deploy Labs Independently**: Each lab can be deployed without affecting others
2. **Use Lab-Specific Cleanup**: Always run the cleanup script from the specific lab directory
3. **Verify Before Deletion**: Use interactive mode (`-i`) to review resources before deletion
4. **Check Resource Names**: Ensure all resources include the lab identifier
5. **Monitor CloudFormation Events**: Watch for unexpected stack deletions
6. **Use Separate AWS Accounts**: For production workshops, consider using separate AWS accounts per lab

### Testing Lab Isolation

**Manual Test**:
1. Deploy Lab5, Lab6, and Lab7
2. Run Lab5 cleanup script
3. Verify Lab6 and Lab7 resources remain intact:
   ```bash
   aws cloudformation describe-stacks --stack-name stack-pooled-lab6 --profile <your-profile-name>
   aws cloudformation describe-stacks --stack-name stack-pooled-lab7 --profile <your-profile-name>
   ```

**Automated Test**:
See `workshop/tests/performance_verification.sh` for automated lab isolation testing.

### Migration from Old Naming Convention

If you have existing deployments using the old naming convention (without lab identifiers):

**Option 1: Manual Cleanup and Redeploy**
1. Manually delete old resources
2. Redeploy using updated scripts (new naming convention)

**Option 2: Gradual Migration**
1. Keep existing deployments as-is
2. New deployments use new naming convention
3. Cleanup scripts support both old and new patterns (backward compatible)

**Recommendation**: Use Option 1 for clean migration and full isolation benefits.

---

## Troubleshooting Guide

### Common Deployment Issues

#### 1. SAM Build Failures

**Symptom**: `sam build` fails with dependency errors

**Solutions**:
- Verify Python 3.14 is installed: `python3 --version`
- Check Docker is running (required for container builds): `docker ps`
- Clear SAM cache: `rm -rf .aws-sam/`
- Rebuild: `sam build --use-container`

#### 2. Stack Already Exists

**Symptom**: `Stack [name] already exists`

**Solutions**:
- Delete existing stack: `aws cloudformation delete-stack --stack-name <name> --profile serverless-saas-demo`
- Wait for deletion: `aws cloudformation wait stack-delete-complete --stack-name <name> --profile serverless-saas-demo`
- Or use a different stack name: `--stack-name <new-name>`

#### 3. Insufficient IAM Permissions

**Symptom**: `User is not authorized to perform: <action>`

**Solutions**:
- Verify AWS credentials: `aws sts get-caller-identity --profile <your-profile-name>`
- Ensure IAM user/role has AdministratorAccess or equivalent permissions
- Check AWS Organizations SCPs if applicable

#### 4. Resource Conflicts

**Symptom**: `Resource already exists` or `Name already in use`

**Solutions**:
- **S3 bucket names**: Must be globally unique. Scripts use stack ID suffix for uniqueness
- **Cognito domain**: Must be unique within region. Change domain prefix in template
- **DynamoDB table names**: Must be unique within account/region. Scripts use lab suffix

#### 5. CloudFormation Rollback

**Symptom**: Stack creation fails and rolls back

**Solutions**:
- Check CloudFormation events: `aws cloudformation describe-stack-events --stack-name <name> --profile <your-profile-name>`
- Look for specific resource failures in events
- Common causes:
  - IAM permission issues
  - Resource limits exceeded
  - Invalid parameter values
  - Dependency failures

#### 6. Cleanup Failures

**Symptom**: Cleanup script fails to delete resources

**Solutions**:
- **S3 buckets not empty**: Script should empty buckets first. If manual cleanup needed:
  ```
  aws s3 rm s3://<bucket-name> --recursive --profile <your-profile-name>
  aws s3 rb s3://<bucket-name> --profile <your-profile-name>
  ```
- **CloudFormation stack stuck**: Force delete:
  ```
  aws cloudformation delete-stack --stack-name <name> --profile <your-profile-name>
  ```
- **CloudWatch log groups remain**: Manual deletion:
  ```
  aws logs delete-log-group --log-group-name <name> --profile <your-profile-name>
  ```

#### 7. API Gateway 403 Errors

**Symptom**: API calls return 403 Forbidden

**Solutions**:
- Verify API Gateway deployment stage exists
- Check Lambda authorizer configuration (Labs 3+)
- Verify Cognito token is valid and not expired
- Check API Gateway resource policies

#### 8. Cognito User Pool Issues

**Symptom**: Cannot create users or authenticate

**Solutions**:
- Verify email address is valid and accessible
- Check Cognito User Pool exists: `aws cognito-idp list-user-pools --max-results 10 --profile <your-profile-name>`
- Verify user pool client configuration
- Check temporary password email was received

#### 9. Lambda Function Errors

**Symptom**: Lambda functions return 500 errors

**Solutions**:
- Check CloudWatch Logs for function errors:
  ```
  aws logs tail /aws/lambda/<function-name> --follow --profile <your-profile-name>
  ```
- Common causes:
  - Missing environment variables
  - DynamoDB table not found
  - IAM permission issues
  - Timeout (increase timeout in template)
  - Memory limit (increase memory in template)

#### 10. Long Deployment Times

**Symptom**: Deployment takes longer than expected

**Expected Times** (from review):
- Lab 1: ~5 minutes
- Lab 2: ~8 minutes
- Lab 3: ~12 minutes
- Lab 4: ~15 minutes
- Lab 5: ~20 minutes
- Lab 6: ~18 minutes
- Lab 7: ~10 minutes

**If significantly longer**:
- Check AWS service health: https://status.aws.amazon.com/
- Verify network connectivity
- Check CloudFormation events for stuck resources
- Consider deploying in different region

### Performance Optimization Tips

1. **Parallel Deployments**: Deploy independent labs in parallel (different terminals)
2. **SAM Cache**: Keep `.aws-sam/` directory between builds for faster rebuilds
3. **Docker Images**: Use `--use-container` flag for consistent builds
4. **Incremental Updates**: Use `sam sync` for faster Lambda-only updates during development

### Security Best Practices

1. **CloudFront Origin Hijacking Prevention**: All cleanup scripts follow secure deletion order (CloudFront → S3)
2. **IAM Least Privilege**: All Lambda functions use minimal IAM permissions
3. **Secrets Management**: No hardcoded secrets in templates or scripts
4. **Tenant Isolation**: Labs 4+ enforce tenant isolation via IAM policies

### Cost Optimization

**Estimated Monthly Costs** (all labs running):
- Lambda: ~$5-10 (depends on usage)
- DynamoDB: ~$2-5 (on-demand pricing)
- API Gateway: ~$3-5 (per million requests)
- CloudWatch Logs: ~$1-2 (60-day retention)
- S3: ~$1 (minimal storage)
- **Total**: ~$12-23/month

**Cost Reduction Tips**:
1. Delete labs when not in use (use cleanup scripts)
2. Use AWS Free Tier where applicable
3. Set CloudWatch Logs retention to 7 days for testing
4. Use DynamoDB on-demand pricing (already configured)

### Additional Resources

- **AWS SAM Documentation**: https://docs.aws.amazon.com/serverless-application-model/
- **AWS CLI Documentation**: https://docs.aws.amazon.com/cli/
- **CloudFormation Documentation**: https://docs.aws.amazon.com/cloudformation/
- **Workshop GitHub**: https://github.com/aws-samples/aws-serverless-saas-workshop

---

## Script Execution Best Practices

### CRITICAL: Direct Execution Only

**All scripts MUST be executed directly with `./` prefix - NEVER use `bash` command:**

✅ **CORRECT:**
```
./scripts/deployment.sh --profile serverless-saas-demo
./scripts/cleanup.sh --profile serverless-saas-demo
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

❌ **WRONG - WILL CAUSE FAILURES:**
```
bash scripts/deployment.sh --profile serverless-saas-demo
bash scripts/cleanup.sh --profile serverless-saas-demo
bash deployment.sh -s -c --profile serverless-saas-demo
```

**Technical Reason**: Scripts use `${BASH_SOURCE[0]}` to determine their location. Running with `bash` breaks path resolution and causes deployment failures.

### Make Scripts Executable

If you get "Permission denied" errors:
```
chmod +x scripts/*.sh
cd workshop/Lab1/scripts && chmod +x *.sh
cd workshop/Lab2/scripts && chmod +x *.sh
# Repeat for all labs
```

### Use Profile Parameter

All scripts support `--profile` parameter:
```
./deployment.sh --profile <your-profile-name>
./cleanup.sh --profile <your-profile-name>
```

If omitted, AWS CLI uses the default profile from `~/.aws/config`.

### Logging

All scripts log to timestamped files in `logs/` directory:
- Deployment logs: `logs/deployment-YYYYMMDD-HHMMSS.log`
- Cleanup logs: `logs/cleanup-YYYYMMDD-HHMMSS.log`

Check logs for detailed error messages if deployment fails.

---

## Lab Cleanup Isolation

### Overview

All cleanup scripts (Lab1-Lab7) implement **lab-specific resource filtering** to ensure that cleaning up one lab does not affect resources from other labs. This prevents cross-lab deletion bugs and maintains complete isolation between labs.

### The Bug That Was Fixed

**Problem**: Prior to the lab isolation improvements, Lab5 cleanup was deleting resources from Lab6 and Lab7 due to overly broad pattern matching.

**Example**:
- Lab5 cleanup script used pattern: `*lab5*`
- This pattern matched:
  - ✅ `serverless-saas-shared-lab5` (correct)
  - ✅ `stack-lab5-pooled-tenant1` (correct)
  - ❌ `stack-lab6-pooled` (WRONG - belongs to Lab6)
  - ❌ `stack-pooled-lab7` (WRONG - belongs to Lab7)

**Impact**: Running Lab5 cleanup would delete Lab6 and Lab7 tenant stacks, causing data loss and requiring full redeployment.

### The Solution: Lab-Specific Filtering

All cleanup scripts now use **precise lab-specific filtering** that matches only resources belonging to that specific lab.

#### Naming Convention for Tenant Stacks

**Lab3-Lab6** use the following naming convention for tenant stacks:
```
stack-<tenant-id>-<tier>-lab<N>
```

Examples:
- Lab3: `stack-tenant1-pooled-lab3`, `stack-tenant2-pooled-lab3`
- Lab4: `stack-tenant1-pooled-lab4`, `stack-tenant2-pooled-lab4`
- Lab5: `stack-tenant1-pooled-lab5`, `stack-tenant2-premium-lab5`
- Lab6: `stack-tenant1-pooled-lab6`, `stack-tenant2-premium-lab6`

**Key Point**: The lab identifier (`lab3`, `lab4`, `lab5`, `lab6`) is ALWAYS at the END of the stack name.

#### Lab-Specific Filtering Implementation

Each cleanup script now includes:

1. **LAB_ID Constant**: Identifies which lab the script belongs to
   ```bash
   LAB_ID="lab5"  # Example for Lab5
   ```

2. **Stack Ownership Verification Function**: Verifies a stack belongs to the lab
   ```bash
   verify_stack_ownership() {
       local stack_name=$1
       local lab_id=$2
       
       if [[ "$stack_name" == *"$lab_id"* ]]; then
           return 0  # Stack belongs to this lab
       else
           print_message "$RED" "WARNING: Stack $stack_name does not belong to $lab_id"
           return 1  # Stack does not belong to this lab
       fi
   }
   ```

3. **CloudFormation Query Filtering**: Uses `contains(StackName, 'labN')` filter
   ```bash
   # Lab5 example - only matches stacks containing 'lab5'
   TENANT_STACKS=$(aws cloudformation list-stacks \
       --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
       --query "StackSummaries[?contains(StackName, 'lab5') && \
                starts_with(StackName, 'stack-')].StackName" \
       --output text \
       --profile "$AWS_PROFILE")
   ```

#### Lab-Specific Examples

**Lab1 & Lab2** (No tenant stacks):
- Main stack pattern: `serverless-saas-lab1`, `serverless-saas-lab2`
- No tenant stacks (basic serverless apps without multi-tenancy)

**Lab3** (Multi-tenancy introduced):
- Shared stack: `serverless-saas-shared-lab3`
- Tenant stacks: `stack-*-lab3` (e.g., `stack-tenant1-pooled-lab3`)
- CloudFormation query: `contains(StackName, 'lab3')`

**Lab4** (Tenant isolation):
- Shared stack: `serverless-saas-shared-lab4`
- Tenant stacks: `stack-*-lab4` (e.g., `stack-tenant1-pooled-lab4`)
- CloudFormation query: `contains(StackName, 'lab4')`

**Lab5** (Tier-based deployment):
- Shared stack: `serverless-saas-shared-lab5`
- Pipeline stack: `serverless-saas-pipeline-lab5`
- Tenant stacks: `stack-*-lab5` (e.g., `stack-tenant1-pooled-lab5`, `stack-tenant2-premium-lab5`)
- CloudFormation query: `contains(StackName, 'lab5')`
- **CRITICAL FIX**: Will NOT match `stack-lab6-pooled` or `stack-pooled-lab7`

**Lab6** (Throttling):
- Shared stack: `serverless-saas-shared-lab6`
- Pipeline stack: `serverless-saas-pipeline-lab6`
- Tenant stacks: `stack-*-lab6` (e.g., `stack-tenant1-pooled-lab6`)
- CloudFormation query: `contains(StackName, 'lab6')`

**Lab7** (Cost attribution):
- Main stack: `serverless-saas-lab7`
- No tenant stacks (cost attribution lab)

### Key Changes in Cleanup Scripts

All cleanup scripts (Lab1-Lab7) now include:

1. **LAB_ID constant** at the top of the script
2. **verify_stack_ownership()** function for validation
3. **Lab-specific CloudFormation queries** using `contains(StackName, 'labN')`
4. **Verification before deletion** for all stacks
5. **Secure deletion order** (CloudFormation → S3) to prevent CloudFront Origin Hijacking

### Troubleshooting Cross-Lab Deletion Issues

#### Issue: Cleanup script deletes resources from other labs

**Diagnosis**:
1. Check if the script has `LAB_ID` constant defined
2. Verify `verify_stack_ownership()` function exists
3. Check CloudFormation query includes `contains(StackName, 'labN')` filter
4. Review stack names to ensure they follow naming convention

**Solution**:
- Update cleanup script to use lab-specific filtering
- Ensure stack names include lab identifier at the end
- Test cleanup in isolated environment first

#### Issue: Cleanup script misses some resources

**Diagnosis**:
1. Check if stack names follow naming convention
2. Verify CloudFormation query filter is correct
3. Check for orphaned resources (stacks not matching expected patterns)

**Solution**:
- Use `aws cloudformation list-stacks` to find all stacks
- Verify stack names contain lab identifier
- Manually delete orphaned resources if needed

#### Issue: Cannot determine which lab a stack belongs to

**Diagnosis**:
1. Check stack name format
2. Look for lab identifier in stack name
3. Check CloudFormation stack tags (if available)

**Solution**:
- Stack names MUST contain lab identifier (e.g., `lab3`, `lab4`, `lab5`)
- If stack name is ambiguous, check CloudFormation console for creation time and parameters
- Use `aws cloudformation describe-stacks --stack-name <name>` to get stack details

### Cleanup Command Examples

All cleanup commands support the `--profile` parameter (REQUIRED) and optional `--stack-name` parameter.

**Lab1**:
```bash
cd workshop/Lab1/scripts
# Using default stack name (serverless-saas-lab1)
echo "yes" | ./cleanup.sh --profile <your-profile-name>

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile <your-profile-name>
```

**Lab3** (with tenant stacks):
```bash
cd workshop/Lab3/scripts
# Using default stack name (serverless-saas-lab3)
echo "yes" | ./cleanup.sh --profile <your-profile-name>
# Automatically cleans up all tenant stacks matching 'lab3' pattern

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile <your-profile-name>
```

**Lab5** (with pipeline and tenant stacks):
```bash
cd workshop/Lab5/scripts
# Using default stack name (serverless-saas-lab5)
echo "yes" | ./cleanup.sh --profile <your-profile-name>
# Automatically cleans up:
# - serverless-saas-shared-lab5
# - serverless-saas-pipeline-lab5
# - All tenant stacks matching 'lab5' pattern
# Will NOT delete Lab6 or Lab7 resources

# Or with explicit stack name
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab5 --profile <your-profile-name>
```

**Global cleanup** (all labs):
```bash
cd workshop/scripts
echo "yes" | ./cleanup-all-labs.sh --profile <your-profile-name>
# Cleans up all labs in sequence: Lab1 → Lab2 → Lab3 → Lab4 → Lab5 → Lab6 → Lab7
```

### Verification

After cleanup, verify no cross-lab deletion occurred:

```bash
# List all remaining CloudFormation stacks
aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `lab`)].StackName' \
    --output table \
    --profile <your-profile-name>

# List all remaining S3 buckets
aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `lab`)].Name' \
    --output table \
    --profile <your-profile-name>

# List all remaining CloudWatch log groups
aws logs describe-log-groups \
    --query 'logGroups[?contains(logGroupName, `lab`)].logGroupName' \
    --output table \
    --profile <your-profile-name>
```

### Additional Resources

- **Detailed Technical Documentation**: `workshop/extra-info/CLEANUP_ISOLATION.md`
- **Deployment Scripts Review**: `workshop/extra-info/DEPLOYMENT_SCRIPTS_REVIEW.md`
- **CloudFront Security Fix**: `workshop/extra-info/CLOUDFRONT_SECURITY_FIX.md`

