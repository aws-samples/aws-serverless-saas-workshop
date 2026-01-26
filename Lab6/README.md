# Lab 6: Tenant Throttling and API Quotas

## Overview

Lab 6 introduces tenant throttling and API quota management for multi-tenant SaaS applications. This lab demonstrates how to implement tier-based rate limiting using AWS API Gateway usage plans and API keys. You'll learn how to configure different throttling limits for each tenant tier, test throttling behavior, and ensure fair resource allocation across tenants.

**Key Concepts:**
- API Gateway usage plans for tier-based throttling
- API keys for tenant identification and quota enforcement
- Rate limiting and burst limits per tenant tier
- Testing throttling behavior with concurrent requests
- Fair resource allocation in multi-tenant environments

**What You'll Build:**
- Four usage plans (Basic, Standard, Premium, Platinum) with different throttling limits
- API keys associated with each tenant tier
- Throttling configuration at the API Gateway level
- Test scripts to verify throttling behavior
- Monitoring and metrics for API usage per tenant

## Prerequisites

Before starting this lab, ensure you have:

- **AWS Account**: With appropriate permissions to create resources
- **AWS CLI**: Installed and configured with profile `serverless-saas-demo`
- **SAM CLI**: Installed for serverless application deployment
- **Python 3.14**: Installed and available in your PATH
- **Node.js and npm**: For Angular applications
- **Git**: For CodeCommit repository operations
- **jq**: For JSON parsing in test scripts
- **Completed Labs 1-5**: Understanding of previous concepts (optional but recommended)

**Verify Prerequisites:**
```
aws --version
sam --version
python3 --version
node --version
git --version
jq --version
```

**Configure AWS Profile:**
```
aws configure --profile serverless-saas-demo
# Enter your AWS Access Key ID, Secret Access Key, and default region (us-east-1)
```

## Architecture

Lab 6 builds upon Lab 5's tier-based deployment architecture and adds API Gateway usage plans for throttling:

### Shared Stack (Pooled Model)

**For Basic, Standard, and Premium Tier Tenants:**
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: 
  - TenantDetails-lab6 (tenant metadata)
  - TenantUserMapping-lab6 (user-tenant associations)
  - TenantStackMapping-lab6 (tenant infrastructure tracking)
  - Settings-lab6 (system configuration)
- **Cognito User Pools**: 
  - PooledTenant (shared user pool for Basic/Standard/Premium tenants)
  - OperationUsers (admin users)
- **Admin API Gateway**: Handles tenant/user management operations
- **API Gateway Usage Plans**: Four usage plans with different throttling limits
  - **Basic Tier**: 10 requests/second, 20 burst
  - **Standard Tier**: 50 requests/second, 100 burst
  - **Premium Tier**: 100 requests/second, 200 burst
  - **Platinum Tier**: 500 requests/second, 1000 burst
- **API Keys**: One API key per usage plan for tenant identification
- **CloudFront Distributions**: 3 distributions for Admin, Landing, and Application UIs
- **S3 Buckets**: Static website hosting for all three applications

### Pipeline Stack (Siloed Model)

