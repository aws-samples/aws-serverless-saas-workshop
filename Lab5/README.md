# Lab 5: Applying Tier-Based Deployment Strategies

## Overview

Lab 5 introduces tier-based deployment strategies for multi-tenant SaaS applications. This lab demonstrates how to deploy different infrastructure configurations based on tenant tiers, implementing both pooled and siloed architectures. You'll learn how to use AWS CodePipeline to automate tenant provisioning and deploy dedicated infrastructure for premium (Platinum) tier tenants.

**Key Concepts:**
- Tier-based tenancy models (pooled vs siloed)
- Automated tenant provisioning with CodePipeline
- Infrastructure as Code with AWS CDK
- Dynamic resource allocation based on tenant tier
- Tenant-specific stack management

**What You'll Build:**
- Shared infrastructure for Basic, Standard, and Premium tier tenants (pooled model)
- Automated CI/CD pipeline for Platinum tier tenant provisioning (siloed model)
- CodeCommit repository for tenant infrastructure templates
- Lambda-triggered pipeline execution on tenant creation
- Tenant-specific CloudFormation stacks for Platinum tenants

## Prerequisites

Before starting this lab, ensure you have:

- **AWS Account**: With appropriate permissions to create resources
- **AWS CLI**: Installed and configured with profile `serverless-saas-demo`
- **SAM CLI**: Installed for serverless application deployment
- **AWS CDK CLI**: Installed for pipeline infrastructure (`npm install -g aws-cdk`)
- **Python 3.14**: Installed and available in your PATH
- **Node.js and npm**: For Angular applications and CDK deployment
- **Git**: For CodeCommit repository operations
- **Completed Labs 1-4**: Understanding of previous concepts (optional but recommended)

**Verify Prerequisites:**
```
aws --version
sam --version
cdk --version
python3 --version
node --version
git --version
```

**Configure AWS Profile:**
```
aws configure --profile serverless-saas-demo
# Enter your AWS Access Key ID, Secret Access Key, and default region (us-east-1)
```

## Architecture

Lab 5 implements a hybrid multi-tenant architecture that supports different deployment models based on tenant tier:

### Shared Stack (Pooled Model)

**For Basic, Standard, and Premium Tier Tenants:**
- **Lambda Functions**: 16 functions for tenant/user management (Python 3.14 runtime)
- **DynamoDB Tables**: 
  - TenantDetails-lab5 (tenant metadata)
  - TenantUserMapping-lab5 (user-tenant associations)
  - TenantStackMapping-lab5 (tenant infrastructure tracking)
  - Settings-lab5 (system configuration)
- **Cognito User Pools**: 
  - PooledTenant (shared user pool for Basic/Standard/Premium tenants)
  - OperationUsers (admin users)
- **Admin API Gateway**: Handles tenant/user management operations
- **CloudFront Distributions**: 3 distributions for Admin, Landing, and Application UIs
- **S3 Buckets**: Static website hosting for all three applications

### Pipeline Stack (Siloed Model)

