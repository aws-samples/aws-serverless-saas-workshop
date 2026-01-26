# Lab 2: Introducing SaaS Shared Services

## Quick Reference

**Deployment Time:** ~10-15 minutes | **Cleanup Time:** ~15-20 minutes

### Quick Start
```
# Deploy
cd workshop/Lab2/scripts
./deployment.sh -s -c --email your-email@example.com --profile serverless-saas-demo

# Get URLs
./geturl.sh --profile serverless-saas-demo

# Cleanup
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab2 --profile serverless-saas-demo
```

### What You'll Deploy
- **16 Lambda Functions** - Tenant/user management (Python 3.14)
- **2 DynamoDB Tables** - TenantDetails, TenantUserMapping
- **2 Cognito User Pools** - PooledTenant (tenants), OperationUsers (admins)
- **1 API Gateway** - Admin API for tenant/user operations
- **2 CloudFront Distributions** - Admin UI, Landing UI
- **2 S3 Buckets** - Static website hosting

### Key Features
- Tenant registration and management
- User management with Cognito authentication
- Admin portal for tenant operations
- Landing page for tenant sign-up
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

---

## Overview

Lab 2 builds upon Lab 1 by introducing multi-tenancy infrastructure and shared services. This lab demonstrates how to implement tenant management, user authentication, and administrative capabilities in a SaaS application using AWS Cognito, Lambda, and DynamoDB.

**What You'll Build:**
- Tenant registration and management system
- User authentication with Amazon Cognito
- Admin portal for tenant operations
- Landing page for tenant sign-up
- Shared services architecture for multi-tenancy

**Learning Objectives:**
- Implement tenant management in a SaaS application
- Configure Amazon Cognito for user authentication
- Build admin and landing page UIs
- Understand shared services architecture patterns
- Manage tenant-user relationships in DynamoDB

## Prerequisites

### Required Tools
- **AWS CLI** (v2.x or later)
- **AWS SAM CLI** (v1.x or later)
- **Python 3.14**
- **Node.js** (v18.x or later) - For client deployment
- **Docker** - Required for SAM build
- **Git**

### AWS Account Requirements
- Active AWS account with appropriate permissions
- AWS credentials configured locally
- Sufficient service limits for:
  - Lambda functions (16 functions)
  - DynamoDB tables (2 tables)
  - Cognito User Pools (2 pools)
  - API Gateway REST APIs (1 API)
  - CloudFront distributions (2 distributions)
  - S3 buckets (2 buckets)

### AWS Profile Setup
```
aws configure --profile serverless-saas-demo
```

## Architecture

### High-Level Architecture
```
┌──────────────┐         ┌──────────────┐
│  Admin UI    │         │  Landing UI  │
│ (CloudFront) │         │ (CloudFront) │
└──────┬───────┘         └──────┬───────┘
       │                        │
       └────────┬───────────────┘
                │
                ▼
        ┌───────────────┐
        │  Admin API    │ ◄── API Gateway
        │   Gateway     │
        └───────┬───────┘
                │
                ▼
┌───────────────────────────────────────┐
│         Lambda Functions              │
│  ┌─────────────┐  ┌─────────────┐   │
│  │   Tenant    │  │    User     │   │
│  │ Management  │  │ Management  │   │
│  └─────────────┘  └─────────────┘   │
└───────────────┬───────────────────────┘
                │
        ┌───────┴────────┐
        │                │
        ▼                ▼
┌──────────────┐  ┌──────────────┐
│   DynamoDB   │  │   Cognito    │
│    Tables    │  │  User Pools  │
└──────────────┘  └──────────────┘
```

### Components

#### Lambda Functions (16 total)
**Tenant Management:**
- `CreateTenantFunction` - Create new tenant
- `GetTenantFunction` - Retrieve tenant details
- `GetTenantsFunction` - List all tenants
- `UpdateTenantFunction` - Update tenant information
- `ActivateTenantFunction` - Activate tenant
- `DeactivateTenantFunction` - Deactivate tenant
- `RegisterTenantFunction` - Register tenant via landing page

