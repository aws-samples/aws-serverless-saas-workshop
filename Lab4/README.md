# Lab 4: Isolating Tenant Data in a Pooled Model

## Quick Reference

**Deployment Time:** ~18-20 minutes | **Cleanup Time:** ~15-20 minutes

### Quick Start
```
# Deploy
cd workshop/Lab4/scripts
./deployment.sh -s -c --email your-email@example.com --tenant-email your-email@example.com --profile serverless-saas-demo

# Get URLs
./geturl.sh --profile serverless-saas-demo

# Cleanup
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab4 --profile serverless-saas-demo
```

### What You'll Deploy

**Shared Stack (serverless-saas-shared-lab4):**
- **16 Lambda Functions** - Tenant/user management (Python 3.14)
- **2 DynamoDB Tables** - TenantDetails-lab4, TenantUserMapping-lab4
- **2 Cognito User Pools** - PooledTenant, OperationUsers
- **1 Admin API Gateway** - Tenant/user management
- **3 CloudFront Distributions** - Admin, Landing, Application UIs
- **3 S3 Buckets** - Static website hosting

**Tenant Stack (serverless-saas-tenant-lab4):**
- **11 Lambda Functions** - Including Business Services Authorizer (Python 3.14)
- **2 DynamoDB Tables** - Product-lab4, Order-lab4 (pooled with tenant isolation)
- **1 Tenant API Gateway** - Product/order operations
- **3 IAM Roles** - Tenant data isolation
  - AuthorizerAccessRole: Generates tenant-scoped STS credentials
  - ProductFunctionRole: Scoped access to Product table
  - OrderFunctionRole: Scoped access to Order table

### Key Features
- **Tenant Data Isolation** - IAM policies enforce row-level security in DynamoDB
- **STS Credentials** - Business Services Authorizer generates temporary credentials scoped to tenant ID
- **Pooled Architecture** - Single set of resources with fine-grained access control
- **Cross-Tenant Protection** - IAM policies prevent access to other tenants' data
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

---

## Overview

Lab 4 demonstrates how to implement tenant data isolation in a pooled multi-tenant architecture using IAM policies and AWS Security Token Service (STS). Building upon Lab 3's multi-tenant foundation, this lab adds fine-grained access control mechanisms to ensure that tenants can only access their own data, even though all tenant data resides in shared DynamoDB tables.

### What You'll Learn

- Implement IAM policy-based tenant isolation in DynamoDB
- Generate tenant-scoped STS credentials using a Lambda authorizer
- Enforce row-level security in pooled database tables
- Test and verify cross-tenant data access prevention
- Understand the security implications of pooled multi-tenancy

### Key Concepts

**Pooled Multi-Tenancy**: Multiple tenants share the same infrastructure and database tables, with logical separation enforced through access controls rather than physical separation.

**IAM Policy-Based Isolation**: AWS IAM policies restrict DynamoDB access based on tenant ID, ensuring each tenant can only read/write their own data.

**STS Credentials**: The Business Services Authorizer generates temporary AWS credentials scoped to a specific tenant, which are then used by Lambda functions to access DynamoDB.

**Row-Level Security**: DynamoDB access is restricted at the row level using IAM condition keys that match the tenant ID in the partition key.

## Prerequisites

Before starting this lab, ensure you have:

- **AWS Account**: With appropriate permissions to create Lambda, DynamoDB, API Gateway, Cognito, CloudFront, S3, and IAM resources
- **AWS CLI**: Installed and configured with profile `serverless-saas-demo`
  ```
  aws --version  # Should be 2.x or higher
  aws configure list --profile serverless-saas-demo
  ```
- **SAM CLI**: Installed for deploying serverless applications
  ```
  sam --version  # Should be 1.x or higher
  ```
- **Python 3.14**: Installed for Lambda runtime compatibility
  ```
  python3 --version  # Should be 3.14.x
  ```
- **Docker**: Running for SAM local testing (optional)
- **Completed Labs**: Understanding of Lab 3 concepts is helpful but not required (Lab 4 is self-contained)


## Architecture

Lab 4 deploys a two-stack architecture with enhanced security controls:

### Shared Stack (serverless-saas-shared-lab4)

**Purpose**: Manages tenant lifecycle, user management, and administrative functions

**Components**:
- **16 Lambda Functions**: Tenant registration, user management, authentication (Python 3.14)
- **DynamoDB Tables**: 
  - `TenantDetails-lab4`: Stores tenant metadata and configuration
  - `TenantUserMapping-lab4`: Maps users to tenants
