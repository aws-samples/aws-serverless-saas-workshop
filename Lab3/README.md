# Lab 3: Adding Multi-Tenancy to Microservices

## Quick Reference

**Deployment Time:** ~13-15 minutes | **Cleanup Time:** ~15-20 minutes

### Quick Start
```
# Deploy
cd workshop/Lab3/scripts
./deployment.sh -s -c --email your-email@example.com --tenant-email your-email@example.com --profile serverless-saas-demo

# Get URLs
./geturl.sh --profile serverless-saas-demo

# Cleanup
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile serverless-saas-demo
```

### What You'll Deploy

**Shared Stack (serverless-saas-shared-lab3):**
- **16 Lambda Functions** - Tenant/user management (Python 3.14)
- **2 DynamoDB Tables** - TenantDetails-lab3, TenantUserMapping-lab3
- **2 Cognito User Pools** - PooledTenant, OperationUsers
- **1 Admin API Gateway** - Tenant/user management
- **3 CloudFront Distributions** - Admin, Landing, Application UIs
- **3 S3 Buckets** - Static website hosting

**Tenant Stack (serverless-saas-tenant-lab3):**
- **10 Lambda Functions** - Product/order operations (Python 3.14)
- **2 DynamoDB Tables** - Product-lab3, Order-lab3 (pooled)
- **1 Tenant API Gateway** - Product/order operations
- **1 Business Services Authorizer** - Tenant context propagation

### Key Features
- **Pooled Multi-Tenant Architecture** - Single set of resources shared across tenants
- **Two API Gateways** - Admin API (tenant/user) + Tenant API (products/orders)
- **Tenant Isolation** - Data partitioned by tenant ID in pooled DynamoDB tables
- **Sample Tenants** - Automatically creates 3 tenants for testing
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

---

## Overview

This lab introduces multi-tenancy capabilities to the serverless web application. You'll add authentication, authorization, tenant-aware logging and metrics, and data partitioning to support multiple tenants in a pooled architecture.

**Key Features:**
- User authentication with Amazon Cognito
- Lambda Authorizer for API Gateway authentication and authorization
- Multi-tenant observability with tenant-aware logging and metrics
- Data partitioning in DynamoDB using tenant context
- Lambda Layers for centralized logging and metrics collection

**Important Note:** Lab 3 uses a **pooled multi-tenant architecture** with two API Gateways:
- **Admin API Gateway** (shared stack) - handles tenant management and user management
- **Tenant API Gateway** (tenant stack) - handles business logic (products, orders)

The Application client uses **TWO different API URLs**:
- `regApiGatewayUrl`: Admin API Gateway (for registration/authentication)
- `apiGatewayUrl`: Tenant API Gateway (for product/order operations)

## Prerequisites

Before starting this lab, ensure you have:

1. **AWS Account**: With appropriate permissions to create Lambda, DynamoDB, API Gateway, Cognito, CloudFront, and S3 resources
2. **AWS CLI configured** with appropriate credentials and the `serverless-saas-demo` profile
3. **AWS SAM CLI installed** (version 1.70.0 or later)
4. **Docker installed and running** (required for SAM builds)
5. **Node.js and npm installed** (for Angular applications)
6. **Python 3.14 or later** installed

**Lab Independence**: This lab is completely self-contained and does NOT require Lab 2 or any other lab to be deployed first. Lab 3 creates its own complete infrastructure including Cognito user pools, tenant management, API Gateways, and DynamoDB tables. The deployment script automatically creates sample tenants for testing.

**Verify Prerequisites:**
```
aws --version
sam --version
docker --version
node --version
python3 --version
```

## Architecture

### High-Level Architecture

