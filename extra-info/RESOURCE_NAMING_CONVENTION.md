# Resource Naming Convention for AWS Serverless SaaS Workshop

## Overview
This document defines the standard naming conventions for all resources across all labs to ensure independent deployment and avoid resource conflicts.

## Base Format

All resources should follow this naming pattern:

```
serverless-saas-lab{N}-{resource-type}-{optional-suffix}
```

Where:
- `{N}` = Lab number (1, 2, 3, 4, 5, etc.)
- `{resource-type}` = Type of resource (admin, app, landing, pool, ops, etc.)
- `{optional-suffix}` = Additional identifier when needed (tenant ID, ShortId, etc.)

### ShortId Technique for Global Uniqueness

For resources requiring global uniqueness (S3 buckets, Cognito domains), use the ShortId technique:

**Character Budget:**
- S3/Cognito limit: 63 characters
- Base: `serverless-saas-lab5` = 20 characters
- Remaining: 43 characters for resource type + ShortId

**ShortId Extraction:**
```yaml
ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

This extracts the first 8 characters from the CloudFormation Stack ID UUID:
- Stack ID: `arn:aws:cloudformation:us-east-1:123456789012:stack/my-stack/763a1250-ed71-11f0-9f85-0e8d661a88d1`
- Extracted UUID: `763a1250-ed71-11f0-9f85-0e8d661a88d1`
- ShortId: `763a1250` (first segment before hyphen)

## Resource-Specific Patterns

### 1. S3 Buckets
**Pattern:** `serverless-saas-lab{N}-{bucket-type}-${ShortId}`

**Character Calculation:**
- Base: `serverless-saas-lab5` = 20 characters
- Bucket type (e.g., `-landing`): ~8 characters  
- Separator: 1 character
- ShortId: 8 characters (first segment of UUID)
- Total: ~37 characters (well under 63-character limit)

**Implementation:**
```yaml
BucketName: !Sub 
  - 'serverless-saas-lab{N}-{bucket-type}-${ShortId}'
  - ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

**Examples:**
- Lab 1: `serverless-saas-lab1-admin-763a1250`
- Lab 2: `serverless-saas-lab2-app-ed7111f0`
- Lab 5: `serverless-saas-lab5-landing-9f850e8d`

**Bucket Types:**
- `admin` - Admin application bucket
- `app` - Tenant application bucket
- `landing` - Landing page bucket

**Why ShortId?**
- S3 bucket names must be globally unique across ALL AWS accounts
- Extracts first 8 characters of CloudFormation Stack ID UUID
- Ensures uniqueness without exposing AWS Account ID
- Keeps bucket names under the 63-character S3 limit
- Format: Takes UUID like `763a1250-ed71-11f0-9f85-0e8d661a88d1` and extracts `763a1250`

### 2. Lambda Functions
**Pattern:** `serverless-saas-lab{N}-{function-name}`

**Examples:**
- `serverless-saas-lab5-create-tenant`
- `serverless-saas-lab5-get-products`
- `serverless-saas-lab5-shared-services-authorizer`

### 3. Lambda Layers
**Pattern:** `serverless-saas-dependencies-lab{N}` (shared)
**Pattern:** `serverless-saas-dependencies-{tenantId}-lab{N}` (tenant-specific)

**Examples:**
- `serverless-saas-dependencies-lab5`
- `serverless-saas-dependencies-pooled-lab5`

### 4. DynamoDB Tables
**Pattern:** `ServerlessSaaS-{TableName}-lab{N}` (shared)
**Pattern:** `{TableName}-{tenantId}-lab{N}` (tenant-specific)

**Examples:**
- Shared: `ServerlessSaaS-Settings-lab5`
- Shared: `ServerlessSaaS-TenantDetails-lab5`
- Tenant: `Product-pooled-lab5`
- Tenant: `Order-tenant123-lab5`

### 5. IAM Roles
**Pattern:** `{role-name}-lab{N}`

**Examples:**
- `authorizer-execution-role-lab5`
- `tenant-management-lambda-execution-role-lab5`
- `pooled-product-function-execution-role-lab5`

**Note:** IAM roles are global resources, so no region suffix is needed.

### 6. IAM Policies
**Pattern:** `{policy-name}-lab{N}`

**Examples:**
- `authorizer-execution-policy-lab5`
- `tenant-management-lambda-execution-policy-lab5`
- `create-user-lambda-execution-policy-lab5`

**Note:** IAM policies are global resources, so no region suffix is needed.

### 7. Cognito User Pools
**Pattern:** `{PoolType}-ServerlessSaaS-lab{N}-UserPool`