- **Cognito User Pools**:
  - `PooledTenant`: Shared user pool for all pooled tenants
  - `OperationUsers`: User pool for system administrators
- **Admin API Gateway**: RESTful API for tenant and user management operations
- **CloudFront Distributions**: 3 distributions for Admin, Landing, and Application sites
- **S3 Buckets**: Static website hosting for all three web applications

### Tenant Stack (serverless-saas-tenant-lab4)

**Purpose**: Provides business services with tenant-scoped access control

**Components**:
- **11 Lambda Functions**: Product and order management with tenant isolation (Python 3.14)
- **Business Services Authorizer**: Custom Lambda authorizer that:
  - Validates JWT tokens from Cognito
  - Extracts tenant ID from the token
  - Generates STS credentials scoped to the tenant ID
  - Returns IAM policy allowing access only to tenant's data
- **DynamoDB Tables** (Pooled with Tenant Isolation):
  - `Product-lab4`: Shared product table with partition key `tenantId-productId`
  - `Order-lab4`: Shared order table with partition key `tenantId-orderId`
- **IAM Roles** (Tenant-Scoped):
  - `AuthorizerAccessRole`: Allows authorizer to assume roles and generate STS credentials
  - `ProductFunctionRole`: Scoped access to Product table for specific tenant
  - `OrderFunctionRole`: Scoped access to Order table for specific tenant
- **Tenant API Gateway**: RESTful API for product and order operations with custom authorizer

### Tenant Isolation Flow

```
1. User authenticates → Cognito returns JWT with tenant ID
2. User calls API → API Gateway invokes Business Services Authorizer
3. Authorizer validates JWT → Extracts tenant ID
4. Authorizer calls STS AssumeRole → Generates tenant-scoped credentials
5. Authorizer returns IAM policy → Allows access only to tenant's data
6. Lambda function executes → Uses scoped credentials to access DynamoDB
7. DynamoDB enforces IAM policy → Restricts access to rows matching tenant ID
```

### IAM Policy Example

The authorizer generates policies like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/Product-lab4",
      "Condition": {
        "ForAllValues:StringEquals": {
          "dynamodb:LeadingKeys": ["tenant-123-*"]
        }
      }
    }
  ]
}
```

This policy ensures the tenant can only access DynamoDB items where the partition key starts with their tenant ID.


## Deployment Steps

### Step 1: Navigate to Lab 4 Directory

```
cd workshop/Lab4
```

### Step 2: Review the Architecture

Before deploying, familiarize yourself with the key files:

- `server/shared-template.yaml`: Defines shared services (tenant management, user management)
- `server/tenant-template.yaml`: Defines tenant services with IAM-based isolation
- `server/TenantManagementService/`: Lambda functions for tenant lifecycle
- `server/ProductService/`: Lambda functions for product operations with tenant isolation
- `server/OrderService/`: Lambda functions for order operations with tenant isolation
- `server/Resources/authorizer.py`: Business Services Authorizer implementation

### Step 3: Review and Add Missing Code

**Important**: This lab contains TODO comments marking areas where you'll implement tenant isolation logic. Look for:

```python
# TODO: Implement tenant-scoped IAM policy generation
# TODO: Add STS AssumeRole call with tenant context
# TODO: Implement DynamoDB condition expression for tenant isolation
```

**Key Files to Review**:

1. **`server/Resources/authorizer.py`**: Business Services Authorizer
   - Validates JWT tokens
   - Extracts tenant ID from token claims
   - Generates STS credentials scoped to tenant
   - Returns IAM policy with tenant-specific conditions

2. **`server/ProductService/product_service.py`**: Product operations
   - Uses tenant-scoped credentials from authorizer
   - Implements DynamoDB queries with tenant ID filtering

3. **`server/OrderService/order_service.py`**: Order operations
   - Uses tenant-scoped credentials from authorizer
   - Implements DynamoDB queries with tenant ID filtering

**Note**: The Solution folder contains completed implementations if you need reference.

### Step 4: Deploy the Lab

Deploy both shared and tenant stacks:

```
cd scripts
./deployment.sh -s -c --email your-email@example.com --tenant-email tenant-email@example.com --profile serverless-saas-demo
```

**Parameters**:
- `-s`: Deploy both shared and tenant stacks
- `-c`: Clean deployment (removes existing stacks if present)
- `--email`: Admin user email for system operations
- `--tenant-email`: Email for test tenant creation
- `--profile`: AWS CLI profile to use (required)

**Deployment Time**: Approximately 18-20 minutes

**What Gets Deployed**:
1. Shared stack with tenant management services
2. Tenant stack with business services and IAM isolation
3. CloudFront distributions for web applications
4. S3 buckets with static website content
5. DynamoDB tables with tenant isolation policies
6. Lambda functions with tenant-scoped IAM roles

### Step 5: Retrieve Application URLs

After deployment completes, get the application URLs:

```
./geturl.sh --profile serverless-saas-demo
```

**Expected Output**:
```
Admin Site URL: https://<admin-cloudfront-id>.cloudfront.net
Landing Site URL: https://<landing-cloudfront-id>.cloudfront.net
App Site URL: https://<app-cloudfront-id>.cloudfront.net
```

Save these URLs - you'll need them for testing.


## Verification

### 1. Verify CloudFormation Stacks

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab4 \
  --profile serverless-saas-demo \
  --query 'Stacks[0].StackStatus'

aws cloudformation describe-stacks \
  --stack-name serverless-saas-tenant-lab4 \
  --profile serverless-saas-demo \
  --query 'Stacks[0].StackStatus'
```

