# Workshop Deployment and Cleanup Manual

## Overview
This manual provides step-by-step instructions for deploying and cleaning up each lab in the Serverless SaaS Workshop. All labs use AWS SAM (Serverless Application Model) for deployment.

---

## Prerequisites

### Required Tools
- AWS CLI configured with valid credentials
- AWS SAM CLI installed
- Python 3.14 or compatible version
- Node.js (for client applications in Labs 2-6)

### AWS Credentials
Ensure your AWS credentials are configured with the profile `serverless-saas-demo`:
```bash
aws configure --profile serverless-saas-demo
# Or verify existing profile:
aws sts get-caller-identity --profile serverless-saas-demo
```

**All commands in this manual use the `serverless-saas-demo` profile.**

---

## Lab 1: Basic Serverless Application

### Deployment

**Location**: `workshop/Lab1/server/`

**Commands**:
```bash
cd workshop/Lab1/server

# Build the application
sam build -t template.yaml

# Deploy the application
sam deploy --config-file samconfig.toml --profile serverless-saas-demo
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
```bash
# Get the API URL
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-lab1 \
  --profile serverless-saas-demo \
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
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
  --stack-name serverless-saas-workshop-lab1 \
  --profile serverless-saas-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
  --stack-name serverless-saas-workshop-lab1 \
  --profile serverless-saas-demo

# Verify CloudWatch log groups are deleted
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/serverless-saas-workshop-lab1 \
  --profile serverless-saas-demo
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

**Location**: `workshop/Lab7/`

**Commands**:
```bash
cd workshop/Lab7

# Build the application
sam build -t template.yaml

# Deploy the application
sam deploy --config-file samconfig.toml --profile serverless-saas-demo
```

**What Gets Deployed**:
- Cost and Usage Report (CUR) infrastructure
- S3 bucket for CUR data
- Glue Database and Crawler
- 2 Lambda functions for cost analysis
- CloudWatch Log Groups with 60-day retention

**Expected Output**:
- Stack Name: `serverless-saas-cost-per-tenant-lab7`
- CUR S3 Bucket
- Athena database for cost queries

### Cleanup

```bash
cd workshop/scripts
./cleanup.sh
# Select 'Y' when prompted to delete serverless-saas-cost-per-tenant-lab7
```

---

## Global Cleanup Script

### Location
`workshop/scripts/cleanup.sh`

### Usage

**Automatic Mode** (default - no prompts):
```bash
cd workshop/scripts
./cleanup.sh
# Automatically deletes all resources without prompting
```

**Interactive Mode** (with confirmations):
```bash
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

```bash
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
**Solution**: Either delete the existing stack or use `sam deploy --no-confirm-changeset --profile serverless-saas-demo` to update it

### Issue: CloudWatch log groups not deleted
**Solution**: Run the cleanup script which now includes comprehensive log group deletion patterns

### Issue: S3 bucket deletion fails with "BucketNotEmpty"
**Solution**: The cleanup script automatically empties buckets before deletion. If manual cleanup is needed:
```bash
aws s3 rm s3://bucket-name --recursive --profile serverless-saas-demo
aws s3 rb s3://bucket-name --profile serverless-saas-demo
```

### Issue: Cognito user pool deletion fails
**Solution**: Delete the domain first, then the user pool:
```bash
aws cognito-idp delete-user-pool-domain \
  --user-pool-id <pool-id> \
  --domain <domain> \
  --profile serverless-saas-demo
aws cognito-idp delete-user-pool \
  --user-pool-id <pool-id> \
  --profile serverless-saas-demo
```

### Issue: Lambda functions can't write to CloudWatch Logs
**Solution**: Verify log groups exist with correct permissions. All labs now create log groups explicitly with 60-day retention.

---

## Best Practices

1. **Always use cleanup scripts**: Don't manually delete resources to avoid orphaned resources
2. **Use the serverless-saas-demo profile**: All commands require `--profile serverless-saas-demo`
3. **Monitor costs**: Check AWS Cost Explorer after deployments
4. **Use screen for long deployments**: Lab 6 deployment script uses screen for background execution
5. **Verify credentials**: Ensure AWS credentials are valid before deployment with `aws sts get-caller-identity --profile serverless-saas-demo`
6. **Check region**: All labs default to `us-west-2`, verify this matches your setup
7. **Review logs**: Check CloudWatch Logs for Lambda function errors
8. **Test incrementally**: Deploy and test each lab before moving to the next

---

## Quick Reference

| Lab | Deploy Command | Stack Name | Cleanup |
|-----|---------------|------------|---------|
| Lab 1 | `sam build && sam deploy --profile serverless-saas-demo` | `serverless-saas-workshop-lab1` | `cleanup.sh` |
| Lab 2 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled` | `cleanup.sh` |
| Lab 3 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled`, `stack-*` | `cleanup.sh` |
| Lab 4 | `./deployment.sh -s -c -e <email> -te <email>` | `stack-pooled`, `stack-*` | `cleanup.sh` |
| Lab 5 | `./deployment.sh -s -c` | `serverless-saas`, `serverless-saas-pipeline` | `cleanup.sh` |
| Lab 6 | `./deploy-with-screen.sh` | `stack-pooled`, `stack-*` | `./cleanup.sh` |
| Lab 7 | `sam build && sam deploy --profile serverless-saas-demo` | `serverless-saas-cost-per-tenant-lab7` | `cleanup.sh` |

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