**User Management:**
- `CreateUserFunction` - Create new user
- `GetUserFunction` - Retrieve user details
- `GetUsersFunction` - List all users
- `UpdateUserFunction` - Update user information
- `DisableUserFunction` - Disable single user
- `DisableUsersByTenantFunction` - Disable all tenant users
- `EnableUsersByTenantFunction` - Enable all tenant users
- `CreateTenantAdminUserFunction` - Create tenant admin

**Authorization:**
- `SharedServicesAuthorizerFunction` - API Gateway authorizer

#### DynamoDB Tables (2 total)
- `ServerlessSaaS-TenantDetails-lab2` - Tenant information
- `ServerlessSaaS-TenantUserMapping-lab2` - User-tenant relationships

#### Cognito User Pools (2 total)
- `PooledTenant-ServerlessSaaS-lab2-UserPool` - Tenant users
- `OperationUsers-ServerlessSaaS-lab2-UserPool` - Admin users

#### CloudFront Distributions (2 total)
- Admin UI distribution
- Landing page distribution

## Deployment Steps

### Step 1: Navigate to Lab 2 Directory
```
cd workshop/Lab2/scripts
```

### Step 2: Deploy the Application

**Full Deployment (Server + Client):**
```
./deployment.sh -s -c --email your-email@example.com --profile serverless-saas-demo
```

**Server Only:**
```
./deployment.sh -s --email your-email@example.com --profile serverless-saas-demo
```

**Client Only (requires server deployed first):**
```
./deployment.sh -c --profile serverless-saas-demo
```

**Deployment Options:**
- `-s, --server` - Deploy backend infrastructure
- `-c, --client` - Deploy frontend applications
- `--email <email>` - Admin user email (required for server deployment)
- `--profile <name>` - AWS profile to use (optional)
- `--region <region>` - AWS region (default: us-east-1)
- `--stack-name <name>` - CloudFormation stack name (default: serverless-saas-lab2)
- `-h, --help` - Display help message

**Expected Deployment Time:** 10-15 minutes

### Step 3: Retrieve Application URLs
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Output:**
```
Admin Site URL: https://<admin-cloudfront-id>.cloudfront.net
Landing Site URL: https://<landing-cloudfront-id>.cloudfront.net
Admin API URL: https://<api-id>.execute-api.us-east-1.amazonaws.com/Prod
```

### Step 4: Retrieve Admin Credentials
Check your email for temporary admin credentials sent by Cognito.

## Verification

### 1. Verify CloudFormation Stack
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab2 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

**Expected Output:** `"CREATE_COMPLETE"`

### 2. Verify Lambda Functions
```
aws lambda list-functions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `lab2`)].FunctionName'
```

**Expected Output:** List of 16 Lambda functions

### 3. Verify DynamoDB Tables
```
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'TableNames[?contains(@, `lab2`)]'
```

**Expected Output:** `["ServerlessSaaS-TenantDetails-lab2", "ServerlessSaaS-TenantUserMapping-lab2"]`

### 4. Verify Cognito User Pools
```
aws cognito-idp list-user-pools \
  --max-results 20 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'UserPools[?contains(Name, `lab2`)].Name'
```

**Expected Output:** Two user pools with `lab2` in their names

## Testing

### Tenant Onboarding via Landing Page

1. **Access Landing Page:**
   Open the Landing Site URL in your browser

2. **Register New Tenant:**
   - Click "Sign Up"
   - Fill in tenant details:
     - Company Name
     - Email
     - Tier (Basic/Standard/Premium/Platinum)
   - Submit registration

3. **Verify Tenant Creation:**
   ```
   API_URL=$(aws cloudformation describe-stacks \
     --stack-name serverless-saas-lab2 \
     --profile serverless-saas-demo \
     --region us-east-1 \
     --query 'Stacks[0].Outputs[?OutputKey==`AdminApiGatewayUrl`].OutputValue' \
     --output text)
   
   # Get admin token first (login via Admin UI)
   curl -X GET ${API_URL}/tenants \
     -H "Authorization: Bearer <admin-token>"
   ```

### Tenant Management via Admin Portal

1. **Access Admin Portal:**
   Open the Admin Site URL in your browser

2. **Login:**
   Use the admin credentials sent to your email

3. **Manage Tenants:**
   - View all tenants
   - Create new tenant
   - Update tenant details
   - Activate/deactivate tenants