Both should return `"CREATE_COMPLETE"`.

### 2. Verify DynamoDB Tables

```
aws dynamodb list-tables --profile serverless-saas-demo | grep lab4
```

Expected tables:
- `TenantDetails-lab4`
- `TenantUserMapping-lab4`
- `Product-lab4`
- `Order-lab4`

### 3. Verify Lambda Functions

```
aws lambda list-functions --profile serverless-saas-demo | grep lab4 | wc -l
```

Should show 27 Lambda functions (16 shared + 11 tenant).

### 4. Verify IAM Roles

```
aws iam list-roles --profile serverless-saas-demo | grep lab4
```

Look for:
- `AuthorizerAccessRole`
- `ProductFunctionRole`
- `OrderFunctionRole`

### 5. Verify CloudWatch Log Groups

```
aws logs describe-log-groups \
  --profile serverless-saas-demo \
  --query 'logGroups[?contains(logGroupName, `lab4`)].logGroupName'
```

All log groups should have 60-day retention.

### 6. Test Application Access

1. Open the **Landing Site URL** in your browser
2. Click "Sign Up" and create a new tenant account
3. Complete the registration process
4. You should be redirected to the Application site
5. Verify you can access the product and order pages


## Testing Tenant Isolation

This section provides comprehensive instructions for testing the tenant data isolation mechanisms implemented in Lab 4.

### Understanding Tenant Isolation

Lab 4 implements **IAM policy-based tenant isolation** in a pooled architecture. This means:

1. **All tenants share the same DynamoDB tables** (Product-lab4, Order-lab4)
2. **Each tenant's data is logically separated** using tenant ID in the partition key
3. **IAM policies enforce access control** at the row level
4. **STS credentials are scoped to each tenant** preventing cross-tenant access

### Test Scenario Overview

We'll create two tenants and verify that:
- Tenant A can only access Tenant A's data
- Tenant B can only access Tenant B's data
- Attempting cross-tenant access is denied by IAM policies
- The Business Services Authorizer correctly generates tenant-scoped credentials

### Step 1: Create Two Test Tenants

#### Create Tenant A

1. Open the **Landing Site URL** in your browser
2. Click "Sign Up"
3. Fill in the registration form:
   - **Company Name**: TenantA Corp
   - **Email**: tenant-a@example.com
   - **Tier**: Select "Basic" or "Standard"
4. Click "Register"
5. Check your email for the verification code
6. Complete the verification process
7. **Save the tenant credentials** (email and password)

#### Create Tenant B

1. Open the **Landing Site URL** in an incognito/private browser window
2. Click "Sign Up"
3. Fill in the registration form:
   - **Company Name**: TenantB Inc
   - **Email**: tenant-b@example.com
   - **Tier**: Select "Basic" or "Standard"
4. Click "Register"
5. Check your email for the verification code
6. Complete the verification process
7. **Save the tenant credentials** (email and password)

### Step 2: Create Test Data for Tenant A

1. Log in to the **App Site URL** as Tenant A
2. Navigate to the **Products** page
3. Create a product:
   - **Product Name**: Tenant A Product 1
   - **Price**: $100
   - **SKU**: TENA-001
4. Click "Add Product"
5. Create another product:
   - **Product Name**: Tenant A Product 2
   - **Price**: $200
   - **SKU**: TENA-002
6. Navigate to the **Orders** page
7. Create an order:
   - **Order Name**: Tenant A Order 1
   - Select products from the list
8. **Note the product and order IDs** displayed in the UI

### Step 3: Create Test Data for Tenant B

