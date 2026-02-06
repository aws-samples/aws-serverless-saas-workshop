# AWS Serverless SaaS Workshop

A comprehensive hands-on workshop for building multi-tenant SaaS solutions using AWS Serverless services.

## Overview

This workshop teaches you how to build a production-ready, multi-tenant SaaS application using AWS Serverless technologies. Through seven progressive labs, you'll learn essential SaaS patterns including tenant isolation, tiered deployments, API throttling, and cost attribution.

### What You'll Build

- **Lab 1**: Basic serverless web application with Lambda, API Gateway, and DynamoDB
- **Lab 2**: Multi-tenant architecture with shared services and tenant management
- **Lab 3**: Microservices with tenant isolation and partitioned data
- **Lab 4**: Advanced tenant isolation using IAM policies and scoped credentials
- **Lab 5**: Tiered deployment strategies with pooled and siloed architectures
- **Lab 6**: API throttling and usage plans per tenant tier
- **Lab 7**: Cost attribution and tenant-level billing in pooled models

## Prerequisites

Before starting the workshop, ensure you have the following installed and configured:

### Required Software

1. **Python 3.14+**
   ```
   python3 --version  # Should show 3.14.x
   ```
   
   **Installation**:
   - macOS: `brew install python@3.14`
   - Windows: Download from https://www.python.org/downloads/
   - Linux: Use your package manager or build from source

2. **AWS CLI v2**
   ```
   aws --version  # Should show aws-cli/2.x.x
   ```
   
   **Installation**:
   - macOS: `brew install awscli`
   - Windows/Linux: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

3. **AWS SAM CLI (v1.70.0+)**
   ```
   sam --version  # Should show SAM CLI, version 1.x.x
   ```
   
   **Installation**:
   - macOS: `brew install aws-sam-cli`
   - Windows/Linux: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html

4. **Docker Desktop**
   ```
   docker --version  # Should show Docker version 20.x.x or higher
   ```
   
   **Installation**: https://docs.docker.com/get-docker/
   
   **Important**: Docker must be running before deploying labs

5. **Node.js LTS (v20.x or v22.x) - REQUIRED**
   ```
   node --version  # Should show v20.x.x or v22.x.x (LTS versions)
   npm --version   # Should show 9.x.x or higher
   ```
   
   **IMPORTANT**: Node.js LTS (Long Term Support) version is required for building Angular client applications.
   
   **Recommended versions**:
   - Node.js v20.x (Active LTS)
   - Node.js v22.x (Active LTS)
   
   **NOT recommended**: Odd-numbered versions (v19, v21, v23, v25) - These are not LTS and may cause compatibility issues
   
   **Installation**:
   
   **Option A: Using Homebrew (macOS)**
   ```
   brew install node@22
   echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```
   
   **Option B: Using nvm (Recommended for managing multiple versions)**
   ```
   # Install nvm
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
   
   # Install Node.js LTS
   nvm install 22
   nvm use 22
   nvm alias default 22
   ```
   
   **Option C: Direct download**
   - Download from: https://nodejs.org/ (choose LTS version)
   
   **Troubleshooting**: If you see an odd-numbered version (v25, v23, etc.), install an LTS version. See [extra-info/NODEJS_LTS_SETUP.md](extra-info/NODEJS_LTS_SETUP.md) for detailed instructions.

6. **AWS CDK CLI (for Labs 5-6)**
   ```
   cdk --version
   ```
   
   **Installation**:
   ```
   npm install -g aws-cdk
   ```

7. **Git**
   ```
   git --version
   ```
   
   **Installation**:
   - macOS: `brew install git` (or use Xcode Command Line Tools)
   - Windows: Download from https://git-scm.com/
   - Linux: Use your package manager (e.g., `apt install git`)

### AWS Account Setup

1. **AWS Account**: You need an AWS account with permissions to create and manage:
   - Lambda functions
   - API Gateway
   - DynamoDB tables
   - Cognito User Pools
   - S3 buckets
   - CloudFormation stacks
   - CodePipeline and CodeCommit
   - CloudWatch logs and metrics
   - IAM roles and policies