**Examples:**
- `PooledTenant-ServerlessSaaS-lab5-UserPool`
- `OperationUsers-ServerlessSaas-lab5-UserPool`

### 8. Cognito User Pool Domains
**Pattern:** `serverless-saas-lab{N}-{domain-type}-${ShortId}`

**Implementation:**
```yaml
Domain: !Sub 
  - 'serverless-saas-lab{N}-{domain-type}-${ShortId}'
  - ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

**Examples:**
- `serverless-saas-lab5-pool-763a1250` (tenant pool)
- `serverless-saas-lab5-ops-ed7111f0` (operations pool)

**Domain Types:**
- `pool` - Tenant user pool domain
- `ops` - Operations/admin user pool domain

### 9. CloudFormation Stacks
**Pattern:** `serverless-saas-lab{N}` (main stack)
**Pattern:** `serverless-saas-{stack-type}-lab{N}` (additional stacks)

**Examples:**
- `serverless-saas-lab1` (main stack for Lab 1)
- `serverless-saas-lab2` (main stack for Lab 2)
- `serverless-saas-shared-lab5` (shared resources stack)
- `serverless-saas-tenant-lab5` (tenant-specific stack)

### 10. CloudFormation Exports
**Pattern:** `Serverless-SaaS-{ExportName}-lab{N}`

**Examples:**
- `Serverless-SaaS-CognitoOperationUsersUserPoolId-lab5`
- `Serverless-SaaS-AuthorizerExecutionRoleArn-lab5`

### 11. API Gateway REST APIs
**Pattern:** `serverless-saas-{api-type}-api-lab{N}`

**Examples:**
- `serverless-saas-admin-api-lab5`
- `pooled-serverless-saas-tenant-api-lab5`

### 12. API Gateway Log Groups
**Pattern:** `/aws/api-gateway/access-logs-serverless-saas-lab{N}-{api-type}-{identifier}`

**Examples:**
- `/aws/api-gateway/access-logs-serverless-saas-lab5-admin-api`
- `/aws/api-gateway/access-logs-serverless-saas-lab5-tenant-api-pooled`

### 13. API Gateway CloudWatch Role (Shared Across All Labs)
**Pattern:** `apigateway-cloudwatch-publish-role` (NO lab suffix)

**Resource:** `AWS::ApiGateway::Account` (singleton per region)

**Why No Lab Suffix?**
- `AWS::ApiGateway::Account` is a singleton resource - only ONE can exist per AWS account per region
- It sets the CloudWatch logging role for ALL API Gateways in that region
- This role is shared across all labs to avoid conflicts
- The IAM role name should be generic: `apigateway-cloudwatch-publish-role`

**Example:**
```yaml
ApiGatewayCloudWatchLogRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: apigateway-cloudwatch-publish-role  # No lab suffix
    ManagedPolicyArns:
      - arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs

ApiGatewayAttachCloudwatchLogArn:
  Type: AWS::ApiGateway::Account  # Singleton resource
  Properties:
    CloudWatchRoleArn: !GetAtt ApiGatewayCloudWatchLogRole.Arn
```

## Shared Resources (No Lab Suffix)

Some resources are shared across all labs and should NOT have a lab suffix:

### 1. CI/CD Pipeline Stack
- **Stack Name:** `serverless-saas-pipeline`
- **Why:** Shared CI/CD infrastructure used by all labs

### 2. CDK Bootstrap Stack
- **Stack Name:** `CDKToolkit`
- **Why:** AWS CDK bootstrap stack required for CDK deployments

### 3. API Gateway CloudWatch Role
- **Role Name:** `apigateway-cloudwatch-publish-role`
- **Resource:** `AWS::ApiGateway::Account` (singleton)
- **Why:** Singleton resource per region that applies to ALL API Gateways

These resources are intentionally shared to avoid duplication and conflicts.

## Implementation Checklist

When creating a new lab or updating an existing one, ensure:

- [ ] All S3 buckets use the UniqueId pattern for global uniqueness
- [ ] All Lambda functions have `serverless-saas-lab{N}-` prefix
- [ ] All Lambda layers have `-lab{N}` suffix
- [ ] All DynamoDB tables have `-lab{N}` suffix
- [ ] All IAM roles have `-lab{N}` suffix (with optional region)
- [ ] All IAM policies have `-lab{N}` suffix (with optional region)
- [ ] All Cognito User Pools have `-lab{N}` suffix
- [ ] All CloudFormation exports have `-lab{N}` suffix
- [ ] All CloudFormation imports reference the correct `-lab{N}` exports
- [ ] Stack names include `lab{N}` identifier

## Benefits

1. **Independent Deployment**: Each lab can be deployed without conflicts
2. **Easy Identification**: Resources are clearly labeled by lab number
3. **No Cross-Lab Dependencies**: Labs don't accidentally reference each other's resources
4. **Global Uniqueness**: S3 buckets work across all AWS accounts
5. **Consistent Pattern**: Easy to understand and maintain

## Example: Complete Lab 5 Resource Set

```
S3 Buckets (with ShortId for global uniqueness):
- serverless-saas-lab5-admin-763a1250
- serverless-saas-lab5-app-763a1250
- serverless-saas-lab5-landing-763a1250