1. Log in to the **App Site URL** as Tenant B (use incognito window)
2. Navigate to the **Products** page
3. Create a product:
   - **Product Name**: Tenant B Product 1
   - **Price**: $150
   - **SKU**: TENB-001
4. Create another product:
   - **Product Name**: Tenant B Product 2
   - **Price**: $250
   - **SKU**: TENB-002
5. Navigate to the **Orders** page
6. Create an order:
   - **Order Name**: Tenant B Order 1
   - Select products from the list
7. **Note the product and order IDs** displayed in the UI


### Step 4: Verify Tenant A Can Only See Their Data

1. While logged in as **Tenant A**, navigate to the Products page
2. **Verify**: You should see only Tenant A's products (TENA-001, TENA-002)
3. **Verify**: You should NOT see Tenant B's products (TENB-001, TENB-002)
4. Navigate to the Orders page
5. **Verify**: You should see only Tenant A's orders
6. **Verify**: You should NOT see Tenant B's orders

### Step 5: Verify Tenant B Can Only See Their Data

1. While logged in as **Tenant B**, navigate to the Products page
2. **Verify**: You should see only Tenant B's products (TENB-001, TENB-002)
3. **Verify**: You should NOT see Tenant A's products (TENA-001, TENA-002)
4. Navigate to the Orders page
5. **Verify**: You should see only Tenant B's orders
6. **Verify**: You should NOT see Tenant A's orders

### Step 6: Verify DynamoDB Data Isolation

Check the actual DynamoDB data to confirm isolation:

```
# List all products in the Product table
aws dynamodb scan \
  --table-name Product-lab4 \
  --profile serverless-saas-demo \
  --query 'Items[*].[productId.S, productName.S]' \
  --output table
```

**Expected Output**: You should see products from both tenants, but with different partition keys:
- Tenant A products: `tenantA-id-TENA-001`, `tenantA-id-TENA-002`
- Tenant B products: `tenantB-id-TENB-001`, `tenantB-id-TENB-002`

```
# List all orders in the Order table
aws dynamodb scan \
  --table-name Order-lab4 \
  --profile serverless-saas-demo \
  --query 'Items[*].[orderId.S, orderName.S]' \
  --output table
```

**Expected Output**: Orders from both tenants with tenant-specific partition keys.

### Step 7: Test Cross-Tenant Access Prevention (Advanced)

This test requires using the AWS CLI to attempt direct API calls with manipulated credentials.

#### Get Tenant A's JWT Token

1. Log in as Tenant A in the browser
2. Open browser Developer Tools (F12)
3. Go to the **Application** or **Storage** tab
4. Find **Local Storage** or **Session Storage**
5. Look for the JWT token (usually stored as `idToken` or `accessToken`)
6. Copy the token value

#### Attempt to Access Tenant B's Data with Tenant A's Token

```
# Replace <TENANT_A_JWT_TOKEN> with the actual token
# Replace <API_GATEWAY_URL> with your Tenant API Gateway URL
# Replace <TENANT_B_PRODUCT_ID> with an actual Tenant B product ID

curl -X GET \
  "https://<API_GATEWAY_URL>/products/<TENANT_B_PRODUCT_ID>" \
  -H "Authorization: Bearer <TENANT_A_JWT_TOKEN>" \
  -v
```

**Expected Result**: 
- HTTP Status: `403 Forbidden` or `401 Unauthorized`
- Error Message: "Access Denied" or "User is not authorized to access this resource"
- This confirms the IAM policy is preventing cross-tenant access

### Step 8: Verify CloudWatch Logs for Authorization

Check the Business Services Authorizer logs to see the IAM policy generation:

```
# Get the authorizer log group name
aws logs describe-log-groups \
  --profile serverless-saas-demo \
  --query 'logGroups[?contains(logGroupName, `BusinessServicesAuthorizer`)].logGroupName' \
  --output text

# Tail the logs (replace <LOG_GROUP_NAME> with actual name)
aws logs tail <LOG_GROUP_NAME> \
  --profile serverless-saas-demo \
  --follow
```

**What to Look For**:
- Log entries showing JWT token validation
- Tenant ID extraction from token claims
- STS AssumeRole calls with tenant context
- Generated IAM policy with tenant-specific conditions
- Authorization decisions (Allow/Deny)

**Example Log Entry**:
```json
{
  "message": "Generated IAM policy for tenant: tenant-123",
  "policy": {
    "principalId": "tenant-123",
    "policyDocument": {
      "Statement": [{
        "Effect": "Allow",
        "Action": ["dynamodb:*"],
        "Resource": "arn:aws:dynamodb:*:*:table/Product-lab4",
        "Condition": {
          "ForAllValues:StringEquals": {
            "dynamodb:LeadingKeys": ["tenant-123-*"]
          }
        }
      }]
    }
  }
}
```