**For Platinum Tier Tenants:**
- **CodePipeline**: Automated deployment pipeline triggered on tenant creation
- **CodeBuild**: Builds and deploys tenant-specific CloudFormation stacks
- **CodeCommit**: Source repository containing tenant infrastructure templates
- **Lambda Function**: Triggers pipeline execution when Platinum tenant is created
- **S3 Bucket**: Pipeline artifacts with predictable naming (`serverless-saas-pipeline-lab5-artifacts-${ShortId}`)
- **CloudWatch Logs**: Pipeline execution logs with 60-day retention
- **Dedicated Resources per Platinum Tenant**:
  - Dedicated Cognito User Pool
  - Dedicated DynamoDB tables (Products, Orders)
  - Dedicated Lambda functions
  - Dedicated API Gateway

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
│                           │   │                           │
│                           │   │ Per-Tenant Resources:     │
│                           │   │ • Dedicated Cognito Pool  │
│                           │   │ • Dedicated DynamoDB      │
│                           │   │ • Dedicated Lambda        │
│                           │   │ • Dedicated API Gateway   │
└───────────────────────────┘   └───────────────────────────┘
```

### Tenant Provisioning Flow

**For Basic, Standard, and Premium Tiers:**
1. Tenant registers via Landing application
2. Registration service creates tenant in shared Cognito pool
3. Tenant data stored in shared DynamoDB tables
4. Tenant uses shared application infrastructure

**For Platinum Tier:**
1. Tenant registers via Landing application or Admin console
2. Registration service creates tenant record in DynamoDB
3. Lambda function detects Platinum tier and triggers CodePipeline
4. CodePipeline executes:
   - Pulls tenant template from CodeCommit
   - CodeBuild deploys dedicated CloudFormation stack
   - Creates dedicated Cognito pool, DynamoDB tables, Lambda functions, API Gateway
5. TenantStackMapping table updated with stack details
6. Tenant uses dedicated infrastructure

## Deployment Steps

### Step 1: Navigate to Lab 5 Directory

```
cd workshop/Lab5/scripts
```

### Step 2: Deploy Lab 5 Infrastructure

Lab 5 requires deploying both the shared infrastructure and the CI/CD pipeline. Use the `-s` flag to deploy the complete server infrastructure (bootstrap + pipeline) and `-c` flag to deploy the client applications.

```
./deployment.sh -s -c --profile serverless-saas-demo
```

**What This Command Does:**
- **Bootstrap Infrastructure** (`-s` includes bootstrap):
  - Deploys shared services (Tenant Management, User Management, Registration)
  - Creates DynamoDB tables for tenant data
  - Sets up Cognito user pools
  - Deploys Admin API Gateway
  - Creates CloudFront distributions and S3 buckets
- **Pipeline Infrastructure** (`-s` includes pipeline):
  - Bootstraps AWS CDK (required for pipeline deployment)
  - Creates CodeCommit repository (`aws-serverless-saas-workshop`)
  - Pushes workshop code to CodeCommit
  - Deploys CodePipeline stack using CDK
  - Creates Lambda trigger for Platinum tenant provisioning
- **Client Applications** (`-c`):
  - Builds and deploys Admin UI (Angular)
  - Builds and deploys Landing UI (Angular)
  - Builds and deploys Application UI (Angular)
  - Uploads to S3 and invalidates CloudFront caches

**Deployment Time:** Approximately 20-25 minutes

**Expected Output:**
```
==========================================
Lab5 Deployment Complete!
==========================================
Duration: 22m 15s

Application URLs:
  Admin Site: https://<admin-cloudfront-id>.cloudfront.net
  Landing Site: https://<landing-cloudfront-id>.cloudfront.net
  App Site: https://<app-cloudfront-id>.cloudfront.net
  Admin API: https://<api-id>.execute-api.us-east-1.amazonaws.com/prod

Next Steps:
  1. Monitor the pipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab5/view?region=us-east-1
  2. Access the Admin site to create tenants
  3. Check CloudFormation stacks for tenant deployments
  4. Open the application URLs in your browser
  5. To retrieve URLs later: ./geturl.sh --stack-name serverless-saas-shared-lab5 --profile serverless-saas-demo
  6. To clean up resources: ./cleanup.sh --region us-east-1 --profile serverless-saas-demo
```

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
  --stack-name serverless-saas-shared-lab5 \
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
  --query 'TableNames[?contains(@, `lab5`)]'
```
Expected tables:
- ServerlessSaaS-TenantDetails-lab5
- ServerlessSaaS-TenantUserMapping-lab5
- ServerlessSaaS-TenantStackMapping-lab5
- ServerlessSaaS-Settings-lab5

3. **Verify Cognito User Pools:**
```
aws cognito-idp list-user-pools \
  --max-results 20 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'UserPools[?contains(Name, `lab5`)]'
```
Expected pools:
- serverless-saas-pooled-lab5
- serverless-saas-operations-lab5

4. **Verify Lambda Functions:**
```
aws lambda list-functions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `lab5`)].FunctionName'
```
Expected: 16+ Lambda functions for tenant/user management

### Verify Pipeline Infrastructure

1. **Check Pipeline Stack:**
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-pipeline-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```
Expected output: `"CREATE_COMPLETE"`

2. **Verify CodeCommit Repository:**
```
aws codecommit get-repository \
  --repository-name aws-serverless-saas-workshop \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'repositoryMetadata.repositoryName'