Lab 3 introduces multi-tenancy support to the application microservices:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Web Applications                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Admin      │  │   Landing    │  │  Application │         │
│  │   Console    │  │   Sign-up    │  │   (SaaS)     │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Amazon CloudFront                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Amazon API Gateway (Dual)                     │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │  Admin API Gateway   │  │  Tenant API Gateway  │            │
│  │  (Shared Services)   │  │  (Business Logic)    │            │
│  └──────────────────────┘  └──────────────────────┘            │
│              │                        │                          │
│              ▼                        ▼                          │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │ Shared Service       │  │ Tenant               │            │
│  │ Authorizer           │  │ Authorizer           │            │
│  └──────────────────────┘  └──────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Lambda Functions                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Lambda Layers                          │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │  │
│  │  │   Logger   │  │   Metrics  │  │    Auth    │         │  │
│  │  │   Manager  │  │   Manager  │  │   Manager  │         │  │
│  │  └────────────┘  └────────────┘  └────────────┘         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │  Shared Services     │  │  Application         │            │
│  │  - Registration      │  │  Services            │            │
│  │  - Tenant Mgmt       │  │  - Product Service   │            │
│  │  - User Mgmt         │  │  - Order Service     │            │
│  └──────────────────────┘  └──────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Data Layer                                  │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │  Amazon DynamoDB     │  │  Amazon Cognito      │            │
│  │  - Product-pooled    │  │  - User Pools        │            │
│  │  - Order-pooled      │  │  - User Groups       │            │
│  │  - TenantDetails     │  │                      │            │
│  └──────────────────────┘  └──────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Observability Layer                            │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │  Amazon CloudWatch   │  │  AWS X-Ray           │            │
│  │  - Logs (tenant ctx) │  │  - Traces (tenant)   │            │
│  │  - Metrics (EMF)     │  │                      │            │
│  └──────────────────────┘  └──────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

**Authentication & Authorization:**
- Amazon Cognito for user authentication with JWT tokens
- Lambda Authorizers for API Gateway (Shared Service and Tenant)
- Custom claims in JWT tokens (tenantId, userRole)
- Role-based access control (System Admin, Tenant Admin, Tenant User)

**Lambda Layers:**
- **Logger Manager**: Centralized logging with tenant context
- **Metrics Manager**: CloudWatch EMF metrics with tenant dimensions
- **Auth Manager**: Role-based authorization helpers

**Data Partitioning:**
- DynamoDB tables with composite keys: `shardId` (partition key) + `productId/orderId` (sort key)
- ShardId format: `{tenantId}-{randomSuffix}` for tenant isolation and hot key prevention

**Multi-Tenant Observability:**
- Tenant-aware CloudWatch logs with tenant_id in log messages
- CloudWatch EMF metrics with tenant_id dimension
- AWS X-Ray tracing with tenant annotations

## Deployment Steps

### Step 1: Navigate to Lab3 Directory

```
cd workshop/Lab3
```

### Step 2: Initialize the Lab (Deploy Infrastructure)

Deploy both shared and tenant stacks:

```
cd scripts
./deployment.sh -s -c --email <your-email> --tenant-email <tenant-email> --profile serverless-saas-demo
```

**Parameters:**
- `-s`: Deploy server-side infrastructure (both shared and tenant stacks)
- `-c`: Deploy client-side applications (Admin, Landing, Application)
- `--email`: Email for admin user notifications
- `--tenant-email`: Email for tenant admin user
- `--profile`: AWS CLI profile to use (required)

**Expected Output:**
```
Deploying shared services stack...
Deploying tenant stack...
Building client applications...
Deployment completed successfully!

Admin Site URL: https://<admin-cloudfront-id>.cloudfront.net
Landing Site URL: https://<landing-cloudfront-id>.cloudfront.net
App Site URL: https://<app-cloudfront-id>.cloudfront.net
Admin API Gateway URL: https://<admin-api-id>.execute-api.us-east-1.amazonaws.com/prod
Tenant API Gateway URL: https://<tenant-api-id>.execute-api.us-east-1.amazonaws.com/prod
```

**Deployment Time:** Approximately 15-20 minutes

**Note:** The deployment creates:
- Two CloudFormation stacks: `serverless-saas-lab3-shared` and `serverless-saas-lab3-tenant`
- Three CloudFront distributions for web applications
- Two API Gateways (Admin and Tenant)
- Lambda functions with layers for shared services and application services
- DynamoDB tables with tenant partitioning
- CloudWatch log groups with 60-day retention

### Step 3: Retrieve URLs (If Needed)

If you close the terminal or need to retrieve the URLs later:

```
cd scripts
./geturl.sh --stack-name serverless-saas-lab3 --profile serverless-saas-demo
```

## Verification

### 1. Verify CloudFormation Stacks

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab3-shared \
  --profile serverless-saas-demo \
  --query 'Stacks[0].StackStatus'

aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab3-tenant \
  --profile serverless-saas-demo \
  --query 'Stacks[0].StackStatus'