2. **AWS Profile Configuration**:
   ```
   # Configure your AWS credentials with a profile name of your choice
   aws configure --profile <your-profile-name>
   
   # Enter your credentials when prompted:
   # AWS Access Key ID: [Your Access Key]
   # AWS Secret Access Key: [Your Secret Key]
   # Default region name: us-east-1 (or us-west-2)
   # Default output format: json
   ```
   
   **Recommended regions**:
   - `us-east-1` (N. Virginia)
   - `us-west-2` (Oregon)

3. **Verify AWS Credentials**:
   ```
   aws sts get-caller-identity --profile <your-profile-name>
   ```

### Email Address

You'll need a valid email address for:
- Admin user creation in Cognito
- Tenant user registration
- Email verification during onboarding

**Tip**: Use the same email address for all labs to simplify testing.

### Verify Prerequisites

Run this script to verify all prerequisites are installed:

```
#!/bin/bash

echo "Checking prerequisites..."
echo ""

# Check AWS CLI
if command -v aws &> /dev/null; then
    echo "✓ AWS CLI: $(aws --version)"
else
    echo "✗ AWS CLI: Not installed"
fi

# Check SAM CLI
if command -v sam &> /dev/null; then
    echo "✓ SAM CLI: $(sam --version)"
else
    echo "✗ SAM CLI: Not installed"
fi

# Check Python
if command -v python3 &> /dev/null; then
    echo "✓ Python: $(python3 --version)"
else
    echo "✗ Python: Not installed"
fi

# Check Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
    if [ $((NODE_MAJOR % 2)) -eq 0 ]; then
        echo "✓ Node.js: $NODE_VERSION (LTS)"
    else
        echo "⚠ Node.js: $NODE_VERSION (NOT LTS - please install v20 or v22)"
    fi
else
    echo "✗ Node.js: Not installed"
fi

# Check CDK
if command -v cdk &> /dev/null; then
    echo "✓ CDK CLI: $(cdk --version)"
else
    echo "⚠ CDK CLI: Not installed (required for Labs 5-6)"
fi

# Check Git
if command -v git &> /dev/null; then
    echo "✓ Git: $(git --version)"
else
    echo "✗ Git: Not installed"
fi

# Check Docker
if command -v docker &> /dev/null; then
    echo "✓ Docker: $(docker --version)"
else
    echo "✗ Docker: Not installed"
fi

# Check AWS credentials
if aws sts get-caller-identity --profile <your-profile-name> &> /dev/null; then
    echo "✓ AWS Profile '<your-profile-name>': Configured"
else
    echo "✗ AWS Profile '<your-profile-name>': Not configured"
fi

echo ""
echo "Prerequisite check complete!"
```

Save this as `check-prerequisites.sh`, make it executable (`chmod +x check-prerequisites.sh`), and run it.

## Architecture

### High-Level Architecture

