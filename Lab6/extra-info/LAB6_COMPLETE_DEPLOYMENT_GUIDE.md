# Lab6 Complete Deployment Guide

## Overview

This guide provides comprehensive deployment instructions for Lab6 (Tenant Throttling) based on real-world testing and troubleshooting. It includes all lessons learned from deploying in a fresh AWS account.

**Last Updated:** January 2026  
**Tested On:** Fresh AWS Account with no prior workshop deployments

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Steps](#deployment-steps)
4. [Testing Throttling](#testing-throttling)
5. [Troubleshooting](#troubleshooting)
6. [Cleanup](#cleanup)
7. [Known Issues and Solutions](#known-issues-and-solutions)

---

## Prerequisites

### Required Tools

Verify all tools are installed and at the correct versions:

```
# AWS CLI (v2.x or later)
aws --version

# AWS SAM CLI (v1.x or later)
sam --version

# Python (3.9 or later)
python3 --version

# Node.js (v18.x recommended, v20+ may have compatibility issues)
node --version

# npm
npm --version

# AWS CDK
npm install -g aws-cdk
cdk --version

# Git
git --version

# jq (for JSON processing in scripts)
jq --version

# screen (for long-running deployments)
screen --version
```

### AWS Account Setup

1. **Configure AWS Credentials:**
   ```
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Default region: us-east-1
   # Default output format: json
   ```

2. **Verify Access:**
   ```
   aws sts get-caller-identity
   ```

3. **Ensure Sufficient Permissions:**
   - CloudFormation full access
   - Lambda full access
   - DynamoDB full access
   - S3 full access
   - API Gateway full access
   - Cognito full access
   - IAM role creation
   - CodePipeline and CodeCommit access

### Python Virtual Environment (Recommended)

```
# Create virtual environment
python3 -m venv .venv_py313

# Activate it
source .venv_py313/bin/activate  # On macOS/Linux
# or
.venv_py313\Scripts\activate  # On Windows

# Install pylint
pip install pylint
```

---

## Architecture Overview

### Lab6 Components

Lab6 builds on Lab5 by adding API Gateway throttling limits per tenant tier:

**Tenant Tiers and Throttling Limits:**

| Tier | Rate Limit | Burst Limit | Daily Quota |
|------|-----------|-------------|-------------|
| Basic | 50 req/sec | 100 | 500 requests/day |
| Standard | 100 req/sec | 200 | 1000 requests/day |
| Premium | 200 req/sec | 400 | 5000 requests/day |
| Platinum | 500 req/sec | 1000 | 10000 requests/day |

**Key Resources:**

1. **Shared Infrastructure Stack** (`serverless-saas-workshop-shared-lab6`)
   - Lambda functions with `-lab6` suffix
   - DynamoDB tables with `-lab6` suffix
   - API Gateway with usage plans and API keys
   - Cognito User Pools
   - S3 buckets for client applications
   - CloudFront distributions

2. **Pipeline Stack** (`serverless-saas-pipeline-lab6`)
   - CodePipeline for tenant provisioning
   - CodeCommit repository
   - Lambda functions for pipeline stages
   - S3 bucket for pipeline artifacts

3. **Pooled Stack** (`stack-lab6-pooled`)
   - Created automatically by pipeline on first run
   - Shared resources for Basic, Standard, and Premium tiers
   - API Gateway endpoint for pooled tenants

4. **Tenant Stacks** (per tenant, silo model only)
   - `stack-{tenantId}` for Platinum tier tenants
   - Dedicated resources per tenant

### Deployment Order (Critical!)

The deployment order is critical to avoid race conditions:

1. **Shared Stack** → Creates DynamoDB tables
2. **Wait for DynamoDB tables** → Ensures tables are ACTIVE
3. **Pipeline Stack** → Deploys CI/CD pipeline
4. **Pipeline Execution** → Automatically creates pooled stack
5. **Wait for Pooled Stack** → Ensures stack-lab6-pooled is ready
6. **Client Applications** → Deploy UI applications

**Why This Order Matters:**
- Pipeline Lambda functions query DynamoDB tables immediately
- If tables don't exist, pipeline fails with `ResourceNotFoundException`
- Pooled stack must exist before tenant registration
- Settings table must have `apiGatewayUrl-Pooled` entry for tenant registration

---

## Deployment Steps

### Option 1: Automated Deployment with Screen (Recommended)

For long-running deployments (15-25 minutes), use the screen session wrapper:

```
cd Lab6/scripts
./deploy-with-screen.sh
```

**Features:**
- Runs deployment in persistent screen session
- Survives terminal disconnections
- Logs all output to timestamped file
- Shows application URLs on completion

**Monitor Progress:**
```
# Reconnect to screen session
screen -r lab6-deployment

# Or watch logs in real-time (from another terminal)
tail -f Lab6/scripts/deployment-*.log

# Detach from screen (keeps it running)
# Press: Ctrl+A, then D
```

### Option 2: Direct Deployment

For interactive deployment with immediate feedback:

```
cd Lab6/scripts
./deployment.sh -s -c
```

**Flags:**
- `-s`: Deploy server infrastructure (shared stack + pipeline)
- `-c`: Deploy client applications (Admin, Landing, App UIs)
- `-b`: Deploy bootstrap only (shared stack only)
- `-p`: Deploy pipeline only

### Deployment Timeline

**Expected Duration:** 15-25 minutes

**Breakdown:**
1. Python code validation: 30 seconds
2. SAM build: 1-2 minutes
3. Shared stack deployment: 5-7 minutes
4. DynamoDB table activation: 30 seconds
5. Pipeline deployment: 3-5 minutes
6. Pipeline execution (pooled stack): 5-8 minutes
7. Client builds and uploads: 2-3 minutes
8. CloudFront invalidations: 30 seconds (async)

### Deployment Output

On successful completion, you'll see:

```
==========================================
Deployment Complete!
==========================================
Admin site URL: https://d1234abcd5678.cloudfront.net
Landing site URL: https://d9876zyxw5432.cloudfront.net
App site URL: https://d5555eeee1111.cloudfront.net

Next steps:
1. Access the Admin site to create tenants
2. Monitor the pipeline at: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view
3. Check CloudFormation stacks for tenant deployments
==========================================
```

**Save these URLs!** You'll need them for testing.

---

## Testing Throttling

### Step 1: Register a Basic Tier Tenant

1. Open the Admin site URL in your browser
2. Click "Register" to create an admin account
3. Log in with your admin credentials
4. Click "Add Tenant" and fill in:
   - Tenant Name: `TestTenant1`
   - Tenant Email: `your-email+tenant1@example.com`
   - Tenant Tier: `Basic`
   - Tenant Plan: `Basic`
5. Click "Register Tenant"

**Wait for tenant provisioning** (30-60 seconds for pooled tenants)

### Step 2: Get JWT Token

1. Open the Landing site URL
2. Log in with tenant credentials (check email for temporary password)
3. Open browser Developer Tools (F12)
4. Go to Application/Storage → Local Storage
5. Find and copy the `idToken` value (this is your JWT token)

### Step 3: Run Throttling Test

```
cd Lab6/scripts
./test-basic-tier-throttling.sh <YOUR_JWT_TOKEN>
```

**Expected Results:**

The script sends 1000 GET requests to the `/products` endpoint. For a Basic tier tenant (50 req/sec, 500 req/day quota):

```
Testing throttling for Basic tier tenant...
Sending 1000 requests to test rate limiting...

Status Code Distribution:
200: 450-550 requests (successful)
429: 400-500 requests (throttled - EXPECTED)
500: 0-50 requests (cold start/initialization)

Throttling is working correctly!
```

**What's Happening:**
- First ~10 requests: May return 500 (Lambda cold start)
- Next ~500 requests: Return 200 (within rate limit)
- Remaining requests: Return 429 (throttled by API Gateway)

**429 Status Code** = "Too Many Requests" - This is the expected behavior!

### Step 4: Test Different Tiers

Register tenants with different tiers and compare throttling behavior:

```
# Standard tier (100 req/sec, 1000 req/day)
./test-basic-tier-throttling.sh <STANDARD_TENANT_JWT>

# Premium tier (200 req/sec, 5000 req/day)
./test-basic-tier-throttling.sh <PREMIUM_TENANT_JWT>

# Platinum tier (500 req/sec, 10000 req/day)
./test-basic-tier-throttling.sh <PLATINUM_TENANT_JWT>
```

Higher tiers should show fewer 429 responses.

---

## Troubleshooting

### Issue 1: Pipeline Deploy Stage Fails on First Run

**Symptom:**
```
Pipeline stage "Deploy" shows "Failed" status
Lambda function error: ResourceNotFoundException - Table ServerlessSaaS-TenantStackMapping-lab6 not found
```

**Root Cause:**
Pipeline was deployed before shared stack, so DynamoDB tables didn't exist when pipeline Lambda tried to scan them.

**Solution:**
This is now fixed in the deployment script. The script:
1. Deploys shared stack first
2. Waits for DynamoDB tables to be ACTIVE
3. Then deploys pipeline

If you still encounter this:
```
# Manually trigger the pipeline
aws codepipeline start-pipeline-execution \
  --name serverless-saas-pipeline-lab6 \
  --region us-east-1
```

### Issue 2: Tenant Registration Fails with KeyError('Item')

**Symptom:**
```
Error registering tenant
KeyError: 'Item' when retrieving apiGatewayUrl-Pooled from Settings table
```

**Root Cause:**
Pooled stack (`stack-lab6-pooled`) was not created yet, so Settings table doesn't have the `apiGatewayUrl-Pooled` entry.

**Solution:**
Wait for pipeline to complete and create the pooled stack:

```
# Check pipeline status
aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab6 \
  --region us-east-1 \
  --query 'stageStates[?stageName==`Deploy`].latestExecution.status'

# Check if pooled stack exists
aws cloudformation describe-stacks \
  --stack-name stack-lab6-pooled \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'

# Verify Settings table entry
aws dynamodb get-item \
  --table-name ServerlessSaaS-Settings-lab6 \
  --key '{"settingName": {"S": "apiGatewayUrl-Pooled"}}' \
  --region us-east-1
```

### Issue 3: Authorizer Fails with KeyError('apiKey')

**Symptom:**
```
500 Internal Server Error
Lambda authorizer error: KeyError: 'apiKey'
```

**Root Cause:**
TenantDetails table is missing the `apiKey` field for the tenant.

**Solution:**
This should not happen with the current code. If it does:

1. Check if tenant was registered correctly:
   ```
   aws dynamodb get-item \
     --table-name ServerlessSaaS-TenantDetails-lab6 \
     --key '{"tenantId": {"S": "<TENANT_ID>"}}' \
     --region us-east-1
   ```

2. If `apiKey` is missing, re-register the tenant

### Issue 4: Authorizer Fails with KeyError('userPoolId')

**Symptom:**
```
500 Internal Server Error
Lambda authorizer error: KeyError: 'Item' on line 50 (userPoolId)
```

**Root Cause:**
Tenant ID in JWT token doesn't match any tenant in TenantDetails table. This happens when:
- Tenant was deleted and re-registered (new tenant ID)
- Using JWT token from old tenant registration
- Database was cleaned up but Cognito users still exist

**Solution:**
1. Extract tenant ID from JWT token:
   ```
   # Decode JWT token (use jwt.io or)
   echo "<JWT_TOKEN>" | cut -d'.' -f2 | base64 -d | jq '.["custom:tenantId"]'
   ```

2. Check if tenant exists in database:
   ```
   aws dynamodb get-item \
     --table-name ServerlessSaaS-TenantDetails-lab6 \
     --key '{"tenantId": {"S": "<TENANT_ID_FROM_JWT>"}}' \
     --region us-east-1
   ```

3. If tenant doesn't exist, re-register the tenant and get a new JWT token

### Issue 5: Authorizer Role Name Mismatch

**Symptom:**
```
500 Internal Server Error
AccessDenied: User is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam::ACCOUNT:role/authorizer-access-role
```

**Root Cause:**
Authorizer is trying to assume role without `-lab6` suffix.

**Solution:**
This is fixed in the current code. The authorizer now uses:
```python
role_arn = f'arn:aws:iam::{account_id}:role/authorizer-access-role-lab6'
```

If you still see this error, update `tenant_authorizer.py` line 107.

### Issue 6: Client Build Fails (Node.js Compatibility)

**Symptom:**
```
npm install failed
npm run build failed
Error building Admin/Landing/Application UI
```

**Root Cause:**
Node.js v20+ has compatibility issues with Angular dependencies.

**Solution:**
Lab6 includes pre-built client files as a fallback:

```
# Check if pre-built files exist
ls -la Lab6/client/Admin/dist
ls -la Lab6/client/Landing/dist
ls -la Lab6/client/Application/dist
```

The deployment script automatically uses pre-built files if build fails.

**Recommended:** Use Node.js v18.x for best compatibility:
```
# Using nvm
nvm install 18
nvm use 18

# Verify
node --version  # Should show v18.x.x
```

### Issue 7: CloudFront Cache Not Updating

**Symptom:**
Client applications show old content after redeployment.

**Solution:**
CloudFront invalidations are triggered automatically but take 5-10 minutes to complete.

**Manual Invalidation:**
```
# Get distribution IDs
aws cloudfront list-distributions \
  --query 'DistributionList.Items[*].[Id,Origins.Items[0].DomainName]' \
  --output table

# Invalidate specific distribution
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"
```

**Or wait:** CloudFront caches expire automatically within 24 hours.

---

## Cleanup

### Option 1: Automated Cleanup (Recommended)

```
cd Lab6/scripts
./cleanup.sh
```

**What Gets Deleted:**
- All tenant stacks (`stack-*`)
- Shared infrastructure stack
- Pipeline stack
- S3 buckets (emptied first)
- Cognito User Pools
- SAM and CDK resources
- CloudWatch log groups

**Duration:** 10-15 minutes

**Features:**
- Parallel deletion of tenant stacks
- Parallel S3 bucket emptying
- Timestamped log file
- Progress tracking
- Verification at the end

### Option 2: Manual Cleanup

```
# Delete tenant stacks
aws cloudformation delete-stack --stack-name stack-<TENANT_ID>

# Delete shared stack
aws cloudformation delete-stack --stack-name serverless-saas-workshop-shared-lab6

# Delete pipeline stack
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab6

# Empty and delete S3 buckets
aws s3 rm s3://<BUCKET_NAME> --recursive
aws s3 rb s3://<BUCKET_NAME>
```

### Verification

After cleanup, verify all resources are deleted:

```
# Check CloudFormation stacks
aws cloudformation list-stacks \
  --query 'StackSummaries[?contains(StackName, `lab6`) && StackStatus!=`DELETE_COMPLETE`].StackName'

# Check Lambda functions
aws lambda list-functions \
  --query "Functions[?contains(FunctionName, 'lab6')].FunctionName"

# Check DynamoDB tables
aws dynamodb list-tables \
  --query "TableNames[?contains(@, 'lab6')]"

# Check S3 buckets
aws s3 ls | grep lab6

# Check Cognito user pools
aws cognito-idp list-user-pools --max-results 60 \
  --query "UserPools[?contains(Name, 'lab6')].Name"
```

---

## Known Issues and Solutions

### 1. Deployment Order is Critical

**Issue:** Race conditions if deployment order is wrong.

**Solution:** Always follow this order:
1. Shared stack (creates DynamoDB tables)
2. Wait for tables to be ACTIVE
3. Pipeline stack (queries DynamoDB tables)
4. Wait for pipeline to create pooled stack
5. Client applications

The deployment script handles this automatically.

### 2. Pooled Stack Must Exist Before Tenant Registration

**Issue:** Tenant registration fails if pooled stack doesn't exist.

**Solution:** Wait for pipeline Deploy stage to complete before registering tenants.

### 3. JWT Token Expires After 1 Hour

**Issue:** Throttling test fails with 401 Unauthorized after 1 hour.

**Solution:** Get a fresh JWT token from the Landing site before running tests.

### 4. Tenant ID Mismatch After Cleanup/Redeploy

**Issue:** Old JWT tokens have different tenant IDs than database.

**Solution:** Always re-register tenants and get fresh JWT tokens after cleanup/redeploy.

### 5. Cold Start Causes Initial 500 Errors

**Issue:** First few requests return 500 errors.

**Solution:** This is normal Lambda cold start behavior. Subsequent requests will succeed.

---

## Best Practices

### 1. Use Screen Sessions for Deployments

Long deployments (15-25 minutes) can be interrupted by network issues. Use screen:

```
./deploy-with-screen.sh
```

### 2. Save Deployment Outputs

```
# Save stack outputs
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-shared-lab6 \
  --query 'Stacks[0].Outputs' > lab6-outputs.json

# Save application URLs
grep "site URL" deployment-*.log > lab6-urls.txt
```

### 3. Monitor Pipeline Execution

```
# Watch pipeline status
watch -n 10 'aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab6 \
  --query "stageStates[*].[stageName,latestExecution.status]" \
  --output table'
```

### 4. Test Incrementally

1. Deploy infrastructure
2. Verify shared stack is complete
3. Verify pipeline created pooled stack
4. Register one tenant
5. Test with that tenant
6. Register more tenants if needed

### 5. Keep Logs

Deployment and cleanup scripts create timestamped log files:
- `deployment-YYYYMMDD-HHMMSS.log`
- `cleanup-YYYYMMDD-HHMMSS.log`

Keep these for troubleshooting.

### 6. Use Fresh Account for Testing

For the most accurate test of the deployment process:
1. Use a fresh AWS account
2. No prior workshop deployments
3. No existing resources with conflicting names
4. Clean slate ensures all steps work correctly

---

## Performance Optimizations

### Deployment Script Optimizations

1. **Parallel S3 Bucket Emptying**
   - Empties multiple buckets simultaneously
   - Reduces cleanup time by ~50%

2. **Async CloudFront Invalidations**
   - Runs invalidations in background
   - Doesn't block deployment completion
   - Saves ~30 seconds per distribution

3. **Pre-built Client Files**
   - Fallback for Node.js compatibility issues
   - Skips npm install/build if available
   - Reduces deployment time by 2-3 minutes

4. **Parallel Tenant Stack Deletion**
   - Deletes multiple stacks simultaneously
   - Reduces cleanup time significantly

### Cleanup Script Optimizations

1. **Timestamped Log Files**
   - Track cleanup progress
   - Troubleshoot issues
   - Audit trail

2. **Duration Tracking**
   - Shows total cleanup time
   - Helps identify bottlenecks

3. **Parallel Operations**
   - S3 bucket emptying
   - Tenant stack deletion
   - Version deletion in versioned buckets

---

## Additional Resources

- [Lab6 Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Lab6 Security Notes](./SECURITY_NOTES.md)
- [Lab6 Changes Summary](./LAB6_CHANGES_SUMMARY.md)
- [Workshop Deployment Guide](../WORKSHOP_DEPLOYMENT_GUIDE.md)
- [Resource Naming Convention](../RESOURCE_NAMING_CONVENTION.md)

---

## Support

For issues or questions:
1. Check this guide's [Troubleshooting](#troubleshooting) section
2. Review [Known Issues](#known-issues-and-solutions)
3. Check deployment/cleanup log files
4. Review CloudFormation stack events
5. Open an issue on the GitHub repository

---

## Testing Checklist

Use this checklist when deploying Lab6 in a fresh account:

- [ ] All prerequisites installed and verified
- [ ] AWS credentials configured
- [ ] Python virtual environment activated (optional)
- [ ] Deployment script executed successfully
- [ ] Shared stack status: CREATE_COMPLETE
- [ ] Pipeline stack status: CREATE_COMPLETE
- [ ] Pipeline Deploy stage: Succeeded
- [ ] Pooled stack status: CREATE_COMPLETE
- [ ] Settings table has apiGatewayUrl-Pooled entry
- [ ] Client applications deployed successfully
- [ ] Admin site accessible
- [ ] Landing site accessible
- [ ] App site accessible
- [ ] Basic tier tenant registered successfully
- [ ] Tenant login successful
- [ ] JWT token obtained
- [ ] Throttling test executed
- [ ] 429 status codes observed (throttling working)
- [ ] Cleanup script executed successfully
- [ ] All resources deleted and verified

---

**Last Updated:** January 2026  
**Tested By:** AWS Serverless SaaS Workshop Team  
**Test Environment:** Fresh AWS Account, us-east-1 region