Cognito User Pools:
- PooledTenant-ServerlessSaaS-lab5-UserPool
- OperationUsers-ServerlessSaas-lab5-UserPool

Cognito User Pool Domains (with ShortId for global uniqueness):
- serverless-saas-lab5-pool-763a1250
- serverless-saas-lab5-ops-763a1250

Lambda Functions:
- serverless-saas-lab5-create-tenant
- serverless-saas-lab5-register-tenant
- serverless-saas-lab5-get-products
- serverless-saas-lab5-create-user
- serverless-saas-lab5-shared-services-authorizer

Lambda Layers:
- serverless-saas-dependencies-lab5
- serverless-saas-dependencies-pooled-lab5

DynamoDB Tables:
- ServerlessSaaS-Settings-lab5
- ServerlessSaaS-TenantDetails-lab5
- ServerlessSaaS-TenantStackMapping-lab5
- ServerlessSaaS-TenantUserMapping-lab5
- Product-pooled-lab5
- Order-pooled-lab5

IAM Roles:
- authorizer-execution-role-lab5
- authorizer-access-role-lab5
- tenant-management-lambda-execution-role-lab5
- create-user-lambda-execution-role-lab5
- pooled-product-function-execution-role-lab5
- pooled-order-function-execution-role-lab5

IAM Policies:
- authorizer-execution-policy-lab5
- tenant-management-lambda-execution-policy-lab5
- create-user-lambda-execution-policy-lab5

CloudFormation Stacks:
- serverless-saas-lab5 (or serverless-saas-shared-lab5 for shared resources)
- serverless-saas-tenant-lab5

CloudFormation Exports:
- Serverless-SaaS-CognitoOperationUsersUserPoolId-lab5
- Serverless-SaaS-CognitoTenantUserPoolId-lab5
- Serverless-SaaS-AuthorizerExecutionRoleArn-lab5

API Gateway REST APIs:
- serverless-saas-admin-api-lab5

API Gateway Log Groups:
- /aws/api-gateway/access-logs-serverless-saas-lab5-admin-api
- /aws/api-gateway/access-logs-serverless-saas-lab5-tenant-api-pooled

DynamoDB GSI:
- ServerlessSaas-TenantConfig-lab5
```

## Resource Tagging Strategy

All AWS resources created in the workshop must be tagged with a standardized set of tags for cost tracking, resource management, and organization.

### Required Tags

Every resource MUST include these tags:

| Tag Key | Description | Example Values |
|---------|-------------|----------------|
| `Environment` | Deployment environment | `workshop`, `dev`, `prod` |
| `Lab` | Lab number | `lab1`, `lab2`, `lab3`, `lab4`, `lab5`, `lab6`, `lab7` |
| `Workshop` | Workshop identifier | `serverless-saas` |
| `Owner` | Resource owner/creator | `workshop-participant`, `admin` |
| `CostCenter` | Cost allocation identifier | `workshop`, `training` |

### Tag Implementation in CloudFormation

#### Global Tags (Applied to All Resources)

Use CloudFormation's `Tags` property at the stack level:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: Lab 1 - Basic Serverless Application

# Global tags applied to all resources
Tags:
  Environment: workshop
  Lab: lab1
  Workshop: serverless-saas
  Owner: workshop-participant
  CostCenter: workshop
```

#### Resource-Specific Tags

For resources that need additional tags:

```yaml
Resources:
  ProductTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: ServerlessSaaS-Product-lab1
      Tags:
        - Key: Environment
          Value: workshop
        - Key: Lab
          Value: lab1
        - Key: Workshop
          Value: serverless-saas
        - Key: Owner
          Value: workshop-participant
        - Key: CostCenter
          Value: workshop
        - Key: ResourceType
          Value: database
        - Key: DataClassification
          Value: demo
```

### Tagged Resource Examples

#### Example 1: Lambda Function (Lab 1)

```yaml
ProductServiceFunction:
  Type: AWS::Serverless::Function
  Properties:
    FunctionName: serverless-saas-lab1-product-service
    Handler: product_service.lambda_handler
    Runtime: python3.14
    Tags:
      Environment: workshop
      Lab: lab1
      Workshop: serverless-saas
      Owner: workshop-participant
      CostCenter: workshop
      Service: product-service
```