### Step 9: Verify IAM Policy Enforcement

Check the IAM roles to understand the policy structure:

```
# Get the ProductFunctionRole policy
aws iam get-role \
  --role-name ProductFunctionRole-lab4 \
  --profile serverless-saas-demo \
  --query 'Role.AssumeRolePolicyDocument'

# List attached policies
aws iam list-attached-role-policies \
  --role-name ProductFunctionRole-lab4 \
  --profile serverless-saas-demo
```

**Key Policy Elements**:
- **Condition Keys**: `dynamodb:LeadingKeys` restricts access to items with specific partition key prefixes
- **Resource ARNs**: Policies are scoped to specific DynamoDB tables
- **Actions**: Limited to necessary DynamoDB operations (GetItem, PutItem, Query, etc.)

### Step 10: Test Isolation with Admin Portal

1. Log in to the **Admin Site URL** using the admin credentials
2. Navigate to **Tenants** page
3. View the list of all tenants (you should see both Tenant A and Tenant B)
4. Click on Tenant A to view details
5. **Verify**: You can see tenant metadata but NOT tenant-specific business data (products/orders)
6. This confirms that admin functions are separate from tenant data access

### Expected Test Results Summary

| Test | Expected Result | Validates |
|------|----------------|-----------|
| Tenant A views products | Sees only Tenant A products | Row-level isolation |
| Tenant B views products | Sees only Tenant B products | Row-level isolation |
| Tenant A views orders | Sees only Tenant A orders | Row-level isolation |
| Tenant B views orders | Sees only Tenant B orders | Row-level isolation |
| DynamoDB scan | Shows all data with tenant prefixes | Physical data structure |
| Cross-tenant API call | Returns 403 Forbidden | IAM policy enforcement |
| Authorizer logs | Shows tenant-scoped policy generation | STS credential scoping |
| IAM role policies | Contains tenant-specific conditions | Policy-based isolation |

### Troubleshooting Isolation Issues

If you can see another tenant's data:

1. **Check JWT Token**: Verify the token contains the correct tenant ID claim
2. **Check Authorizer Logic**: Review `server/Resources/authorizer.py` for tenant ID extraction
3. **Check IAM Policies**: Verify the generated policy includes tenant-specific conditions
4. **Check DynamoDB Keys**: Ensure partition keys include tenant ID prefix
5. **Check CloudWatch Logs**: Look for authorization errors or policy generation issues

If cross-tenant access is NOT blocked:

1. **Verify IAM Policy Conditions**: Check that `dynamodb:LeadingKeys` condition is present
2. **Verify STS Credentials**: Ensure the authorizer is generating scoped credentials
3. **Verify Lambda Execution**: Check that Lambda functions are using the scoped credentials
4. **Check API Gateway Configuration**: Verify the custom authorizer is attached to all routes


## Understanding the Implementation

### Business Services Authorizer

The authorizer is the key component that enforces tenant isolation:

```python
def lambda_handler(event, context):
    # 1. Extract JWT token from Authorization header
    token = event['authorizationToken']
    
    # 2. Validate JWT token with Cognito
    claims = validate_jwt(token)
    
    # 3. Extract tenant ID from token claims
    tenant_id = claims['custom:tenantId']
    
    # 4. Generate STS credentials scoped to tenant
    sts_client = boto3.client('sts')
    assumed_role = sts_client.assume_role(
        RoleArn=f'arn:aws:iam::{account_id}:role/TenantAccessRole',
        RoleSessionName=f'tenant-{tenant_id}',
        Policy=generate_tenant_policy(tenant_id)
    )
    
    # 5. Return IAM policy with tenant-scoped credentials
    return {
        'principalId': tenant_id,
        'policyDocument': generate_policy(tenant_id),
        'context': {
            'tenantId': tenant_id,
            'accessKeyId': assumed_role['Credentials']['AccessKeyId'],
            'secretAccessKey': assumed_role['Credentials']['SecretAccessKey'],
            'sessionToken': assumed_role['Credentials']['SessionToken']
        }
    }
```

### IAM Policy Generation

The authorizer generates policies with tenant-specific conditions:

```python
def generate_tenant_policy(tenant_id):
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                "Resource": [
                    f"arn:aws:dynamodb:*:*:table/Product-lab4",
                    f"arn:aws:dynamodb:*:*:table/Order-lab4"
                ],
                "Condition": {
                    "ForAllValues:StringLike": {
                        "dynamodb:LeadingKeys": [f"{tenant_id}-*"]
                    }
                }
            }
        ]
    }
```