```

**Expected Output:** `"CREATE_COMPLETE"` for both stacks

### 2. Verify API Gateways

```
aws apigateway get-rest-apis \
  --profile serverless-saas-demo \
  --query 'items[?contains(name, `lab3`)].{Name:name, ID:id}'
```

**Expected Output:** Two API Gateways (Admin and Tenant)

### 3. Verify DynamoDB Tables

```
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --query 'TableNames[?contains(@, `pooled`)]'
```

**Expected Output:**
```json
[
    "Product-pooled",
    "Order-pooled"
]
```

### 4. Verify Lambda Functions

```
aws lambda list-functions \
  --profile serverless-saas-demo \
  --query 'Functions[?contains(FunctionName, `lab3`)].FunctionName'
```

**Expected Output:** Multiple Lambda functions including:
- CreateProductFunction
- GetProductsFunction
- CreateOrderFunction
- TenantAuthorizerFunction
- SharedServiceAuthorizerFunction

### 5. Verify CloudWatch Log Groups

```
aws logs describe-log-groups \
  --profile serverless-saas-demo \
  --log-group-name-prefix "/aws/lambda/stack-pooled" \
  --query 'logGroups[].{Name:logGroupName, Retention:retentionInDays}'
```

**Expected Output:** Log groups with 60-day retention

### 6. Test Application Access

**Login to SaaS Application:**

1. Open the App Site URL in your browser
2. Click "Login" - you'll be redirected to an unauthorized page (expected)
3. Click "Login" again to access the Cognito Hosted UI
4. Enter credentials for tenant1 admin user (check your email for temporary password)
5. Reset password if prompted (first-time login)
6. After successful login, you should see the application dashboard

**Create a Product:**

1. Click "Products" in the left navigation menu
2. Click "Create Product" button
3. Fill in the form:
   - SKU: `PROD-001`
   - Name: `Test Product`
   - Price: `29.99`
   - Category: `Electronics`
4. Click "Submit"
5. Verify the product appears in the product list

**Create an Order:**

1. Click "Orders" in the left navigation menu
2. Click "Create Order" button
3. Select a product and set quantity
4. Click "Submit"
5. Verify the order appears in the order list

### 7. Verify Multi-Tenant Data Partitioning

**Check DynamoDB Data:**

1. Go to AWS Console → DynamoDB → Tables
2. Select `Product-pooled` table
3. Click "Explore table items"
4. Observe the `shardId` format: `{tenantId}-{randomSuffix}`
5. Verify products are partitioned by tenant

**Example Item:**
```json
{
  "shardId": "tenant1-abc123-5",
  "productId": "uuid-here",
  "sku": "PROD-001",
  "name": "Test Product",
  "price": "29.99",
  "category": "Electronics"
}
```

### 8. Verify Multi-Tenant Observability

**Tenant-Aware Logs:**

1. Go to AWS Console → CloudWatch → Log groups
2. Search for `/aws/lambda/stack-pooled-CreateProductFunction`
3. Open the latest log stream
4. Verify log messages include `tenant_id` field

**Example Log Entry:**
```json
{
  "level": "INFO",
  "location": "create_product:45",
  "message": "Creating product",
  "timestamp": "2026-01-25 12:34:56,789",
  "service": "product-service",
  "tenant_id": "tenant1"
}
```

**Tenant-Aware Metrics:**

1. Go to AWS Console → CloudWatch → Metrics
2. Click "All metrics"
3. Under "Custom namespaces", click "ServerlessSaaS"
4. Click "service, tenant_id"
5. Select "ProductCreated" metric
6. Verify metrics are grouped by tenant_id

**X-Ray Tracing:**

1. Go to AWS Console → X-Ray → Traces
2. Adjust time range if needed (e.g., "Last 3 hours")
3. In "Group by" dropdown, select "Annotation.TenantId"
4. Click on a specific TenantId to view traces for that tenant
5. Click on a trace ID to see the end-to-end request flow

### 9. Test Multi-Tenancy with Multiple Tenants

**Login as Different Tenant:**

1. Logout from the current session
2. Login with tenant2 admin credentials
3. Create products and orders for tenant2
4. Verify tenant2 cannot see tenant1's data
5. Check DynamoDB to confirm data is partitioned by tenantId

## Testing Multi-Tenancy

### Test Scenario 1: Tenant Isolation

**Objective:** Verify that tenants can only access their own data

**Steps:**
1. Login as tenant1 admin
2. Create 2-3 products for tenant1
3. Note the product IDs
4. Logout and login as tenant2 admin
5. Verify tenant2 cannot see tenant1's products
6. Create products for tenant2
7. Verify tenant2 only sees their own products

**Expected Result:** Each tenant sees only their own data

### Test Scenario 2: Role-Based Access Control

**Objective:** Verify different user roles have appropriate permissions

**Steps:**
1. Login as System Admin (admin-user)
2. Access Admin Console
3. Verify you can view all tenants
4. Login as Tenant Admin (tenant1 admin)
5. Verify you can manage users in your tenant
6. Verify you cannot access other tenants' data

**Expected Result:** Permissions are enforced based on user role

### Test Scenario 3: Tenant-Aware Logging

**Objective:** Verify logs include tenant context

**Steps:**
1. Login as tenant1 and create a product
2. Login as tenant2 and create a product
3. Go to CloudWatch Logs
4. Search for CreateProductFunction log group
5. Verify logs show different tenant_id values

**Expected Result:** Logs include tenant_id for each request

### Test Scenario 4: Tenant-Aware Metrics

**Objective:** Verify metrics are collected per tenant

**Steps:**
1. Create 5 products as tenant1
2. Create 3 products as tenant2
3. Go to CloudWatch Metrics → ServerlessSaaS namespace
4. View ProductCreated metric grouped by tenant_id
5. Verify counts match: tenant1=5, tenant2=3

**Expected Result:** Metrics are tracked separately per tenant

## Troubleshooting

### Issue: Deployment Fails with "Stack already exists"

**Cause:** Previous deployment was not cleaned up properly

**Solution:**
```
cd scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile serverless-saas-demo
# Wait for cleanup to complete, then redeploy
./deployment.sh -s -c --email <your-email> --tenant-email <tenant-email> --profile serverless-saas-demo
```

### Issue: "Unauthorized" Error When Accessing Application

**Cause:** User not authenticated or JWT token expired

**Solution:**
1. Click "Login" button to access Cognito Hosted UI
2. Enter valid credentials for a tenant admin user
3. If first-time login, reset the temporary password
4. Ensure you're using the correct tenant credentials

### Issue: Cannot See Products/Orders After Login

**Cause:** API Gateway authorization issue or incorrect API URL

**Solution:**
1. Check browser console for API errors
2. Verify the application is using the correct Tenant API Gateway URL
3. Check CloudWatch logs for authorization errors:
   ```
   aws logs tail /aws/lambda/stack-pooled-TenantAuthorizerFunction \
     --follow \
     --profile serverless-saas-demo
   ```

### Issue: Products from Other Tenants Are Visible

**Cause:** Data partitioning not working correctly

**Solution:**
1. Check DynamoDB items to verify shardId includes tenantId
2. Verify Lambda Authorizer is passing tenant context
3. Check CloudWatch logs for the GetProductsFunction:
   ```
   aws logs tail /aws/lambda/stack-pooled-GetProductsFunction \
     --follow \
     --profile serverless-saas-demo
   ```

### Issue: Metrics Not Showing in CloudWatch

**Cause:** EMF format not being logged correctly

**Solution:**
1. Check Lambda function logs for EMF JSON output
2. Verify metrics_manager.py is being called
3. Wait 5-10 minutes for metrics to appear in CloudWatch
4. Check the ServerlessSaaS custom namespace exists

### Issue: X-Ray Traces Not Showing Tenant Annotations

**Cause:** X-Ray tracing not enabled or annotations not added

**Solution:**
1. Verify X-Ray tracing is enabled on Lambda functions:
   ```
   aws lambda get-function-configuration \
     --function-name stack-pooled-CreateProductFunction \
     --profile serverless-saas-demo \
     --query 'TracingConfig'
   ```
2. Check that `tracer.put_annotation("TenantId", tenant_id)` is in the code
3. Wait a few minutes for traces to propagate

### Issue: Lambda Function Timeout

**Cause:** Cold start or insufficient resources

**Solution:**
1. Check Lambda function timeout settings (should be 30 seconds)
2. Check Lambda function memory (should be 512 MB minimum)
3. Review CloudWatch logs for timeout errors
4. Consider increasing timeout or memory if needed

### Issue: DynamoDB Hot Partition

**Cause:** All tenant data going to same partition

**Solution:**
1. Verify shardId includes random suffix: `{tenantId}-{randomSuffix}`
2. Check the suffix_start and suffix_end range in product_service_dal.py
3. Ensure random.randrange() is generating different suffixes

## Cleanup

To remove all resources created in this lab:

```
cd workshop/Lab3/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab3 --profile serverless-saas-demo
```

**What Gets Deleted:**
- Both CloudFormation stacks (shared and tenant)
- All Lambda functions and layers
- API Gateways (Admin and Tenant)
- DynamoDB tables (Product-pooled, Order-pooled)
- CloudWatch log groups
- CloudFront distributions
- S3 buckets (application assets and SAM artifacts)
- Cognito user pools and users

**Cleanup Time:** Approximately 15-20 minutes

**Note:** The cleanup script follows a secure deletion order to prevent CloudFront origin hijacking:
1. Deletes CloudFormation stacks (including CloudFront distributions)
2. Waits for stack deletion to complete
3. Deletes S3 buckets (now safe after CloudFront is gone)
4. Removes CloudWatch log groups
5. Cleans up Cognito resources

**Verification:**
```
# Verify stacks are deleted
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab3-shared \
  --profile serverless-saas-demo 2>&1 | grep "does not exist"