**For Platinum Tier Tenants:**
- **CodePipeline**: Automated deployment pipeline triggered on tenant creation
- **CodeBuild**: Builds and deploys tenant-specific CloudFormation stacks
- **CodeCommit**: Source repository containing tenant infrastructure templates
- **Lambda Function**: Triggers pipeline execution when Platinum tenant is created
- **S3 Bucket**: Pipeline artifacts
- **CloudWatch Logs**: Pipeline execution logs with 60-day retention
- **Dedicated Resources per Platinum Tenant**:
  - Dedicated Cognito User Pool
  - Dedicated DynamoDB tables (Products, Orders)
  - Dedicated Lambda functions
  - Dedicated API Gateway with Platinum usage plan

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        CloudFront CDN                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Admin UI     │  │ Landing UI   │  │ App UI       │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Admin API Gateway                             │
│              (Tenant & User Management)                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Usage Plans & API Keys (Throttling)                      │  │
│  │  • Basic:    10 req/s,  20 burst                         │  │
│  │  • Standard: 50 req/s, 100 burst                         │  │
│  │  • Premium: 100 req/s, 200 burst                         │  │
│  │  • Platinum: 500 req/s, 1000 burst                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Shared Services                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Tenant Management │ User Management │ Registration       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ DynamoDB: TenantDetails, TenantUserMapping,              │  │
│  │           TenantStackMapping, Settings                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ▼                           ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│   Pooled Model            │   │   Siloed Model            │
│   (Basic/Standard/Premium)│   │   (Platinum)              │
│                           │   │                           │
│ • Shared Cognito Pool     │   │ • CodePipeline            │
│ • Shared DynamoDB Tables  │   │ • CodeCommit Repo         │
│ • Shared Lambda Functions │   │ • CodeBuild               │
│ • Shared API Gateway      │   │ • Lambda Trigger          │
│ • Throttled by API Key    │   │                           │
│                           │   │ Per-Tenant Resources:     │
│                           │   │ • Dedicated Cognito Pool  │
│                           │   │ • Dedicated DynamoDB      │
│                           │   │ • Dedicated Lambda        │
│                           │   │ • Dedicated API Gateway   │
│                           │   │ • Platinum Usage Plan     │
└───────────────────────────┘   └───────────────────────────┘
```

### Throttling Flow

**Request Processing with Throttling:**
1. Client makes API request with API key in header
2. API Gateway identifies tenant tier from API key
3. API Gateway applies usage plan throttling limits
4. If within limits: Request proceeds to Lambda authorizer
5. If exceeds limits: API Gateway returns 429 (Too Many Requests)
6. Lambda authorizer validates JWT and injects tenant context
7. Business logic Lambda processes request
8. Response returned to client

**Throttling Limits by Tier:**
- **Basic**: 10 requests/second steady state, 20 burst capacity
- **Standard**: 50 requests/second steady state, 100 burst capacity
- **Premium**: 100 requests/second steady state, 200 burst capacity
- **Platinum**: 500 requests/second steady state, 1000 burst capacity

## Deployment Steps

### Step 1: Navigate to Lab 6 Directory

```
cd workshop/Lab6/scripts
```

### Step 2: Deploy Lab 6 Infrastructure

Lab 6 requires deploying both the shared infrastructure (with usage plans) and the CI/CD pipeline. Use the `-s` flag to deploy the complete server infrastructure and `-c` flag to deploy the client applications.

```
./deployment.sh -s -c --profile serverless-saas-demo
```

**What This Command Does:**
- **Shared Infrastructure** (`-s` includes shared stack):
  - Deploys shared services (Tenant Management, User Management, Registration)
  - Creates DynamoDB tables for tenant data
  - Sets up Cognito user pools
  - Deploys Admin API Gateway with usage plans
  - Creates four usage plans (Basic, Standard, Premium, Platinum)
  - Generates API keys for each usage plan
  - Creates CloudFront distributions and S3 buckets
- **Pipeline Infrastructure** (`-s` includes pipeline):
  - Creates CodeCommit repository (`aws-serverless-saas-workshop`)
  - Pushes workshop code to CodeCommit
  - Deploys CodePipeline stack using CDK
  - Creates Lambda trigger for Platinum tenant provisioning
  - **Waits for pipeline to create pooled stack** (5-10 minutes)
- **Client Applications** (`-c`):
  - Builds and deploys Admin UI (Angular)
  - Builds and deploys Landing UI (Angular)
  - Builds and deploys Application UI (Angular)
  - Uploads to S3 and invalidates CloudFront caches

**Deployment Time:** Approximately 25-30 minutes (includes waiting for pipeline)

**Expected Output:**
```
==========================================
Lab6 Deployment Complete!
==========================================
Duration: 27m 45s