### Lambda Function Implementation

Lambda functions use the scoped credentials from the authorizer:

```python
def get_product(event, context):
    # 1. Extract tenant context from authorizer
    tenant_id = event['requestContext']['authorizer']['tenantId']
    access_key = event['requestContext']['authorizer']['accessKeyId']
    secret_key = event['requestContext']['authorizer']['secretAccessKey']
    session_token = event['requestContext']['authorizer']['sessionToken']
    
    # 2. Create DynamoDB client with scoped credentials
    dynamodb = boto3.client(
        'dynamodb',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        aws_session_token=session_token
    )
    
    # 3. Query DynamoDB with tenant-scoped key
    product_id = event['pathParameters']['productId']
    response = dynamodb.get_item(
        TableName='Product-lab4',
        Key={'productId': {'S': f'{tenant_id}-{product_id}'}}
    )
    
    # 4. Return product data
    return {
        'statusCode': 200,
        'body': json.dumps(response['Item'])
    }
```

### Key Security Principles

1. **Least Privilege**: IAM policies grant only the minimum permissions needed
2. **Defense in Depth**: Multiple layers of security (JWT validation, IAM policies, DynamoDB conditions)
3. **Temporary Credentials**: STS credentials expire after a short period
4. **Explicit Deny**: Any access outside the tenant's data is explicitly denied
5. **Audit Trail**: All access attempts are logged in CloudWatch


## Cleanup

When you're finished with Lab 4, clean up all resources to avoid ongoing AWS charges.

### Automated Cleanup

```
cd workshop/Lab4/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab4 --profile serverless-saas-demo
```

**What Gets Deleted**:
1. CloudFormation stacks (shared and tenant)
2. Lambda functions and layers
3. DynamoDB tables and data
4. API Gateway REST APIs
5. Cognito User Pools and users
6. IAM roles and policies
7. CloudWatch log groups
8. S3 buckets and website content
9. CloudFront distributions

**Cleanup Time**: Approximately 15-20 minutes (CloudFront distributions take the longest)

### Verify Cleanup

After cleanup completes, verify all resources are removed:

```
# Check CloudFormation stacks
aws cloudformation list-stacks \
  --profile serverless-saas-demo \
  --query 'StackSummaries[?contains(StackName, `lab4`) && StackStatus!=`DELETE_COMPLETE`]'

# Check DynamoDB tables
aws dynamodb list-tables \
  --profile serverless-saas-demo | grep lab4

# Check Lambda functions
aws lambda list-functions \
  --profile serverless-saas-demo | grep lab4

# Check S3 buckets
aws s3 ls --profile serverless-saas-demo | grep lab4
```

All commands should return empty results.

### Manual Cleanup (If Needed)

If automated cleanup fails, manually delete resources:

```
# Delete CloudFormation stacks
aws cloudformation delete-stack \
  --stack-name serverless-saas-tenant-lab4 \
  --profile serverless-saas-demo

aws cloudformation delete-stack \
  --stack-name serverless-saas-shared-lab4 \
  --profile serverless-saas-demo

# Wait for stack deletion
aws cloudformation wait stack-delete-complete \
  --stack-name serverless-saas-tenant-lab4 \
  --profile serverless-saas-demo

# Delete S3 buckets (if any remain)
aws s3 rb s3://$(aws s3 ls --profile serverless-saas-demo | grep lab4 | awk '{print $3}') \
  --force \
  --profile serverless-saas-demo

# Delete CloudWatch log groups
aws logs describe-log-groups \
  --profile serverless-saas-demo \
  --query 'logGroups[?contains(logGroupName, `lab4`)].logGroupName' \
  --output text | xargs -I {} aws logs delete-log-group \
  --log-group-name {} \
  --profile serverless-saas-demo
```


## Troubleshooting

### Deployment Issues

#### Issue: SAM build fails with Python version error

**Symptom**: Error message about Python 3.14 not found

**Solution**:
```
# Verify Python 3.14 is installed
python3.14 --version

# If not installed, install Python 3.14
# On macOS with Homebrew:
brew install python@3.14

# On Amazon Linux 2023:
sudo dnf install python3.14
```

#### Issue: CloudFormation stack creation fails

**Symptom**: Stack status shows `ROLLBACK_COMPLETE` or `CREATE_FAILED`