#### Example 2: DynamoDB Table (Lab 3)

```yaml
ProductTable:
  Type: AWS::DynamoDB::Table
  Properties:
    TableName: Product-pooled-lab3
    BillingMode: PAY_PER_REQUEST
    Tags:
      - Key: Environment
        Value: workshop
      - Key: Lab
        Value: lab3
      - Key: Workshop
        Value: serverless-saas
      - Key: Owner
        Value: workshop-participant
      - Key: CostCenter
        Value: workshop
      - Key: TenantModel
        Value: pooled
      - Key: DataType
        Value: product-catalog
```

#### Example 3: S3 Bucket (Lab 2)

```yaml
AdminAppBucket:
  Type: AWS::S3::Bucket
  Properties:
    BucketName: !Sub 
      - 'serverless-saas-lab2-admin-${ShortId}'
      - ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
    Tags:
      - Key: Environment
        Value: workshop
      - Key: Lab
        Value: lab2
      - Key: Workshop
        Value: serverless-saas
      - Key: Owner
        Value: workshop-participant
      - Key: CostCenter
        Value: workshop
      - Key: Application
        Value: admin-ui
      - Key: ContentType
        Value: static-website
```

#### Example 4: API Gateway (Lab 4)

```yaml
TenantAPI:
  Type: AWS::Serverless::Api
  Properties:
    Name: serverless-saas-tenant-api-lab4
    StageName: prod
    Tags:
      Environment: workshop
      Lab: lab4
      Workshop: serverless-saas
      Owner: workshop-participant
      CostCenter: workshop
      APIType: tenant-api
      IsolationModel: scoped-credentials
```

#### Example 5: Cognito User Pool (Lab 5)

```yaml
TenantUserPool:
  Type: AWS::Cognito::UserPool
  Properties:
    UserPoolName: PooledTenant-ServerlessSaaS-lab5-UserPool
    UserPoolTags:
      Environment: workshop
      Lab: lab5
      Workshop: serverless-saas
      Owner: workshop-participant
      CostCenter: workshop
      UserType: tenant-users
      TenantModel: pooled
```

#### Example 6: IAM Role (Lab 6)

```yaml
AuthorizerExecutionRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: authorizer-execution-role-lab6
    Tags:
      - Key: Environment
        Value: workshop
      - Key: Lab
        Value: lab6
      - Key: Workshop
        Value: serverless-saas
      - Key: Owner
        Value: workshop-participant
      - Key: CostCenter
        Value: workshop
      - Key: Purpose
        Value: lambda-authorizer
      - Key: SecurityLevel
        Value: high
```

#### Example 7: CloudWatch Log Group (Lab 7)

```yaml
CostAttributionLogGroup:
  Type: AWS::Logs::LogGroup
  Properties:
    LogGroupName: /aws/lambda/serverless-saas-lab7-cost-attribution
    RetentionInDays: 60
    Tags:
      - Key: Environment
        Value: workshop
      - Key: Lab
        Value: lab7
      - Key: Workshop
        Value: serverless-saas
      - Key: Owner
        Value: workshop-participant
      - Key: CostCenter
        Value: workshop
      - Key: LogType
        Value: application
      - Key: RetentionPolicy
        Value: 60-days
```

### Tag Validation

Use this AWS CLI command to verify tags on deployed resources:

```
# List all resources with workshop tags
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Workshop,Values=serverless-saas \
  --profile serverless-saas-demo

# List resources for a specific lab
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Lab,Values=lab1 \
  --profile serverless-saas-demo

# Get cost allocation by lab
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Lab \
  --profile serverless-saas-demo
```

### Benefits of Consistent Tagging

1. **Cost Tracking**: Track costs per lab, environment, or cost center
2. **Resource Management**: Easily identify and manage resources by lab
3. **Automation**: Enable automated cleanup and resource lifecycle management
4. **Compliance**: Meet organizational tagging requirements
5. **Reporting**: Generate reports on resource usage and costs
6. **Multi-Tenant Attribution**: Track costs per tenant in pooled models (Lab 7)

## Notes

- Resources using `${AWS::StackName}` in their names should NOT add additional `-lab{N}` suffix since the stack name already includes it
- Tenant-specific resources should include both tenant ID and lab number
- Always verify resource names don't exceed AWS service limits (e.g., S3 bucket names: 63 characters)
- All resources MUST be tagged with the required tags: Environment, Lab, Workshop, Owner, CostCenter
- Additional tags can be added for specific resource types or use cases