Application URLs:
  Admin Site: https://<admin-cloudfront-id>.cloudfront.net
  Landing Site: https://<landing-cloudfront-id>.cloudfront.net
  App Site: https://<app-cloudfront-id>.cloudfront.net
  Admin API: https://<api-id>.execute-api.us-east-1.amazonaws.com/prod

Next Steps:
  1. Monitor the pipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view
  2. Access the Admin site to create tenants
  3. Test throttling behavior with test-basic-tier-throttling.sh
  4. Open the application URLs in your browser
  5. To retrieve URLs later: ./geturl.sh --profile serverless-saas-demo
  6. To clean up resources: ./cleanup.sh --stack-name serverless-saas-lab6 --profile serverless-saas-demo
```

**Important Note:** The deployment script automatically waits for the pipeline to create the `stack-lab6-pooled` stack. This stack is required for tenant registration to work. If the pipeline fails or times out, you can manually trigger it from the CodePipeline console.

### Step 3: Retrieve Application URLs

If you need to retrieve the URLs after deployment:

```
./geturl.sh --profile serverless-saas-demo
```

This will display:
- Admin Site URL (for tenant management)
- Landing Site URL (for tenant registration)
- App Site URL (for tenant application access)
- Pipeline Name (for monitoring Platinum tenant deployments)

## Verification

### Verify Shared Infrastructure

1. **Check CloudFormation Stack:**
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```
Expected output: `"CREATE_COMPLETE"`

2. **Verify DynamoDB Tables:**
```
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'TableNames[?contains(@, `lab6`)]'
```
Expected tables:
- ServerlessSaaS-TenantDetails-lab6
- ServerlessSaaS-TenantUserMapping-lab6
- ServerlessSaaS-TenantStackMapping-lab6
- ServerlessSaaS-Settings-lab6

3. **Verify Cognito User Pools:**
```
aws cognito-idp list-user-pools \
  --max-results 20 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'UserPools[?contains(Name, `lab6`)]'
```
Expected pools:
- serverless-saas-pooled-lab6
- serverless-saas-operations-lab6

4. **Verify Lambda Functions:**
```
aws lambda list-functions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `lab6`)].FunctionName'
```
Expected: 16+ Lambda functions for tenant/user management

### Verify Pipeline Infrastructure

1. **Check Pipeline Stack:**
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-pipeline-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```
Expected output: `"CREATE_COMPLETE"`

2. **Verify Pooled Stack (Created by Pipeline):**
```
aws cloudformation describe-stacks \
  --stack-name stack-lab6-pooled \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```
Expected output: `"CREATE_COMPLETE"`

**Note:** The pooled stack is automatically created by the pipeline during deployment. If it doesn't exist, check the pipeline execution status.

3. **Verify CodeCommit Repository:**
```
aws codecommit get-repository \
  --repository-name aws-serverless-saas-workshop \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'repositoryMetadata.repositoryName'
```
Expected output: `"aws-serverless-saas-workshop"`

4. **Verify CodePipeline:**
```
aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'pipelineName'
```
Expected output: `"serverless-saas-pipeline-lab6"`

### Verify Usage Plans and API Keys

1. **List Usage Plans:**
```
aws apigateway get-usage-plans \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'items[?contains(name, `lab6`)].[name,throttle.rateLimit,throttle.burstLimit]' \
  --output table
```
Expected output:
```
---------------------------------------------------------
|                    GetUsagePlans                      |
+----------------------------+------------+-------------+
|  Basic-lab6                |  10.0      |  20         |
|  Standard-lab6             |  50.0      |  100        |
|  Premium-lab6              |  100.0     |  200        |
|  Platinum-lab6             |  500.0     |  1000       |
+----------------------------+------------+-------------+
```

2. **List API Keys:**
```
aws apigateway get-api-keys \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --include-values \
  --query 'items[?contains(name, `lab6`)].[name,id]' \
  --output table
```
Expected: Four API keys (Basic, Standard, Premium, Platinum)

3. **Verify API Key Association:**
```
# Get usage plan ID
USAGE_PLAN_ID=$(aws apigateway get-usage-plans \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'items[?name==`Basic-lab6`].id' \
  --output text)