**Solution**:
```
# Check stack events for error details
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-shared-lab4 \
  --profile serverless-saas-demo \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Common causes:
# 1. Insufficient IAM permissions - verify your AWS profile has admin access
# 2. Resource limits - check service quotas in AWS Console
# 3. Existing resources - run cleanup script first
```

#### Issue: Deployment script hangs or times out

**Symptom**: Script runs for more than 30 minutes without completing

**Solution**:
```
# Check CloudFormation stack status
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab4 \
  --profile serverless-saas-demo \
  --query 'Stacks[0].StackStatus'

# If stuck in CREATE_IN_PROGRESS, check for failed resources
aws cloudformation describe-stack-resources \
  --stack-name serverless-saas-shared-lab4 \
  --profile serverless-saas-demo \
  --query 'StackResources[?ResourceStatus!=`CREATE_COMPLETE`]'
```

### Tenant Isolation Issues

#### Issue: Can see other tenant's data

**Symptom**: Tenant A can view Tenant B's products or orders

**Solution**:
1. **Verify JWT token contains tenant ID**:
   ```
   # Decode JWT token (use jwt.io or a JWT decoder)
   # Check for 'custom:tenantId' claim
   ```

2. **Check authorizer logs**:
   ```
   aws logs tail /aws/lambda/BusinessServicesAuthorizer-lab4 \
     --profile serverless-saas-demo \
     --follow
   ```

3. **Verify IAM policy generation**:
   - Look for log entries showing policy generation
   - Verify the policy includes `dynamodb:LeadingKeys` condition
   - Confirm the condition uses the correct tenant ID

4. **Check DynamoDB partition keys**:
   ```
   aws dynamodb scan \
     --table-name Product-lab4 \
     --profile serverless-saas-demo \
     --max-items 5
   ```
   - Verify keys start with tenant ID (e.g., `tenant-123-product-456`)

#### Issue: Cross-tenant access not blocked

**Symptom**: API calls with Tenant A's token can access Tenant B's data

**Solution**:
1. **Verify custom authorizer is attached**:
   ```
   aws apigateway get-authorizers \
     --rest-api-id <API_ID> \
     --profile serverless-saas-demo
   ```

2. **Check authorizer configuration**:
   - Verify authorizer type is `TOKEN`
   - Verify token source is `Authorization` header
   - Verify authorizer Lambda function is correct

3. **Test authorizer directly**:
   ```
   aws lambda invoke \
     --function-name BusinessServicesAuthorizer-lab4 \
     --payload '{"authorizationToken":"Bearer <JWT_TOKEN>","methodArn":"arn:aws:execute-api:*:*:*/GET/products"}' \
     --profile serverless-saas-demo \
     response.json
   
   cat response.json
   ```

#### Issue: 403 Forbidden on all API calls

**Symptom**: All API calls return 403, even for valid tenant data

**Solution**:
1. **Check JWT token expiration**:
   - Tokens expire after 1 hour by default
   - Log out and log back in to get a fresh token

2. **Verify Cognito User Pool configuration**:
   ```
   aws cognito-idp describe-user-pool \
     --user-pool-id <POOL_ID> \
     --profile serverless-saas-demo
   ```

3. **Check Lambda execution role permissions**:
   ```
   aws iam get-role \
     --role-name ProductFunctionRole-lab4 \
     --profile serverless-saas-demo
   ```

### Application Issues

#### Issue: CloudFront returns 403 or 404

**Symptom**: Application URLs return errors

**Solution**:
```
# Check S3 bucket website configuration
aws s3api get-bucket-website \
  --bucket <BUCKET_NAME> \
  --profile serverless-saas-demo

# Verify CloudFront distribution status
aws cloudfront list-distributions \
  --profile serverless-saas-demo \
  --query 'DistributionList.Items[?contains(Comment, `lab4`)]'

# Wait for CloudFront distribution to deploy (can take 15-20 minutes)
```

#### Issue: Cannot create tenant or user

**Symptom**: Registration fails with error

**Solution**:
1. **Check Cognito User Pool**:
   ```
   aws cognito-idp list-users \
     --user-pool-id <POOL_ID> \
     --profile serverless-saas-demo
   ```

2. **Check TenantDetails table**:
   ```
   aws dynamodb scan \
     --table-name TenantDetails-lab4 \
     --profile serverless-saas-demo
   ```

3. **Check Lambda function logs**:
   ```
   aws logs tail /aws/lambda/RegisterTenant-lab4 \
     --profile serverless-saas-demo \
     --follow
   ```

### Performance Issues

#### Issue: API calls are slow

**Symptom**: API responses take more than 2-3 seconds