```
Expected output: `"aws-serverless-saas-workshop"`

3. **Verify CodePipeline:**
```
aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'pipelineName'
```
Expected output: `"serverless-saas-pipeline-lab5"`

4. **Check Pipeline Artifacts Bucket:**
```
aws s3 ls --profile serverless-saas-demo | grep "serverless-saas-pipeline-lab5-artifacts"
```
Expected: One S3 bucket with predictable naming pattern

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

### Test 1: Create a Basic Tier Tenant (Pooled Model)

1. **Open Landing Site** and click "Sign Up"

2. **Fill in Tenant Details:**
   - Company Name: `TestCompany-Basic`
   - Email: `basic@example.com`
   - Tier: Select "Basic"
   - Complete registration

3. **Verify Pooled Deployment:**
```
# Check tenant record in DynamoDB
aws dynamodb get-item \
  --table-name ServerlessSaaS-TenantDetails-lab5 \
  --key '{"tenantId": {"S": "<tenant-id>"}}' \
  --profile serverless-saas-demo \
  --region us-east-1
```

4. **Verify No Dedicated Stack Created:**
```
# Should return empty - Basic tier uses pooled resources
aws cloudformation list-stacks \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'StackSummaries[?contains(StackName, `<tenant-id>`)]'
```

### Test 2: Create a Platinum Tier Tenant (Siloed Model)

1. **Open Admin Site** and login with admin credentials

2. **Create Platinum Tenant:**
   - Navigate to "Tenants" section
   - Click "Add Tenant"
   - Fill in details:
     - Company Name: `TestCompany-Platinum`
     - Email: `platinum@example.com`
     - Tier: Select "Platinum"
   - Submit

3. **Monitor Pipeline Execution:**
```
# Watch pipeline status
aws codepipeline get-pipeline-state \
  --name serverless-saas-pipeline-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'stageStates[*].[stageName,latestExecution.status]' \
  --output table
```

Or visit the CodePipeline console:
```
https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab5/view?region=us-east-1
```

4. **Verify Dedicated Stack Created:**
```
# Wait for pipeline to complete (5-10 minutes)
# Then check for tenant-specific stack
aws cloudformation describe-stacks \
  --stack-name stack-<tenant-id> \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```
Expected output: `"CREATE_COMPLETE"`

5. **Verify Dedicated Resources:**
```
# Check dedicated Cognito pool
aws cognito-idp list-user-pools \
  --max-results 20 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'UserPools[?contains(Name, `<tenant-id>`)]'

# Check dedicated DynamoDB tables
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'TableNames[?contains(@, `<tenant-id>`)]'

# Check dedicated Lambda functions
aws lambda list-functions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `<tenant-id>`)].FunctionName'
```

6. **Verify TenantStackMapping:**
```
aws dynamodb get-item \
  --table-name ServerlessSaaS-TenantStackMapping-lab5 \
  --key '{"tenantId": {"S": "<tenant-id>"}}' \
  --profile serverless-saas-demo \
  --region us-east-1
```
Expected: Record with stack name and deployment details

### Test 3: Verify Tenant Isolation

1. **Login as Basic Tier Tenant:**
   - Use Basic tenant credentials
   - Create products and orders
   - Note the API Gateway URL (shared)

2. **Login as Platinum Tier Tenant:**
   - Use Platinum tenant credentials
   - Create products and orders
   - Note the API Gateway URL (dedicated)

3. **Verify Data Isolation:**
```
# Basic tier data in shared table
aws dynamodb scan \
  --table-name ServerlessSaaS-Product-lab5 \
  --filter-expression "tenantId = :tid" \
  --expression-attribute-values '{":tid":{"S":"<basic-tenant-id>"}}' \
  --profile serverless-saas-demo \
  --region us-east-1

# Platinum tier data in dedicated table
aws dynamodb scan \
  --table-name Product-<platinum-tenant-id> \
  --profile serverless-saas-demo \
  --region us-east-1
```

### Test 4: Verify Pipeline Trigger

1. **Check Lambda Trigger Function:**
```
aws lambda get-function \
  --function-name TenantProvisioningTrigger-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1
```

2. **View CloudWatch Logs:**
```
aws logs tail /aws/lambda/TenantProvisioningTrigger-lab5 \
  --follow \
  --profile serverless-saas-demo \
  --region us-east-1
```

3. **Verify Pipeline Invocations:**
```
aws codepipeline list-pipeline-executions \
  --pipeline-name serverless-saas-pipeline-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --max-items 5
```

## Troubleshooting

### Issue 1: CDK Bootstrap Fails

**Symptom:**
```
Error: This stack uses assets, so the toolkit stack must be deployed to the environment
```

**Solution:**
```
# Manually bootstrap CDK
cdk bootstrap aws://<account-id>/us-east-1 --profile serverless-saas-demo

# Then retry deployment
cd workshop/Lab5/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

### Issue 2: CodeCommit Push Fails