# Check associated API keys
aws apigateway get-usage-plan-keys \
  --usage-plan-id $USAGE_PLAN_ID \
  --profile serverless-saas-demo \
  --region us-east-1
```

### Verify Client Applications

1. **Access Admin Site:**
   - Open the Admin Site URL in your browser
   - You should see the admin login page
   - Login with the credentials emailed during deployment

2. **Access Landing Site:**
   - Open the Landing Site URL in your browser
   - You should see the tenant registration page

3. **Access Application Site:**
   - Open the App Site URL in your browser
   - You should see the application login page

## Testing

### Test 1: Create a Basic Tier Tenant

1. **Open Landing Site** and click "Sign Up"

2. **Fill in Tenant Details:**
   - Company Name: `TestCompany-Basic`
   - Email: `basic@example.com`
   - Tier: Select "Basic"
   - Complete registration

3. **Verify Tenant Record:**
```
# Get tenant ID from DynamoDB
aws dynamodb scan \
  --table-name ServerlessSaaS-TenantDetails-lab6 \
  --filter-expression "companyName = :name" \
  --expression-attribute-values '{":name":{"S":"TestCompany-Basic"}}' \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Items[0].[tenantId.S,tenantTier.S,apiKey.S]' \
  --output table
```

4. **Verify Usage Plan Assignment:**
```
# Get the API key from the tenant record
API_KEY="<api-key-from-previous-command>"

# Check which usage plan the API key is associated with
aws apigateway get-api-key \
  --api-key $API_KEY \
  --include-value \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query '[name,stageKeys]'
```

### Test 2: Run Throttling Test Script

This is the most important test for Lab 6. It demonstrates how API Gateway throttles requests based on the tenant's usage plan.

**Prerequisites:**
- A Basic tier tenant must be created (from Test 1)
- You need a valid JWT token for the tenant

**Step 1: Obtain JWT Token**

1. Login to the Application site with your Basic tier tenant credentials
2. Open browser developer tools (F12)
3. Go to the "Application" or "Storage" tab
4. Find "Local Storage" or "Session Storage"
5. Look for a key containing "idToken" or "accessToken"
6. Copy the token value (it will be a long string starting with "eyJ...")

**Step 2: Run the Throttling Test**

```
cd workshop/Lab6/tests

# Run the test with your JWT token
./test-basic-tier-throttling.sh "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." --profile serverless-saas-demo
```

**What This Test Does:**
- Makes 1000 concurrent GET requests to the `/products` endpoint
- Each request includes the JWT token for authentication
- API Gateway applies the Basic tier throttling limits (10 req/s, 20 burst)
- Prints the HTTP status code for each request

**Expected Results:**

The test will output approximately:
```
STATUS_CODE : 200
STATUS_CODE : 200
STATUS_CODE : 429
STATUS_CODE : 200
STATUS_CODE : 429
STATUS_CODE : 429
...
All done
```

**Typical Distribution for Basic Tier:**
- **~570 requests succeed** (HTTP 200): Within throttling limits
- **~430 requests throttled** (HTTP 429): Exceeded throttling limits

**Why This Happens:**
- Basic tier allows 10 requests/second steady state
- Burst capacity allows up to 20 requests in a short burst
- The test sends 1000 requests concurrently (much faster than 10/second)
- API Gateway throttles excess requests with 429 status code

**Step 3: Analyze Results**

Count the status codes:
```
# Run test and count results
./test-basic-tier-throttling.sh "your-jwt-token" --profile serverless-saas-demo 2>&1 | \
  grep "STATUS_CODE" | \
  awk '{print $3}' | \
  sort | uniq -c

# Expected output:
#  570 200
#  430 429
```

### Test 3: Compare Throttling Across Tiers

To see how different tiers have different throttling limits, create tenants in each tier and run the same test:

**Create Standard Tier Tenant:**
1. Register a new tenant with tier "Standard"
2. Login and obtain JWT token
3. Run throttling test:
```
./test-basic-tier-throttling.sh "standard-tier-jwt-token" --profile serverless-saas-demo 2>&1 | \
  grep "STATUS_CODE" | awk '{print $3}' | sort | uniq -c
