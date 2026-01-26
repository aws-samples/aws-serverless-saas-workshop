# AWS Serverless SaaS Workshop - Complete Deployment Guide

## Overview

This guide provides comprehensive deployment instructions for all labs in the AWS Serverless SaaS Workshop. It covers both global shared resources and lab-specific configurations to ensure successful, conflict-free deployments.

## Table of Contents

1. [Global Shared Resources](#global-shared-resources)
2. [Prerequisites](#prerequisites)
3. [Lab-Specific Deployment](#lab-specific-deployment)
4. [Common Issues and Solutions](#common-issues-and-solutions)
5. [Cleanup Procedures](#cleanup-procedures)

---

## Global Shared Resources

### Resources Shared Across ALL Labs

These resources are intentionally shared across all labs and should **NOT** have a lab suffix:

#### 1. API Gateway CloudWatch Role

**Resource Type:** `AWS::IAM::Role` + `AWS::ApiGateway::Account`

**Role Name:** `apigateway-cloudwatch-publish-role` (NO lab suffix, NO region suffix)

**Why Shared:**
- `AWS::ApiGateway::Account` is a **singleton resource** - only ONE can exist per AWS account per region
- It sets the CloudWatch logging role for ALL API Gateways in that region
- This role is shared across all labs to avoid conflicts

**Configuration:**
```yaml
ApiGatewayCloudWatchLogRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: apigateway-cloudwatch-publish-role  # No lab suffix, no region suffix
    ManagedPolicyArns:
      - arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs
    AssumeRolePolicyDocument:
      Version: 2012-10-17
      Statement:
        - Effect: Allow
          Principal:
            Service:
              - apigateway.amazonaws.com
          Action:
            - sts:AssumeRole

ApiGatewayAttachCloudwatchLogArn:
  Type: AWS::ApiGateway::Account  # Singleton resource
  Properties:
    CloudWatchRoleArn: !GetAtt ApiGatewayCloudWatchLogRole.Arn
```

**Important Notes:**
- If this role already exists from a previous lab deployment, CloudFormation will fail with a role name conflict
- The role should be created once and reused across all labs
- When cleaning up labs, do NOT delete this role if other labs are still deployed

#### 2. CI/CD Pipeline Stack

**Stack Name:** `serverless-saas-pipeline` (NO lab suffix)

**Why Shared:** Shared CI/CD infrastructure used by all labs for tenant provisioning

#### 3. CDK Bootstrap Stack

**Stack Name:** `CDKToolkit` (NO lab suffix)

**Why Shared:** AWS CDK bootstrap stack required for CDK deployments across all labs

---

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.x or later)
   ```
   aws --version
   ```

2. **AWS SAM CLI** (v1.x or later)
   ```
   sam --version
   ```

3. **Python** (3.9 or later)
   ```
   python3 --version
   ```

4. **Node.js** (v18.x or later)
   ```
   node --version
   ```

5. **Git**
   ```
   git --version
   ```

### AWS Account Setup

1. **Configure AWS Credentials:**
   ```
   aws configure --profile <your-profile-name>
   ```

2. **Verify Access:**
   ```
   aws sts get-caller-identity --profile <your-profile-name>
   ```

3. **Bootstrap SAM (if not already done):**
   ```
   sam init --bootstrap
   ```

### First-Time Setup

If this is your first lab deployment, the `apigateway-cloudwatch-publish-role` will be created automatically. For subsequent labs, this role will already exist and be reused.

---

## Lab-Specific Deployment

### General Deployment Pattern

Each lab follows this standard deployment pattern:

```
cd Lab{N}/scripts
./deployment.sh
```

### Lab 1: Basic Multi-Tenant Architecture

**Stack Name:** `serverless-saas-workshop-shared-lab1`

**Key Resources:**
- Lambda functions: `serverless-saas-lab1-*`
- DynamoDB tables: `ServerlessSaaS-*-lab1`
- S3 buckets: `serverless-saas-lab1-*-${ShortId}`
- Cognito pools: `*-ServerlessSaaS-lab1-UserPool`

**Deployment:**
```
cd Lab1/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

### Lab 2: Tenant Isolation

**Stack Name:** `serverless-saas-workshop-shared-lab2`

**Key Resources:**
- Lambda functions: `serverless-saas-lab2-*`
- DynamoDB tables: `ServerlessSaaS-*-lab2`
- IAM roles: `*-lab2-${AWS::Region}`

**Deployment:**
```
cd Lab2/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

### Lab 3: Tenant Onboarding

**Stack Name:** `serverless-saas-workshop-shared-lab3`

**Key Resources:**
- Lambda functions: `serverless-saas-lab3-*`
- DynamoDB tables: `ServerlessSaaS-*-lab3`
- Tenant stacks: `stack-{tenantId}`

**Deployment:**
```
cd Lab3/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

### Lab 4: Tenant Deployment Pipeline

**Stack Name:** `serverless-saas-workshop-shared-lab4`

**Key Resources:**
- Lambda functions: `serverless-saas-lab4-*`
- CodePipeline: `serverless-saas-pipeline` (shared)
- DynamoDB tables: `ServerlessSaaS-*-lab4`

**Deployment:**
```
cd Lab4/scripts
./deployment.sh
```

**Estimated Time:** 20-25 minutes

### Lab 5: Tenant Tiering

**Stack Name:** `serverless-saas-workshop-shared-lab5`

**Key Resources:**
- Lambda functions: `serverless-saas-lab5-*`
- API Keys: `serverless-saas-lab5-{tier}-apikey`
- Usage Plans: `serverless-saas-lab5-{tier}-plan`
- DynamoDB tables: `ServerlessSaaS-*-lab5`

**Deployment:**
```
cd Lab5/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

**Special Notes:**
- Introduces API Gateway usage plans and API keys
- Each tier (Basic, Standard, Premium, Platinum) has its own API key and usage plan

### Lab 6: Tenant Throttling

**Stack Name:** `serverless-saas-workshop-shared-lab6`

**Key Resources:**
- Lambda functions: `serverless-saas-lab6-*`
- API Keys: `serverless-saas-lab6-{tier}-apikey`
- Usage Plans: `serverless-saas-lab6-{tier}-plan` (with throttling limits)
- DynamoDB tables: `ServerlessSaaS-*-lab6`

**Deployment:**
```
cd Lab6/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

**Special Notes:**
- Builds on Lab 5 with added throttling configurations
- Different throttling limits per tier:
  - Basic: 10 requests/second, 100 burst
  - Standard: 50 requests/second, 500 burst
  - Premium: 100 requests/second, 1000 burst
  - Platinum: 500 requests/second, 5000 burst

### Lab 7: Advanced Features

**Stack Name:** `serverless-saas-workshop-shared-lab7`

**Key Resources:**
- Lambda functions: `serverless-saas-lab7-*`
- DynamoDB tables: `ServerlessSaaS-*-lab7`

**Deployment:**
```
cd Lab7/scripts
./deployment.sh
```

**Estimated Time:** 15-20 minutes

---

## Common Issues and Solutions

### Issue 1: API Gateway CloudWatch Role Already Exists

**Error Message:**
```
CREATE_FAILED: ApiGatewayCloudWatchLogRole
Role with name apigateway-cloudwatch-publish-role already exists
```

**Solution:**
This is expected behavior when deploying a second or subsequent lab. The role is shared across all labs.

**Fix Options:**

**Option A: Reuse Existing Role (Recommended)**

Modify the CloudFormation template to conditionally create the role:

```yaml
Conditions:
  CreateApiGatewayRole: !Equals [!Ref CreateApiGatewayRoleParameter, 'true']

Resources:
  ApiGatewayCloudWatchLogRole:
    Type: AWS::IAM::Role
    Condition: CreateApiGatewayRole
    Properties:
      RoleName: apigateway-cloudwatch-publish-role
      # ... rest of configuration
```

**Option B: Reference Existing Role**

If the role already exists, reference it by ARN instead of creating it:

```yaml
Parameters:
  ExistingApiGatewayRoleArn:
    Type: String
    Default: ""
    Description: "ARN of existing API Gateway CloudWatch role (leave empty to create new)"

Conditions:
  UseExistingRole: !Not [!Equals [!Ref ExistingApiGatewayRoleArn, ""]]

Resources:
  ApiGatewayAttachCloudwatchLogArn:
    Type: AWS::ApiGateway::Account
    Properties:
      CloudWatchRoleArn: !If 
        - UseExistingRole
        - !Ref ExistingApiGatewayRoleArn
        - !GetAtt ApiGatewayCloudWatchLogRole.Arn
```

### Issue 2: S3 Bucket Name Already Exists

**Error Message:**
```
CREATE_FAILED: Bucket name already exists
```

**Solution:**
S3 bucket names must be globally unique. The workshop uses ShortId to ensure uniqueness:

```yaml
BucketName: !Sub 
  - 'serverless-saas-lab{N}-{bucket-type}-${ShortId}'
  - ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

This should prevent conflicts, but if it occurs:
1. Delete the existing bucket (if safe to do so)
2. Or modify the bucket name pattern in the template

### Issue 3: DynamoDB Table Already Exists

**Error Message:**
```
CREATE_FAILED: Table ServerlessSaaS-TenantDetails-lab{N} already exists
```

**Solution:**
Ensure you're using the correct lab number suffix. Each lab should have unique table names:
- Lab 1: `ServerlessSaaS-TenantDetails-lab1`
- Lab 2: `ServerlessSaaS-TenantDetails-lab2`
- etc.

### Issue 4: IAM Role Name Conflict

**Error Message:**
```
CREATE_FAILED: Role with name {role-name} already exists
```

**Solution:**
Verify all IAM roles have the correct lab suffix:
- Regional roles: `{role-name}-lab{N}-${AWS::Region}`
- Global roles: `{role-name}-lab{N}`
- Shared role (API Gateway): `apigateway-cloudwatch-publish-role` (no suffix)

### Issue 5: Stack Rollback

**Error Message:**
```
ROLLBACK_IN_PROGRESS: The following resource(s) failed to create
```

**Solution:**
1. Check CloudFormation events for specific error:
   ```
   aws cloudformation describe-stack-events \
     --stack-name serverless-saas-workshop-shared-lab{N} \
     --region us-east-1 \
     --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
   ```

2. Delete the failed stack:
   ```
   aws cloudformation delete-stack \
     --stack-name serverless-saas-workshop-shared-lab{N} \
     --region us-east-1
   ```

3. Fix the issue in the template

4. Redeploy

### Issue 6: Python Syntax Errors

**Error Message:**
```
Validating server code using pylint
ERROR: Syntax error in {file}.py
```

**Solution:**
1. Check Python file for syntax errors
2. Common issues:
   - Incorrect indentation
   - Missing colons
   - Typos in keywords (e.g., `iif` instead of `if`)
3. Fix and redeploy

---

## Cleanup Procedures

### Cleaning Up Individual Labs

Each lab includes a cleanup script:

```
cd Lab{N}/scripts
./cleanup.sh
```

**What Gets Deleted:**
- CloudFormation stacks
- Lambda functions
- DynamoDB tables
- S3 buckets (and their contents)
- Cognito user pools
- IAM roles (except shared API Gateway role)
- CloudWatch log groups

### Cleaning Up All Labs

To clean up all labs at once:

```
# Lab 1
cd Lab1/scripts && ./cleanup.sh

# Lab 2
cd ../../Lab2/scripts && ./cleanup.sh

# Lab 3
cd ../../Lab3/scripts && ./cleanup.sh

# Lab 4
cd ../../Lab4/scripts && ./cleanup.sh

# Lab 5
cd ../../Lab5/scripts && ./cleanup.sh

# Lab 6
cd ../../Lab6/scripts && ./cleanup.sh

# Lab 7
cd ../../Lab7/scripts && ./cleanup.sh
```

### Cleaning Up Shared Resources

**IMPORTANT:** Only delete shared resources after ALL labs have been cleaned up.

#### Delete API Gateway CloudWatch Role

```
aws iam delete-role --role-name apigateway-cloudwatch-publish-role
```

#### Delete CI/CD Pipeline Stack

```
aws cloudformation delete-stack --stack-name serverless-saas-pipeline
```

#### Delete CDK Bootstrap Stack (Optional)

**WARNING:** Only delete if you're not using CDK for other projects!

```
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Verification

Verify all resources are deleted:

```
# Check CloudFormation stacks
aws cloudformation list-stacks \
  --query 'StackSummaries[?contains(StackName, `serverless-saas`) && StackStatus!=`DELETE_COMPLETE`].StackName'

# Check Lambda functions
aws lambda list-functions \
  --query "Functions[?contains(FunctionName, 'serverless-saas')].FunctionName"

# Check DynamoDB tables
aws dynamodb list-tables \
  --query "TableNames[?contains(@, 'ServerlessSaaS')]"

# Check S3 buckets
aws s3 ls | grep serverless-saas

# Check Cognito user pools
aws cognito-idp list-user-pools --max-results 60 \
  --query "UserPools[?contains(Name, 'ServerlessSaaS')].Name"
```

---

## Best Practices

### 1. Deploy Labs Sequentially

Deploy labs in order (Lab 1 → Lab 2 → Lab 3, etc.) to understand the progression of concepts.

### 2. Use Screen Sessions for Long Deployments

```
cd Lab{N}/scripts
./deploy-with-screen.sh
```

This allows deployments to continue even if your terminal disconnects.

### 3. Monitor CloudFormation Events

```
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-workshop-shared-lab{N} \
  --region us-east-1 \
  --max-items 20
```

### 4. Save Deployment Outputs

Each lab deployment outputs important values (API URLs, Cognito pool IDs, etc.). Save these for reference:

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-shared-lab{N} \
  --region us-east-1 \
  --query 'Stacks[0].Outputs' > lab{N}-outputs.json
```

### 5. Test Before Moving to Next Lab

Verify each lab works correctly before proceeding to the next one.

### 6. Keep Labs Isolated

Each lab is designed to be independent. You can have multiple labs deployed simultaneously without conflicts (thanks to the naming convention).

### 7. Custom Resources Best Practice

**Always include `ServiceTimeout: 300` in custom resource definitions** to prevent premature timeouts during CloudFormation operations.

**Why This Matters:**
- Custom resources execute Lambda functions that may need time to complete operations (DynamoDB writes, API calls, etc.)
- Default CloudFormation timeout for custom resources can be too short
- A 300-second (5-minute) timeout provides adequate time for most operations
- Prevents deployment failures due to timeout issues

**Example:**
```yaml
UpdateSettingsTable:
  Type: Custom::UpdateSettingsTable
  Properties:
    ServiceToken: !Ref UpdateSettingsTableFunctionArn
    SettingsTableName: !Ref ServerlessSaaSSettingsTableName
    cognitoUserPoolId: !Ref CognitoUserPoolId
    cognitoUserPoolClientId: !Ref CognitoUserPoolClientId
    ServiceTimeout: 300  # Always include this

UpdateTenantStackMap:
  Type: Custom::UpdateTenantStackMap
  Properties:
    ServiceToken: !Ref UpdateTenantStackMapTableFunctionArn
    TenantStackMappingTableName: !Ref TenantStackMappingTableName
    ServiceTimeout: 300  # Always include this
```

**Common Custom Resource Operations:**
- Initializing DynamoDB tables with configuration data
- Updating API Gateway usage plans
- Configuring tenant-specific resources
- Cross-stack resource coordination

---

## Troubleshooting Commands

### Check Stack Status

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-shared-lab{N} \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

### View Stack Events

```
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-workshop-shared-lab{N} \
  --region us-east-1 \
  --max-items 50
```

### Check Lambda Function Logs

```
aws logs tail /aws/lambda/serverless-saas-lab{N}-{function-name} --follow
```

### Test API Gateway Endpoint

```
curl -X GET https://{api-id}.execute-api.us-east-1.amazonaws.com/prod/tenants \
  -H "x-api-key: {api-key}"
```

### Check DynamoDB Table

```
aws dynamodb scan --table-name ServerlessSaaS-TenantDetails-lab{N} --limit 10
```

---

## Additional Resources

- [AWS Serverless SaaS Workshop](https://github.com/aws-samples/aws-serverless-saas-workshop)
- [Resource Naming Convention](./RESOURCE_NAMING_CONVENTION.md)
- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)

---

## Support

For issues or questions:
1. Check the [Common Issues](#common-issues-and-solutions) section
2. Review lab-specific troubleshooting guides (e.g., `Lab5/TROUBLESHOOTING.md`)
3. Check CloudFormation stack events for detailed error messages
4. Open an issue on the GitHub repository

---

## Version History

- **v1.0** - Initial comprehensive deployment guide
- Covers Labs 1-7
- Includes global shared resources documentation
- Provides cleanup procedures and troubleshooting

---

**Last Updated:** January 2026