**Symptom:**
```
fatal: unable to access 'codecommit::us-east-1://aws-serverless-saas-workshop/': 
The requested URL returned error: 403
```

**Solution:**
```
# Install git-remote-codecommit
pip install git-remote-codecommit

# Verify AWS credentials
aws sts get-caller-identity --profile serverless-saas-demo

# Retry deployment
./deployment.sh -s -c --profile serverless-saas-demo
```

### Issue 3: Pipeline Fails to Trigger

**Symptom:**
Platinum tenant created but pipeline doesn't execute

**Solution:**
```
# Check Lambda trigger function logs
aws logs tail /aws/lambda/TenantProvisioningTrigger-lab5 \
  --follow \
  --profile serverless-saas-demo \
  --region us-east-1

# Manually trigger pipeline
aws codepipeline start-pipeline-execution \
  --name serverless-saas-pipeline-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1
```

### Issue 4: CodeBuild Fails with Python Version Error

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
cd workshop/Lab5/server/TenantPipeline
# Edit buildspec.yml to use python: 3.11
git add buildspec.yml
git commit -m "Update Python version to 3.11"
git push cc main
```

### Issue 5: Tenant Stack Deployment Fails

**Symptom:**
Pipeline succeeds but tenant stack shows `CREATE_FAILED`

**Solution:**
```
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name stack-<tenant-id> \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Common issues:
# 1. Resource limits exceeded - request limit increase
# 2. IAM permissions - verify CodeBuild role has necessary permissions
# 3. Resource naming conflicts - ensure unique tenant IDs

# Delete failed stack and retry
aws cloudformation delete-stack \
  --stack-name stack-<tenant-id> \
  --profile serverless-saas-demo \
  --region us-east-1

# Trigger pipeline again from Admin UI
```

### Issue 6: CloudFront Cache Not Invalidated

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

### Issue 7: DynamoDB Table Not Found

**Symptom:**
```
ResourceNotFoundException: Requested resource not found: Table: ServerlessSaaS-TenantDetails-lab5
```

**Solution:**
```
# Verify shared stack deployed successfully
aws cloudformation describe-stacks \
  --stack-name serverless-saas-shared-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1

# If stack failed, check events
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-shared-lab5 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Redeploy if necessary
cd workshop/Lab5/scripts
./deployment.sh -b --profile serverless-saas-demo
```

## Cleanup

To remove all Lab 5 resources and avoid ongoing charges:

```
cd workshop/Lab5/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab5 --profile serverless-saas-demo
```

**What Gets Deleted:**
1. **Tenant Stacks**: All Platinum tier tenant-specific CloudFormation stacks
2. **Pipeline Stack**: CodePipeline, CodeBuild, and associated resources
3. **Shared Stack**: Shared services, Lambda functions, DynamoDB tables, Cognito pools
4. **CodeCommit Repository**: aws-serverless-saas-workshop repository
5. **S3 Buckets**: Pipeline artifacts, client application hosting buckets
6. **CloudWatch Logs**: All log groups with 60-day retention
7. **CloudFront Distributions**: All three distributions (Admin, Landing, App)

**Cleanup Time:** Approximately 15-20 minutes

**Manual Cleanup (if needed):**

If automated cleanup fails, manually delete resources:

```
# Delete tenant stacks
aws cloudformation delete-stack --stack-name stack-<tenant-id> --profile serverless-saas-demo --region us-east-1

# Delete pipeline stack
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab5 --profile serverless-saas-demo --region us-east-1

# Delete shared stack
aws cloudformation delete-stack --stack-name serverless-saas-shared-lab5 --profile serverless-saas-demo --region us-east-1

# Delete CodeCommit repository
aws codecommit delete-repository --repository-name aws-serverless-saas-workshop --profile serverless-saas-demo --region us-east-1