```

**Expected Results by Tier:**

| Tier     | Rate Limit | Burst | Expected 200s | Expected 429s |
|----------|------------|-------|---------------|---------------|
| Basic    | 10/sec     | 20    | ~570          | ~430          |
| Standard | 50/sec     | 100   | ~750          | ~250          |
| Premium  | 100/sec    | 200   | ~850          | ~150          |
| Platinum | 500/sec    | 1000  | ~980          | ~20           |

**Note:** Actual numbers may vary slightly based on network latency and API Gateway processing time.

### Test 4: Verify Throttling Metrics

1. **View API Gateway Metrics:**
```
# Get API Gateway ID
API_ID=$(aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`AdminApiGatewayId`].OutputValue' \
  --output text)

# View throttling metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=$API_ID \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --profile serverless-saas-demo \
  --region us-east-1
```

2. **View Throttled Requests:**
```
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name 4XXError \
  --dimensions Name=ApiName,Value=$API_ID \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --profile serverless-saas-demo \
  --region us-east-1
```

3. **View CloudWatch Logs:**
```
# View API Gateway access logs
aws logs tail /aws/apigateway/serverless-saas-admin-lab6 \
  --follow \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --filter-pattern "429"
```

### Test 5: Verify Tenant Isolation

Ensure that one tenant's throttling doesn't affect another tenant:

1. **Create Two Basic Tier Tenants:**
   - Tenant A: `TestCompany-A`
   - Tenant B: `TestCompany-B`

2. **Run Throttling Test for Tenant A:**
```
./test-basic-tier-throttling.sh "tenant-a-jwt-token" --profile serverless-saas-demo
```

3. **Simultaneously Run Test for Tenant B:**
```
./test-basic-tier-throttling.sh "tenant-b-jwt-token" --profile serverless-saas-demo
```

4. **Verify Independent Throttling:**
   - Each tenant should have ~570 successful requests
   - Each tenant should have ~430 throttled requests
   - One tenant's throttling should not affect the other

## Troubleshooting

### Issue 1: Pooled Stack Not Created

**Symptom:**
```
An error occurred (ValidationError) when calling the DescribeStacks operation: 
Stack with id stack-lab6-pooled does not exist
```

**Solution:**
```
# Check pipeline execution status
aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1

# If pipeline failed, check CodeBuild logs
aws codebuild list-builds-for-project \
  --project-name serverless-saas-pipeline-lab6-build \
  --profile serverless-saas-demo \
  --region us-east-1

# Manually trigger pipeline
aws codepipeline start-pipeline-execution \
  --name serverless-saas-pipeline-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1

# Wait 5-10 minutes for stack creation
```

### Issue 2: Usage Plan Not Found

**Symptom:**
```
An error occurred (NotFoundException) when calling the GetUsagePlan operation: 
Invalid Usage Plan ID specified
```

**Solution:**
```
# Verify shared stack deployed successfully
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1

# Check if usage plans were created
aws apigateway get-usage-plans \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'items[?contains(name, `lab6`)]'