**Solution**:
1. **Check Lambda cold starts**:
   - First request after idle period is slower
   - Subsequent requests should be faster

2. **Check DynamoDB capacity**:
   ```
   aws dynamodb describe-table \
     --table-name Product-lab4 \
     --profile serverless-saas-demo \
     --query 'Table.BillingModeSummary'
   ```

3. **Review CloudWatch metrics**:
   - Lambda duration
   - DynamoDB consumed capacity
   - API Gateway latency


## Key Takeaways

### Tenant Isolation Patterns

Lab 4 demonstrates the **IAM policy-based isolation pattern** for pooled multi-tenancy:

**Advantages**:
- Cost-effective: Shared infrastructure reduces operational costs
- Scalable: No per-tenant resource provisioning required
- Centralized: Single codebase and deployment for all tenants
- Flexible: Easy to add new tenants without infrastructure changes

**Considerations**:
- Complexity: Requires careful IAM policy design and testing
- Performance: Shared resources may have noisy neighbor effects
- Security: Must ensure policies are correctly implemented and tested
- Compliance: May not meet requirements for highly regulated industries

### Security Best Practices

1. **Always validate JWT tokens**: Never trust client-provided tenant IDs
2. **Use temporary credentials**: STS credentials expire automatically
3. **Implement least privilege**: Grant only necessary permissions
4. **Log all access attempts**: Maintain audit trail for compliance
5. **Test isolation thoroughly**: Verify cross-tenant access is blocked
6. **Monitor for anomalies**: Alert on unusual access patterns
7. **Regular security reviews**: Audit IAM policies and access logs

### When to Use This Pattern

**Use IAM policy-based isolation when**:
- Cost optimization is a priority
- Tenants have similar resource requirements
- Compliance allows shared infrastructure
- You need to scale to thousands of tenants
- Operational simplicity is important

**Consider alternative patterns when**:
- Regulatory compliance requires physical separation
- Tenants have vastly different resource needs
- Performance isolation is critical
- Tenants require custom configurations
- You have a small number of high-value tenants

### Comparison with Other Isolation Patterns

| Pattern | Cost | Isolation | Complexity | Scalability |
|---------|------|-----------|------------|-------------|
| **IAM Policy (Lab 4)** | Low | Medium | Medium | High |
| **Siloed (Lab 5)** | High | High | Low | Medium |
| **Hybrid (Lab 5)** | Medium | High | High | High |
| **Database-level** | Low | Low | Low | High |

## Additional Resources

### AWS Documentation

- [AWS IAM Policy Conditions](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition.html)
- [DynamoDB Condition Keys](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html)
- [AWS STS AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [API Gateway Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Multi-Tenant SaaS on AWS](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)

### Workshop Resources

- **Official Workshop**: [AWS Serverless SaaS Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US)
- **Lab 4 Guide**: [Isolating Tenant Data in a Pooled Model](https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US/lab4)
- **Solution Code**: `workshop/Solution/Lab4/` directory
- **Architecture Diagrams**: Available in the official workshop guide

### Related Labs

- **Lab 3**: Multi-tenancy in microservices (prerequisite concepts)
- **Lab 5**: Tier-based deployment strategies (alternative isolation patterns)
- **Lab 6**: Tenant throttling and quotas (complementary security controls)
- **Lab 7**: Cost attribution in pooled model (operational considerations)

### Community Resources

- [AWS SaaS Factory](https://aws.amazon.com/partners/programs/saas-factory/)
- [AWS SaaS Boost](https://github.com/awslabs/aws-saas-boost)
- [AWS Well-Architected SaaS Lens](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)

## Next Steps

After completing Lab 4, you can:

1. **Proceed to Lab 5**: Learn about tier-based deployment strategies and hybrid isolation models
2. **Explore Lab 6**: Implement tenant throttling and API quotas
3. **Review Lab 7**: Understand cost attribution in pooled architectures
4. **Experiment with the code**: Modify IAM policies to test different isolation scenarios
5. **Deploy to production**: Adapt this pattern for your own SaaS application

## Feedback and Support

If you encounter issues or have questions:

1. Check the **Troubleshooting** section above
2. Review the **CloudWatch logs** for detailed error messages
3. Consult the **official workshop guide** for additional context
4. Check the **Solution code** in `workshop/Solution/Lab4/`
5. Open an issue in the workshop repository

---

**Congratulations!** You've successfully implemented and tested tenant data isolation in a pooled multi-tenant architecture using IAM policies and STS credentials. This is a critical security pattern for building scalable, cost-effective SaaS applications on AWS.