4. **Manage Users:**
   - View users for a tenant
   - Create new users
   - Update user information
   - Enable/disable users

### API Testing

**Register Tenant via API:**
```
curl -X POST ${API_URL}/registration \
  -H "Content-Type: application/json" \
  -d '{
    "tenantName": "Test Company",
    "tenantEmail": "test@example.com",
    "tenantTier": "Standard",
    "tenantPhone": "555-0100",
    "tenantAddress": "123 Main St"
  }'
```

**List Tenants (requires admin token):**
```
curl -X GET ${API_URL}/tenants \
  -H "Authorization: Bearer <admin-token>"
```

## Cleanup

### Automated Cleanup (Recommended)
```
cd workshop/Lab2/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab2 --profile serverless-saas-demo
```

### Interactive Cleanup
```
./cleanup.sh --stack-name serverless-saas-lab2 --profile serverless-saas-demo
```

### What Gets Deleted
- CloudFormation stack and all nested resources
- Lambda functions and layers
- API Gateway REST API and execution logs
- DynamoDB tables
- Cognito User Pools
- CloudFront distributions (2)
- S3 buckets (2) including all objects
- CloudWatch log groups
- IAM roles and policies

**Cleanup Time:** 15-20 minutes

## Troubleshooting

### Deployment Issues

#### Issue: "Email parameter required"
**Solution:**
The `--email` parameter is required for server deployment:
```
./deployment.sh -s --email your-email@example.com --profile serverless-saas-demo
```

#### Issue: "Cognito domain already exists"
**Solution:**
Cognito domains must be globally unique. The deployment script uses a ShortId to ensure uniqueness. If this fails, manually delete the existing domain or use a different stack name.

#### Issue: "Admin user not created"
**Solution:**
Check your email (including spam folder) for Cognito verification email. If not received:
```
aws cognito-idp admin-get-user \
  --user-pool-id <pool-id> \
  --username <email> \
  --profile serverless-saas-demo \
  --region us-east-1
```

### Runtime Issues

#### Issue: "Cannot create tenant - table not found"
**Solution:**
Verify DynamoDB tables exist and Lambda functions have correct environment variables:
```
aws lambda get-function-configuration \
  --function-name serverless-saas-lab2-CreateTenantFunction \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Environment.Variables'
```

#### Issue: "Unauthorized error from API"
**Solution:**
1. Verify you're using a valid JWT token from Cognito
2. Check the authorizer Lambda function logs
3. Ensure the token hasn't expired (tokens expire after 1 hour)

#### Issue: "CloudFront returns 403 error"
**Solution:**
Wait 15-20 minutes for CloudFront distribution to fully deploy. Check distribution status:
```
aws cloudfront list-distributions \
  --profile serverless-saas-demo \
  --query 'DistributionList.Items[?contains(Comment, `lab2`)].Status'
```

### Cleanup Issues

#### Issue: "Cannot delete Cognito User Pool - users exist"
**Solution:**
The cleanup script handles this automatically. If manual cleanup is needed:
```
# List users
aws cognito-idp list-users \
  --user-pool-id <pool-id> \
  --profile serverless-saas-demo \
  --region us-east-1

# Delete each user
aws cognito-idp admin-delete-user \
  --user-pool-id <pool-id> \
  --username <username> \
  --profile serverless-saas-demo \
  --region us-east-1
```

## Additional Resources

### Documentation
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/latest/developerguide/)
- [Multi-Tenant SaaS on AWS](https://aws.amazon.com/solutions/implementations/saas-identity-and-isolation-with-amazon-cognito/)
- [SaaS Architecture Patterns](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)

### Workshop Resources
- [Lab 2 Summary](LAB2_SUMMARY.md) - Quick reference guide
- [Deployment Manual](../DEPLOYMENT_CLEANUP_MANUAL.md) - Comprehensive deployment guide

### Next Steps
After completing Lab 2, proceed to:
- **Lab 3**: Adding Multi-Tenancy to Microservices - Implement tenant isolation and partitioned data

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review deployment logs in `workshop/Lab2/logs/`
3. Consult the [Deployment Manual](../DEPLOYMENT_CLEANUP_MANUAL.md)

## License

This workshop is licensed under the MIT-0 License. See the LICENSE file for details.