# If missing, redeploy shared stack
cd workshop/Lab6/scripts
./deployment.sh -b --profile serverless-saas-demo
```

### Issue 3: API Key Not Associated with Usage Plan

**Symptom:**
Tenant created but throttling doesn't work

**Solution:**
```
# Get tenant's API key
TENANT_ID="<tenant-id>"
API_KEY=$(aws dynamodb get-item \
  --table-name ServerlessSaaS-TenantDetails-lab6 \
  --key "{\"tenantId\":{\"S\":\"$TENANT_ID\"}}" \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Item.apiKey.S' \
  --output text)

# Check API key details
aws apigateway get-api-key \
  --api-key $API_KEY \
  --include-value \
  --profile serverless-saas-demo \
  --region us-east-1

# If not associated, manually associate with usage plan
USAGE_PLAN_ID=$(aws apigateway get-usage-plans \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'items[?name==`Basic-lab6`].id' \
  --output text)

aws apigateway create-usage-plan-key \
  --usage-plan-id $USAGE_PLAN_ID \
  --key-id $API_KEY \
  --key-type API_KEY \
  --profile serverless-saas-demo \
  --region us-east-1
```

### Issue 4: Throttling Test Returns All 401 Errors

**Symptom:**
```
STATUS_CODE : 401
STATUS_CODE : 401
...
```

**Solution:**
The JWT token is invalid or expired. Obtain a fresh token:

1. Logout and login again to the Application site
2. Open browser developer tools (F12)
3. Go to Application/Storage tab
4. Copy the new idToken or accessToken
5. Run the test again with the new token

### Issue 5: Throttling Test Returns All 403 Errors

**Symptom:**
```
STATUS_CODE : 403
STATUS_CODE : 403
...
```

**Solution:**
The API key is missing or invalid in the request headers:

```
# Verify the test script is using the correct API endpoint
APP_APIGATEWAYURL=$(aws cloudformation describe-stacks \
  --stack-name stack-lab6-pooled \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" \
  --output text)

echo "API Gateway URL: $APP_APIGATEWAYURL"

# Verify API key is configured in API Gateway
aws apigateway get-api-keys \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --include-values \
  --query 'items[?contains(name, `lab6`)]'
```

### Issue 6: Pipeline Fails with Python Version Error

**Symptom:**
```
Error: Python 3.9 not found
```

**Solution:**
The buildspec.yml has been updated to use Python 3.11 (compatible with Amazon Linux 2023). If you see this error:

1. Check the buildspec.yml in the CodeCommit repository
2. Verify it specifies `python: 3.11` in the runtime-versions section
3. If not, update the buildspec.yml and push to CodeCommit:
```
cd workshop/Lab6/server/TenantPipeline
# Edit buildspec.yml to use python: 3.11
git add buildspec.yml
git commit -m "Update Python version to 3.11"
git push cc main
```

### Issue 7: CloudFront Cache Not Invalidated

**Symptom:**
Client applications show old content after deployment

**Solution:**
```
# Manually invalidate CloudFront distributions
# Get distribution IDs
aws cloudfront list-distributions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'DistributionList.Items[*].[Id,Origins.Items[0].DomainName]' \
  --output table

# Invalidate each distribution
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*" \
  --profile serverless-saas-demo \
  --region us-east-1
```

## Cleanup

To remove all Lab 6 resources and avoid ongoing charges:

```
cd workshop/Lab6/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab6 --profile serverless-saas-demo
```

**What Gets Deleted:**
1. **Tenant Stacks**: All Platinum tier tenant-specific CloudFormation stacks
2. **Pooled Stack**: stack-lab6-pooled (tenant resources)
3. **Pipeline Stack**: CodePipeline, CodeBuild, and associated resources
4. **Shared Stack**: Shared services, Lambda functions, DynamoDB tables, Cognito pools, usage plans, API keys
5. **CodeCommit Repository**: aws-serverless-saas-workshop repository
6. **S3 Buckets**: Pipeline artifacts, client application hosting buckets
7. **CloudWatch Logs**: All log groups with 60-day retention
8. **CloudFront Distributions**: All three distributions (Admin, Landing, App)

**Cleanup Time:** Approximately 15-20 minutes

**Manual Cleanup (if needed):**

If automated cleanup fails, manually delete resources:

```
# Delete tenant stacks
aws cloudformation delete-stack --stack-name stack-<tenant-id> --profile serverless-saas-demo --region us-east-1

# Delete pooled stack
aws cloudformation delete-stack --stack-name stack-lab6-pooled --profile serverless-saas-demo --region us-east-1

# Delete pipeline stack
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab6 --profile serverless-saas-demo --region us-east-1

# Delete shared stack
aws cloudformation delete-stack --stack-name serverless-saas-shared-lab6 --profile serverless-saas-demo --region us-east-1

# Delete CodeCommit repository
aws codecommit delete-repository --repository-name aws-serverless-saas-workshop --profile serverless-saas-demo --region us-east-1

# Empty and delete S3 buckets
aws s3 rm s3://<bucket-name> --recursive --profile serverless-saas-demo --region us-east-1
aws s3 rb s3://<bucket-name> --profile serverless-saas-demo --region us-east-1
```

## Key Concepts

### API Gateway Usage Plans

**What Are Usage Plans?**
Usage plans allow you to configure throttling and quota limits for API clients. Each usage plan defines:
- **Rate Limit**: Steady-state request rate (requests per second)
- **Burst Limit**: Maximum concurrent requests allowed
- **Quota**: Total requests allowed per day/week/month (optional)

**How They Work:**
1. Create usage plan with throttling limits
2. Generate API key
3. Associate API key with usage plan
4. Client includes API key in request headers
5. API Gateway enforces limits based on usage plan

**Benefits:**
- **Fair Resource Allocation**: Prevents one tenant from consuming all resources
- **Tier-Based Pricing**: Higher tiers get higher limits
- **DDoS Protection**: Limits impact of malicious traffic
- **Cost Control**: Prevents unexpected API costs

### Rate Limiting vs Burst Capacity

**Rate Limit (Steady State):**
- Sustained request rate over time
- Example: 10 requests/second means 600 requests/minute
- Enforced using token bucket algorithm
- Tokens refill at the rate limit

**Burst Capacity:**
- Maximum requests allowed in a short burst
- Example: 20 burst allows 20 concurrent requests
- Uses accumulated tokens from idle periods
- Prevents legitimate traffic spikes from being throttled

**Token Bucket Algorithm:**
```
1. Bucket starts with burst capacity tokens
2. Each request consumes one token
3. Tokens refill at rate limit per second
4. If bucket empty, request is throttled (429)
5. Bucket never exceeds burst capacity
```

**Example for Basic Tier (10/sec, 20 burst):**
- Bucket starts with 20 tokens
- Client sends 20 requests instantly → All succeed (bucket empty)
- After 1 second → Bucket has 10 tokens
- Client sends 15 requests → 10 succeed, 5 throttled
- After 2 seconds → Bucket has 10 tokens again

### API Keys for Tenant Identification

**Why API Keys?**
- **Tenant Identification**: Each tenant has unique API key
- **Usage Plan Association**: API key links tenant to usage plan
- **Throttling Enforcement**: API Gateway uses API key to apply limits
- **Metrics and Monitoring**: Track usage per tenant

**API Key Management:**
- Generated during tenant registration
- Stored in TenantDetails DynamoDB table
- Included in JWT token claims
- Validated by Lambda authorizer
- Injected into request headers by client

**Security Considerations:**
- API keys are not secrets (they're in client code)
- Always use with JWT authentication
- API keys identify tenant, JWT authenticates user
- Never rely on API keys alone for security

### Throttling in Multi-Tenant Architecture

**Pooled Model Throttling:**
- All Basic/Standard/Premium tenants share API Gateway
- Each tenant has own API key and usage plan
- Throttling applied per tenant, not globally
- One tenant's throttling doesn't affect others

**Siloed Model Throttling:**
- Platinum tenants have dedicated API Gateway
- Dedicated usage plan with higher limits
- Complete isolation from other tenants
- No noisy neighbor issues

**Throttling Strategy:**
```
Basic Tier:    Low limits, cost-effective
Standard Tier: Medium limits, balanced
Premium Tier:  High limits, premium pricing
Platinum Tier: Very high limits, dedicated resources
```

### Fair Resource Allocation

**Problem:**
Without throttling, one tenant could:
- Consume all API Gateway capacity
- Cause high latency for other tenants
- Drive up costs for the SaaS provider
- Create denial of service for other tenants

**Solution:**
Tier-based throttling ensures:
- Each tenant gets guaranteed capacity
- Higher-paying tenants get more capacity
- No single tenant can monopolize resources
- Predictable performance for all tenants

**Implementation:**
1. Define throttling limits per tier
2. Create usage plans with those limits
3. Associate API keys with usage plans
4. Enforce limits at API Gateway level
5. Monitor and adjust limits based on usage

## Verification

After deploying Lab 6, verify that throttling is working correctly:

### 1. Verify CloudFormation Stacks

Check that all stacks deployed successfully:

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab6 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'

aws cloudformation describe-stacks \
  --stack-name stack-lab6-pooled \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

Expected output: `"CREATE_COMPLETE"` or `"UPDATE_COMPLETE"`

### 2. Verify Usage Plans and API Keys

Check that usage plans were created with correct throttling limits:

```
# List usage plans
aws apigateway get-usage-plans \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'items[?contains(name, `lab6`)]'

# List API keys
aws apigateway get-api-keys \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --include-values \
  --query 'items[?contains(name, `lab6`)]'
```

### 3. Test Throttling Behavior

Run the throttling test script to verify limits are enforced:

```
cd workshop/Lab6/tests
./test-throttling.sh
```

Expected output:
- Basic tier: Mix of 200 and 429 status codes (throttled)
- Standard tier: Fewer 429 codes than Basic
- Premium tier: Minimal or no 429 codes
- Platinum tier: No throttling (dedicated API Gateway)

### 4. Verify Tenant Registration

Test that new tenants can register and receive API keys:

1. Navigate to the Landing page URL (from deployment outputs)
2. Register a new tenant with different tiers
3. Verify tenant appears in DynamoDB TenantDetails table
4. Confirm API key is generated and associated with correct usage plan

### 5. Verify Application Functionality

Test the Application client with throttling:

1. Login to the Application site
2. Perform multiple rapid operations (create/update products)
3. Monitor for 429 errors in browser console
4. Verify operations succeed within throttling limits

## Next Steps

After completing Lab 6, you can:

1. **Proceed to Lab 7**: Learn about cost attribution in a pooled model
   - Track per-tenant costs in shared infrastructure
   - Implement cost allocation tags
   - Generate tenant-specific billing reports

2. **Experiment with Throttling Limits**:
   - Modify usage plan limits in shared-template.yaml
   - Redeploy and test with different limits
   - Observe impact on throttling behavior

3. **Implement Quota Limits**:
   - Add daily/weekly/monthly quotas to usage plans
   - Track quota usage per tenant
   - Send notifications when quotas are exceeded

4. **Monitor API Usage**:
   - Set up CloudWatch dashboards for API metrics
   - Create alarms for high throttling rates
   - Analyze usage patterns per tenant tier

5. **Optimize Throttling Strategy**:
   - Analyze actual tenant usage patterns
   - Adjust limits based on real-world data
   - Implement dynamic throttling based on load

## Additional Resources

- [API Gateway Usage Plans Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html)
- [API Gateway Throttling Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html)
- [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)
- [Multi-Tenant SaaS on AWS](https://aws.amazon.com/solutions/implementations/saas-identity-and-isolation-with-amazon-cognito/)
- [SaaS Tenant Isolation Strategies](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-isolation.html)
- [Workshop Guide](https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US/lab6)

## Summary

In Lab 6, you learned how to implement tenant throttling and API quota management for multi-tenant SaaS applications. You deployed API Gateway usage plans with tier-based throttling limits, tested throttling behavior with concurrent requests, and verified fair resource allocation across tenants. This approach ensures that each tenant gets guaranteed API capacity based on their tier, prevents resource monopolization, and enables tier-based pricing models.

**Key Takeaways:**
- API Gateway usage plans enable tier-based throttling and quotas
- Rate limiting and burst capacity work together to handle traffic patterns
- API keys identify tenants and associate them with usage plans
- Throttling ensures fair resource allocation in multi-tenant environments
- Testing throttling behavior validates that limits are enforced correctly
- Tier-based throttling supports differentiated pricing models