# Empty and delete S3 buckets
aws s3 rm s3://<bucket-name> --recursive --profile serverless-saas-demo --region us-east-1
aws s3 rb s3://<bucket-name> --profile serverless-saas-demo --region us-east-1
```

## Key Concepts

### Tier-Based Tenancy

**Pooled Model (Basic, Standard, Premium):**
- **Shared Resources**: All tenants share the same infrastructure
- **Cost Efficiency**: Lower per-tenant cost due to resource sharing
- **Scalability**: Easier to scale horizontally
- **Isolation**: Logical isolation through tenant ID partitioning
- **Use Case**: Cost-sensitive tenants with standard requirements

**Siloed Model (Platinum):**
- **Dedicated Resources**: Each tenant has dedicated infrastructure
- **Performance**: Guaranteed performance without noisy neighbor issues
- **Compliance**: Meets strict regulatory requirements
- **Customization**: Tenant-specific configurations possible
- **Use Case**: Enterprise customers with compliance or performance requirements

### CodePipeline Automation

**Pipeline Stages:**
1. **Source**: Pulls tenant template from CodeCommit
2. **Build**: CodeBuild executes SAM deployment
3. **Deploy**: CloudFormation creates tenant-specific stack

**Benefits:**
- **Consistency**: Every Platinum tenant gets identical infrastructure
- **Speed**: Automated provisioning in 5-10 minutes
- **Auditability**: Complete deployment history in CodePipeline
- **Rollback**: Easy rollback to previous versions

### Infrastructure as Code with CDK

**CDK Advantages:**
- **Type Safety**: TypeScript provides compile-time validation
- **Reusability**: Constructs can be shared across projects
- **Abstraction**: Higher-level abstractions than CloudFormation
- **Testing**: Unit tests for infrastructure code

**CDK vs SAM:**
- **SAM**: Simpler, focused on serverless applications
- **CDK**: More powerful, supports all AWS resources
- **Lab 5 Uses Both**: SAM for application stacks, CDK for pipeline infrastructure

### Tenant Stack Mapping

The TenantStackMapping table tracks tenant infrastructure:

```json
{
  "tenantId": "abc123",
  "stackName": "stack-abc123",
  "applyLatestRelease": true,
  "codeCommitId": "commit-hash",
  "lastDeployedAt": "2025-01-25T10:30:00Z"
}
```

**Use Cases:**
- Track which tenants have dedicated infrastructure
- Manage infrastructure updates across tenants
- Audit tenant provisioning history
- Support tenant-specific rollbacks

### Dynamic Resource Allocation

**Decision Logic:**
```python
if tenant_tier == "Platinum":
    trigger_pipeline(tenant_id)
    create_dedicated_stack(tenant_id)
else:
    use_shared_resources()
    add_to_pooled_cognito(tenant_id)
```

**Considerations:**
- **Cost**: Platinum tier costs more due to dedicated resources
- **Provisioning Time**: Platinum tenants wait 5-10 minutes for infrastructure
- **Management**: More stacks to manage and monitor
- **Flexibility**: Easy to move tenants between tiers by redeploying

## Next Steps

After completing Lab 5, you can:

1. **Proceed to Lab 6**: Learn about tenant throttling and API quotas
   - Implement API Gateway usage plans
   - Configure per-tenant API keys
   - Set up rate limiting and burst limits

2. **Experiment with Tier Migration**:
   - Upgrade a Basic tenant to Platinum
   - Observe pipeline execution and stack creation
   - Migrate data from pooled to siloed tables

3. **Customize Pipeline**:
   - Modify buildspec.yml for custom build steps
   - Add approval stages to pipeline
   - Implement blue/green deployments

4. **Monitor Pipeline Executions**:
   - Set up CloudWatch alarms for pipeline failures
   - Create dashboards for tenant provisioning metrics
   - Implement SNS notifications for pipeline events

5. **Explore Cost Implications**:
   - Compare costs between pooled and siloed models
   - Analyze per-tenant infrastructure costs
   - Optimize resource allocation based on usage

## Additional Resources

- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [Multi-Tenant SaaS on AWS](https://aws.amazon.com/solutions/implementations/saas-identity-and-isolation-with-amazon-cognito/)
- [SaaS Tenant Isolation Strategies](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-isolation.html)
- [Workshop Guide](https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US/lab5)

## Summary

In Lab 5, you learned how to implement tier-based deployment strategies for multi-tenant SaaS applications. You deployed a hybrid architecture supporting both pooled (Basic, Standard, Premium) and siloed (Platinum) tenancy models. You automated Platinum tenant provisioning using CodePipeline, CodeCommit, and CodeBuild, demonstrating how to dynamically allocate infrastructure based on tenant tier. This approach provides flexibility to meet diverse customer requirements while optimizing costs and maintaining operational efficiency.

**Key Takeaways:**
- Tier-based tenancy allows different deployment models for different customer segments
- CodePipeline automates infrastructure provisioning for premium tenants
- CDK provides powerful infrastructure as code capabilities
- Tenant stack mapping enables tracking and management of tenant-specific infrastructure
- Hybrid architectures balance cost efficiency with performance and compliance requirements