# Verify S3 buckets are deleted
aws s3 ls --profile serverless-saas-demo | grep lab3

# Verify log groups are deleted
aws logs describe-log-groups \
  --profile serverless-saas-demo \
  --log-group-name-prefix "/aws/lambda/stack-pooled"
```

## Key Concepts

### Lambda Authorizers

Lambda Authorizers provide centralized authentication and authorization for API Gateway:

**Tenant Authorizer:**
- Validates JWT tokens from Cognito
- Extracts tenant context (tenantId, userRole)
- Returns IAM policy allowing/denying API access
- Passes tenant context to Lambda functions
- Caches authorization decisions for 60 seconds

**Shared Service Authorizer:**
- Enforces role-based access control
- System Admins: Full access to all tenants
- Tenant Admins: Access to their tenant only
- Tenant Users: Limited access to their own data

### Lambda Layers

Lambda Layers provide reusable code across all Lambda functions:

**Logger Manager:**
- Adds tenant_id to all log messages
- Uses AWS Lambda Powertools for structured logging
- Enables tenant-specific log filtering

**Metrics Manager:**
- Records metrics using CloudWatch EMF format
- Adds tenant_id as a dimension
- Enables tenant-specific metric aggregation

**Auth Manager:**
- Provides role-checking helper functions
- Simplifies authorization logic in Lambda functions

### Data Partitioning Strategy

**Composite Key Design:**
- Partition Key: `shardId` = `{tenantId}-{randomSuffix}`
- Sort Key: `productId` or `orderId`

**Benefits:**
- Tenant isolation at the data layer
- Prevents hot partition issues
- Enables efficient tenant-specific queries
- Foundation for tenant isolation policies (Lab 4)

### Multi-Tenant Observability

**CloudWatch Logs:**
- Structured JSON logs with tenant_id field
- Enables filtering by tenant: `{ $.tenant_id = "tenant1" }`
- Supports CloudWatch Insights queries

**CloudWatch Metrics:**
- EMF format logs metrics in log streams
- Custom namespace: ServerlessSaaS
- Dimensions: service, tenant_id
- No PutMetrics API calls (cost-effective)

**X-Ray Tracing:**
- End-to-end request tracing
- Tenant annotations for filtering
- Service map visualization
- Performance analysis per tenant

## Next Steps

After completing Lab 3, proceed to:

**Lab 4: Isolating Tenant Data in a Pooled Model**
- Implement tenant isolation using IAM policies
- Prevent cross-tenant data access
- Add fine-grained access control with STS
- Test tenant isolation mechanisms

## Additional Resources

- [AWS Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [AWS Lambda Layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html)
- [AWS Lambda Powertools Python](https://docs.powertools.aws.dev/lambda/python/latest/)
- [CloudWatch Embedded Metric Format](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [AWS X-Ray](https://docs.aws.amazon.com/xray/latest/devguide/aws-xray.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [SaaS Tenant Isolation Strategies](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-isolation.html)
