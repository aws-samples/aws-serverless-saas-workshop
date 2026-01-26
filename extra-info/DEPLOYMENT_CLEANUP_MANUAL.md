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
```bash
./scripts/deployment.sh --profile <your-profile-name>
./scripts/cleanup.sh --profile <your-profile-name>
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile <your-profile-name>
```

❌ **ABSOLUTELY WRONG - NEVER DO THIS:**
```bash
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
```bash
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
```bash
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

**Option 1: Using cleanup script**:
```bash
cd workshop/scripts
./cleanup.sh
# Select 'Y' when prompted to delete serverless-saas-workshop-lab1
```

**Option 2: Manual cleanup**:
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
```bash
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

```bash
cd workshop/scripts
./cleanup.sh
# Select 'Y' when prompted to delete stack-pooled
```

---

## Lab 3: Tenant Isolation (Silo Model)

### Deployment

**Location**: `workshop/Lab3/server/`

**Commands**:
```bash
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

```bash
cd workshop/scripts
./cleanup.sh
# Script will automatically find and delete all tenant stacks (stack-*)
# Select 'Y' for each stack when prompted
```

---

## Lab 4: Advanced Tenant Isolation

### Deployment

**Location**: `workshop/Lab4/server/`

**Commands**:
```bash
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

```bash
cd workshop/scripts
./cleanup.sh
# Script will delete all tenant stacks and shared services
```

---

## Lab 5: CI/CD Pipeline

### Deployment

**Location**: `workshop/Lab5/server/`

**Commands**:
```bash
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

```bash
cd workshop/scripts
./cleanup.sh
# Deletes pipeline stack, serverless-saas stack, and CodeCommit repo
```

---

## Lab 6: API Throttling and Usage Plans

### Deployment

**Location**: `workshop/Lab6/server/`

**Commands**:
```bash
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
```bash
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

```bash
cd workshop/Lab6/server
./cleanup.sh
# Runs parallel cleanup operations with timestamped logs
```

---

## Lab 7: Cost Attribution and Metering

### Deployment

**Location**: `workshop/Lab7/scripts/`

**Commands**:
```bash
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

```bash
cd workshop/Lab7/scripts

# Run cleanup script
echo "yes" | ./cleanup.sh --profile <your-profile-name>
```

**Cleanup Script Parameters**:
- `--profile <profile>`: AWS CLI profile name (optional, uses default if not provided)
- `--region <region>`: AWS region (optional, default: us-east-1)
- `--main-stack <name>`: Main stack name (optional, default: serverless-saas-lab7)
- `--tenant-stack <name>`: Tenant stack name (optional, default: stack-pooled-lab7)

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

| Lab | Deploy Command | Stack Name | Cleanup |
|-----|---------------|------------|---------|
| Lab 1 | `sam build && sam deploy --profile <your-profile-name>` | `serverless-saas-workshop-lab1` | `cleanup.sh` |
| Lab 2 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled` | `cleanup.sh` |
| Lab 3 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled`, `stack-*` | `cleanup.sh` |
| Lab 4 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled`, `stack-*` | `cleanup.sh` |
| Lab 5 | `./deployment.sh -s -c` | `serverless-saas`, `serverless-saas-pipeline` | `cleanup.sh` |
| Lab 6 | `./deploy-with-screen.sh` | `stack-pooled`, `stack-*` | `./cleanup.sh` |
| Lab 7 | `./deployment.sh --profile <your-profile-name>` | `serverless-saas-lab7`, `stack-pooled-lab7` | `./cleanup.sh --profile <your-profile-name>` |

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
```bash
./scripts/deployment.sh --profile serverless-saas-demo
./scripts/cleanup.sh --profile serverless-saas-demo
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

❌ **WRONG - WILL CAUSE FAILURES:**
```bash
bash scripts/deployment.sh --profile serverless-saas-demo
bash scripts/cleanup.sh --profile serverless-saas-demo
bash deployment.sh -s -c --profile serverless-saas-demo
```

**Technical Reason**: Scripts use `${BASH_SOURCE[0]}` to determine their location. Running with `bash` breaks path resolution and causes deployment failures.

### Make Scripts Executable

If you get "Permission denied" errors:
```bash
chmod +x scripts/*.sh
cd workshop/Lab1/scripts && chmod +x *.sh
cd workshop/Lab2/scripts && chmod +x *.sh
# Repeat for all labs
```

### Use Profile Parameter

All scripts support `--profile` parameter:
```bash
./deployment.sh --profile <your-profile-name>
./cleanup.sh --profile <your-profile-name>
```

If omitted, AWS CLI uses the default profile from `~/.aws/config`.

### Logging

All scripts log to timestamped files in `logs/` directory:
- Deployment logs: `logs/deployment-YYYYMMDD-HHMMSS.log`
- Cleanup logs: `logs/cleanup-YYYYMMDD-HHMMSS.log`

Check logs for detailed error messages if deployment fails.