The workshop demonstrates a complete multi-tenant SaaS architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                     CloudFront (CDN)                        │
│              Admin UI | Landing UI | App UI                 │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│                   API Gateway (REST)                        │
│         /admin/* | /registration/* | /products/*           │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│              Lambda Authorizer (JWT)                        │
│         Tenant Context Injection & Isolation                │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│                  Business Logic Lambdas                     │
│    Product Service | Order Service | Tenant Management     │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│                    Data Layer                               │
│  DynamoDB (Pooled/Siloed) | Cognito | EventBridge          │
└─────────────────────────────────────────────────────────────┘
```

### Multi-Tenant SaaS Patterns

The workshop covers these essential SaaS patterns:

1. **Tenant Isolation**: Ensuring data and resources are isolated between tenants
2. **Pooled vs Siloed Architecture**: Balancing cost efficiency with tenant requirements
3. **Tiered Deployments**: Different infrastructure for different tenant tiers
4. **API Throttling**: Rate limiting based on tenant subscription level
5. **Cost Attribution**: Tracking costs per tenant in shared infrastructure
6. **Tenant Onboarding**: Automated provisioning of tenant resources
7. **Identity & Access Management**: Secure authentication and authorization

### Global Shared Resources

Some resources are intentionally shared across all labs to avoid conflicts and follow AWS best practices:

#### API Gateway CloudWatch Role

**Resource Type**: `AWS::IAM::Role` + `AWS::ApiGateway::Account`

**Role Name**: `apigateway-cloudwatch-publish-role` (NO lab suffix)

**Why Shared**:
- `AWS::ApiGateway::Account` is a **singleton resource** - only ONE can exist per AWS account per region
- It sets the CloudWatch logging role for ALL API Gateways in that region
- This role is shared across all labs to avoid conflicts

**Important Notes**:
- If this role already exists from a previous lab deployment, CloudFormation will reuse it
- When cleaning up labs, do NOT delete this role if other labs are still deployed
- The role is automatically created during the first lab deployment

#### Other Shared Resources

- **CI/CD Pipeline Stack**: `serverless-saas-pipeline` (used by Labs 5-6 for tenant provisioning)
- **CDK Bootstrap Stack**: `CDKToolkit` (required for CDK deployments in Lab 5+)

## Quick Start (Experienced Users)

If you're familiar with AWS and want to deploy quickly:

```
# 1. Configure AWS profile
aws configure --profile <your-profile-name>

# 2. Deploy all labs (recommended - parallel deployment)
cd workshop
./deploy-all.sh --email your-email@example.com --profile <your-profile-name>

# 3. Or deploy individual labs
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile <your-profile-name>

# 4. Get application URLs
./geturl.sh --profile <your-profile-name>

# 5. Clean up when done
cd workshop
./cleanup-all.sh --profile <your-profile-name>
```

## Deployment Steps

### Option 1: Deploy All Labs (Recommended for First-Time Users)

Deploy all labs using the orchestration script with TRUE PARALLEL deployment:

```
cd workshop

# Deploy all labs with automatic user creation (recommended)
./deploy-all.sh --email your-email@example.com --profile <your-profile-name>
```

**Features**:
- TRUE PARALLEL deployment using CloudFormation nested stacks
- All 7 labs deploy simultaneously for maximum speed
- Automatic Cognito user creation when `--email` is provided
- 60-day log retention automatically configured

**Expected Duration**: 15-20 minutes for all labs

### Option 2: Deploy Individual Labs

Deploy labs one at a time for focused learning:

#### Lab 1: Basic Serverless Application

```
cd workshop/Lab1/scripts

# Deploy server and client
./deployment.sh -s -c --profile <your-profile-name>

# Get application URL
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: Lambda functions, API Gateway, DynamoDB tables, CloudFront distribution

**Expected Duration**: 8-10 minutes

#### Lab 2: Multi-Tenant Shared Services

```
cd workshop/Lab2/scripts

# Deploy with admin email
./deployment.sh -s -c --email your-email@example.com --profile <your-profile-name>

# Get application URLs
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: Cognito User Pool, Tenant Management Service, Admin UI, Landing UI

**Expected Duration**: 10-12 minutes

#### Lab 3: Microservices with Tenant Isolation

```
cd workshop/Lab3/scripts

# Deploy shared and tenant infrastructure
./deployment.sh -s -c --email your-email@example.com --tenant-email your-email@example.com --profile <your-profile-name>

# Get application URLs
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: Pooled DynamoDB tables, Product/Order microservices, Tenant API Gateway

**Expected Duration**: 12-15 minutes

#### Lab 4: Advanced Tenant Isolation

```
cd workshop/Lab4/scripts

# Deploy with IAM policies and scoped credentials
./deployment.sh -s -c --email your-email@example.com --tenant-email your-email@example.com --profile <your-profile-name>

# Get application URLs
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: IAM policies for tenant isolation, Lambda authorizer with scoped credentials

**Expected Duration**: 12-15 minutes

#### Lab 5: Tiered Deployment Strategies

```
cd workshop/Lab5/scripts

# Deploy CI/CD pipeline and tiered infrastructure
./deployment.sh -s -c --profile <your-profile-name>

# Get application URLs
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: CodePipeline, CodeCommit, Pooled and Siloed tenant stacks

**Expected Duration**: 15-20 minutes

#### Lab 6: API Throttling and Usage Plans

```
cd workshop/Lab6/scripts

# Deploy with usage plans and API keys
./deployment.sh -s -c --profile <your-profile-name>

# Get application URLs
./geturl.sh --profile <your-profile-name>

# Test throttling behavior (after creating a tenant)
./test-basic-tier-throttling.sh <JWT_TOKEN> --profile <your-profile-name>
```

**What's Deployed**: API Gateway usage plans, API keys per tier, throttling configuration

**Expected Duration**: 15-20 minutes

#### Lab 7: Cost Attribution

```
cd workshop/Lab7/scripts

# Deploy using the deployment script
./deployment.sh --profile <your-profile-name>

# Get resource information
./geturl.sh --profile <your-profile-name>
```

**What's Deployed**: Athena, Glue Crawler, EventBridge rules, Cost attribution Lambda

**Expected Duration**: 10-12 minutes

### Script Parameters Reference

All deployment scripts support these common parameters:

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `--profile` | AWS CLI profile name | No | Machine's default profile |
| `--region` | AWS region | No | us-east-1 |
| `--help` | Show help message | No | - |

Lab-specific parameters:

| Lab | Parameter | Description | Required |
|-----|-----------|-------------|----------|
| Lab 1 | `-s` | Deploy server | No |
| Lab 1 | `-c` | Deploy client | No |
| Lab 2+ | `--email` | Admin email address | Yes (Lab 2+) |
| Lab 3+ | `--tenant-email` | Tenant user email | Yes (Lab 3+) |
| Lab 3-6 | `-s` | Deploy shared stack | No |
| Lab 3-6 | `-c` | Deploy client UIs | No |
| All Labs | `--stack-name` | Custom stack name | No |

**Orchestration Script Parameters** (`./deploy-all.sh`):

```
./deploy-all.sh [OPTIONS]

Options:
  --profile PROFILE         AWS CLI profile (REQUIRED)
  --email EMAIL             Admin email address (triggers automatic user creation)
  --tenant-email EMAIL      Tenant email for auto-tenant creation in Labs 3-4
  --password PASSWORD       Admin temporary password (default: SaaS#Workshop2026)
  --environment ENV         Deployment environment: dev, staging, prod (default: dev)
  --stack-name NAME         Main orchestration stack name (default: serverless-saas-lab)
  --region REGION           AWS region (default: us-east-1)
  --disable-rollback        Disable CloudFormation rollback on failure (for debugging)
  --help                    Show help message
```

## Verification

### Verify Lab Deployment

After deploying each lab, verify successful deployment:

1. **Check CloudFormation Stack Status**:
   ```
   aws cloudformation describe-stacks \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name> \
     --query 'Stacks[0].StackStatus'
   ```
   Expected: `"CREATE_COMPLETE"` or `"UPDATE_COMPLETE"`

2. **Get Application URLs**:
   ```
   cd workshop/Lab1/scripts
   ./geturl.sh --profile <your-profile-name>
   ```

3. **Test Application**:
   - Open the application URL in your browser
   - For Labs 2+: Complete tenant registration
   - Test CRUD operations (create, read, update, delete)

4. **Check CloudWatch Logs**:
   ```
   aws logs describe-log-groups \
     --log-group-name-prefix /aws/lambda/serverless-saas-lab1 \
     --profile <your-profile-name>
   ```

### Lab-Specific Verification

**Lab 1**: 
- Application loads successfully
- Can create and view products/orders
- DynamoDB tables contain data

**Lab 2**:
- Can register new tenant via Landing UI
- Can log in to Admin UI
- Tenant appears in DynamoDB TenantDetails table

**Lab 3**:
- Tenant data is partitioned by tenant ID
- Product and Order APIs work correctly
- Multi-tenant observability in CloudWatch

**Lab 4**:
- Tenant isolation prevents cross-tenant data access
- Lambda authorizer generates scoped credentials
- IAM policies enforce tenant boundaries

**Lab 5**:
- Platinum tier tenant gets dedicated infrastructure
- Basic/Standard/Premium tiers use pooled resources
- CodePipeline deploys changes automatically

**Lab 6**:
- API throttling limits enforced per tier
- Basic tier: 10 requests/second
- Standard tier: 50 requests/second
- Premium/Platinum: Higher limits

**Lab 7**:
- Cost attribution data appears in Athena
- Tenant-level metrics in CloudWatch
- Glue Crawler processes CUR data

## Cleanup

### Clean Up Individual Labs

Remove resources for a specific lab:

**All Labs (Lab 1-7):**
```
cd workshop/Lab1/scripts  # Change to appropriate lab directory

# Non-interactive cleanup (recommended)
echo "yes" | ./cleanup.sh --profile <your-profile-name>
```

**Note**: All lab cleanup scripts now use a consistent interface. The `--stack-name` parameter is no longer required.

### Clean Up All Labs

Remove all workshop resources:

```
cd workshop

# Non-interactive cleanup (recommended)
echo "yes" | ./cleanup-all.sh --profile <your-profile-name>

# Or with auto-confirm flag
./cleanup-all.sh -y --profile <your-profile-name>
```

**Expected Duration**: 15-30 minutes for all labs (CloudFront propagation takes time)

### Verify Cleanup

After cleanup, verify all resources are removed:

```
# Check CloudFormation stacks
aws cloudformation list-stacks \
  --stack-status-filter DELETE_COMPLETE \
  --profile <your-profile-name> \
  --query 'StackSummaries[?contains(StackName, `serverless-saas-lab`)].StackName'

# Check S3 buckets
aws s3 ls --profile <your-profile-name> | grep serverless-saas

# Check CloudWatch log groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/serverless-saas \
  --profile <your-profile-name>
```

All commands should return empty results or show DELETE_COMPLETE status.

## Best Practices

### Deployment Best Practices

1. **Deploy Labs Sequentially**: Deploy labs in order (Lab 1 → Lab 2 → Lab 3, etc.) to understand the progression of concepts and avoid dependency issues.

2. **Test Before Moving Forward**: Verify each lab works correctly before proceeding to the next one. This helps isolate issues and ensures a solid foundation.

3. **Save Deployment Outputs**: Each lab deployment outputs important values (API URLs, Cognito pool IDs, etc.). Save these for reference:
   ```
   aws cloudformation describe-stacks \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name> \
     --query 'Stacks[0].Outputs' > lab1-outputs.json
   ```

4. **Monitor CloudFormation Events**: Keep an eye on deployment progress and catch issues early:
   ```
   aws cloudformation describe-stack-events \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name> \
     --max-items 20
   ```

5. **Keep Labs Isolated**: Each lab is designed to be independent. You can have multiple labs deployed simultaneously without conflicts thanks to the naming convention.

### CloudFormation Custom Resources

**Always include `ServiceTimeout: 300` in custom resource definitions** to prevent premature timeouts during CloudFormation operations.

**Why This Matters**:
- Custom resources execute Lambda functions that may need time to complete operations (DynamoDB writes, API calls, etc.)
- Default CloudFormation timeout for custom resources can be too short
- A 300-second (5-minute) timeout provides adequate time for most operations
- Prevents deployment failures due to timeout issues

**Example**:
```yaml
UpdateSettingsTable:
  Type: Custom::UpdateSettingsTable
  Properties:
    ServiceToken: !Ref UpdateSettingsTableFunctionArn
    SettingsTableName: !Ref ServerlessSaaSSettingsTableName
    cognitoUserPoolId: !Ref CognitoUserPoolId
    cognitoUserPoolClientId: !Ref CognitoUserPoolClientId
    ServiceTimeout: 300  # Always include this
```

**Common Custom Resource Operations**:
- Initializing DynamoDB tables with configuration data
- Updating API Gateway usage plans
- Configuring tenant-specific resources
- Cross-stack resource coordination

## Troubleshooting

### Common Issues and Solutions

#### 1. Docker Not Running

**Error**: `Cannot connect to the Docker daemon`

**Solution**:
```
# Start Docker Desktop
# On macOS: Open Docker Desktop application
# On Linux: sudo systemctl start docker
# Verify: docker ps
```

#### 2. AWS Credentials Not Configured

**Error**: `Unable to locate credentials`

**Solution**:
```
aws configure --profile <your-profile-name>
# Enter your AWS Access Key ID and Secret Access Key
```

#### 3. SAM Build Fails

**Error**: `Build Failed Error: PythonPipBuilder:ResolveDependencies`

**Solution**:
```
# Ensure Python 3.14 is installed
python3 --version

# Clear SAM cache
rm -rf .aws-sam

# Rebuild
sam build
```

#### 4. Stack Already Exists

**Error**: `Stack [serverless-saas-lab1] already exists`

**Solution**:
```
# Option 1: Use a different stack name
./deployment.sh --stack-name my-unique-stack --profile <your-profile-name>

# Option 2: Delete existing stack first
./cleanup.sh --profile <your-profile-name>
```

#### 5. API Gateway CloudWatch Role Already Exists

**Error**: `CREATE_FAILED: ApiGatewayCloudWatchLogRole - Role with name apigateway-cloudwatch-publish-role already exists`

**Solution**:
This is expected behavior when deploying a second or subsequent lab. The role is shared across all labs and will be automatically reused. The deployment will continue successfully.

**Why This Happens**:
- `AWS::ApiGateway::Account` is a singleton resource (only one per region)
- The role is intentionally shared across all labs
- CloudFormation templates are designed to handle this gracefully

#### 6. S3 Bucket Name Already Exists

**Error**: `CREATE_FAILED: Bucket name already exists`

**Solution**:
S3 bucket names must be globally unique. The workshop uses ShortId to ensure uniqueness:

```yaml
BucketName: !Sub 
  - 'serverless-saas-lab1-app-${ShortId}'
  - ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

If this error occurs:
1. Delete the existing bucket (if safe to do so)
2. Or modify the bucket name pattern in the template
3. Ensure you're not reusing stack names from previous deployments

#### 7. DynamoDB Table Already Exists

**Error**: `CREATE_FAILED: Table ServerlessSaaS-TenantDetails-lab1 already exists`

**Solution**:
Ensure you're using the correct lab number suffix. Each lab should have unique table names:
- Lab 1: `ServerlessSaaS-TenantDetails-lab1`
- Lab 2: `ServerlessSaaS-TenantDetails-lab2`
- etc.

If the table exists from a previous deployment, clean up the old stack first.

#### 8. IAM Role Name Conflict

**Error**: `CREATE_FAILED: Role with name {role-name} already exists`

**Solution**:
Verify all IAM roles have the correct lab suffix:
- Regional roles: `{role-name}-lab1-us-east-1`
- Global roles: `{role-name}-lab1`
- Shared role (API Gateway): `apigateway-cloudwatch-publish-role` (no suffix)

#### 9. Stack Rollback

**Error**: `ROLLBACK_IN_PROGRESS: The following resource(s) failed to create`

**Solution**:
1. Check CloudFormation events for specific error:
   ```
   aws cloudformation describe-stack-events \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name> \
     --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
   ```

2. Delete the failed stack:
   ```
   aws cloudformation delete-stack \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name>
   ```

3. Fix the issue in the template and redeploy

#### 10. Email Not Received

**Issue**: Cognito verification email not received

**Solution**:
- Check spam/junk folder
- Verify email address is correct
- Check Cognito User Pool in AWS Console
- Resend verification email from Cognito Console

#### 11. CloudFormation Stack Stuck

**Issue**: Stack stuck in CREATE_IN_PROGRESS or DELETE_IN_PROGRESS

**Solution**:
```
# Check stack events for errors
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-lab1 \
  --profile <your-profile-name> \
  --max-items 20

# If stuck in DELETE_IN_PROGRESS, wait or manually delete resources
```

#### 12. S3 Bucket Not Empty

**Error**: `The bucket you tried to delete is not empty`

**Solution**:
```
# Empty bucket before deletion
aws s3 rm s3://your-bucket-name --recursive --profile <your-profile-name>

# Then delete bucket
aws s3 rb s3://your-bucket-name --profile <your-profile-name>
```

#### 13. Lambda Function Errors

**Issue**: Lambda function returns 500 errors

**Solution**:
```
# Check CloudWatch logs
aws logs tail /aws/lambda/serverless-saas-lab1-ProductService \
  --follow \
  --profile <your-profile-name>

# Common causes:
# - Missing environment variables
# - DynamoDB table not found
# - IAM permission issues
```

#### 14. API Gateway 403 Forbidden

**Issue**: API requests return 403 Forbidden

**Solution**:
- Verify JWT token is valid and not expired
- Check Lambda authorizer logs
- Verify IAM policies allow the operation
- Ensure tenant context is correctly injected

#### 15. Deployment Timeout

**Issue**: Deployment takes longer than expected

**Solution**:
- CloudFront distributions take 15-20 minutes to deploy
- Lambda functions with large dependencies take longer to build
- Check AWS Service Health Dashboard for outages
- Increase timeout in deployment script if needed

#### 16. Python Syntax Errors

**Error**: `Validating server code using pylint - ERROR: Syntax error in {file}.py`

**Solution**:
1. Check Python file for syntax errors
2. Common issues:
   - Incorrect indentation
   - Missing colons
   - Typos in keywords (e.g., `iif` instead of `if`)
3. Fix and redeploy

### Getting Help

If you encounter issues not covered here:

1. **Check CloudFormation Events**:
   ```
   aws cloudformation describe-stack-events \
     --stack-name serverless-saas-lab1 \
     --profile <your-profile-name>
   ```

2. **Check CloudWatch Logs**:
   ```
   aws logs tail /aws/lambda/your-function-name \
     --follow \
     --profile <your-profile-name>
   ```

3. **Review Lab-Specific README**: Each lab has detailed instructions in `workshop/LabN/README.md`

4. **Detailed Deployment Guide**: See [extra-info/DETAILED_DEPLOYMENT_GUIDE.md](extra-info/DETAILED_DEPLOYMENT_GUIDE.md) for advanced troubleshooting

5. **Official Workshop Guide**: https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US

### Advanced Troubleshooting Commands

For deeper investigation:

```
# Check stack status
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile <your-profile-name> \
  --query 'Stacks[0].StackStatus'

# View detailed stack events
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-lab1 \
  --profile <your-profile-name> \
  --max-items 50

# Check Lambda function logs
aws logs tail /aws/lambda/serverless-saas-lab1-ProductService --follow

# Test API Gateway endpoint
curl -X GET https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/tenants \
  -H "x-api-key: {api-key}"

# Check DynamoDB table
aws dynamodb scan --table-name ServerlessSaaS-TenantDetails-lab1 --limit 10
```

## Lab-Specific Documentation

Each lab includes detailed instructions and learning objectives:

- [Lab 1: Basic Serverless Application](Lab1/README.md)
- [Lab 2: Multi-Tenant Shared Services](Lab2/README.md)
- [Lab 3: Microservices with Tenant Isolation](Lab3/README.md)
- [Lab 4: Advanced Tenant Isolation](Lab4/README.md)
- [Lab 5: Tiered Deployment Strategies](Lab5/README.md)
- [Lab 6: API Throttling and Usage Plans](Lab6/README.md)
- [Lab 7: Cost Attribution](Lab7/README.md)

## Additional Resources

- **Prerequisites Guide**: [extra-info/PREREQUISITES.md](extra-info/PREREQUISITES.md) - Detailed installation instructions and verification
- **Deployment Manual**: [extra-info/DEPLOYMENT_CLEANUP_MANUAL.md](extra-info/DEPLOYMENT_CLEANUP_MANUAL.md)
- **Detailed Deployment Guide**: [extra-info/DETAILED_DEPLOYMENT_GUIDE.md](extra-info/DETAILED_DEPLOYMENT_GUIDE.md)
- **Resource Naming Convention**: [extra-info/RESOURCE_NAMING_CONVENTION.md](extra-info/RESOURCE_NAMING_CONVENTION.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this workshop.

## License

This workshop is licensed under the MIT-0 License. See [LICENSE](LICENSE) for details.

## Support

For issues, questions, or feedback:
- Open an issue in the GitHub repository
- Refer to the official AWS workshop guide
- Check AWS documentation for specific services

---

**Happy Learning!** 🚀
