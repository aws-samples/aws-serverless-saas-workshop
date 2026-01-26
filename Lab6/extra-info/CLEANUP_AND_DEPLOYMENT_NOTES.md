# Lab6 Cleanup and Deployment Notes

## Deployment Script (`deployment.sh`)

### Key Features

1. **Lab6 Stack References**: All CloudFormation operations correctly reference Lab6 stacks:
   - `serverless-saas-workshop-shared-lab6`
   - `serverless-saas-workshop-tenant-lab6`

2. **Client Deployment with Fallback**:
   - Creates Lab6-specific environment files with correct API URLs
   - Attempts to build client apps with npm
   - **Fallback mechanism**: If build fails (Node.js compatibility), uses pre-built files from Lab5
   - This is intentional - Lab5 and Lab6 client code is identical, so pre-built files work perfectly

3. **S3 Bucket Targets**: Correctly uploads to Lab6 buckets:
   - `$ADMIN_BUCKET` (from Lab6 stack output)
   - `$LANDING_BUCKET` (from Lab6 stack output)
   - `$APP_BUCKET` (from Lab6 stack output)

### Why Lab5 Pre-built Files?

The deployment script references Lab5 pre-built files as a **fallback only**:

```
if [ -d "../../Lab5/client/Landing/dist" ] && [ -d "../../Lab5/client/Admin/dist" ] && [ -d "../../Lab5/client/Application/dist" ]; then
  USE_PREBUILT=true
fi
```

This is **correct behavior** because:
- Lab6 client code is identical to Lab5
- Node.js v25+ has compatibility issues with Angular build
- Pre-built files from Lab5 work perfectly for Lab6
- Files are uploaded to Lab6 S3 buckets with Lab6 environment configuration

## Cleanup Script (`cleanup.sh`)

### Cleanup Steps (in order)

1. **Tenant Stacks**: Deletes all `stack-*` tenant stacks
2. **S3 Buckets Identification**: Gets Lab6 bucket names from CloudFormation outputs
3. **S3 Buckets Emptying**: Empties all Lab6 application buckets (handles versioning)
4. **Shared Stack**: Deletes `serverless-saas-workshop-shared-lab6`
5. **Tenant Template Stack**: Deletes `serverless-saas-workshop-tenant-lab6`
6. **Pipeline Artifacts Bucket**: Identifies `serverless-saas-pipeline-lab6-pipelineartifactsbucket-*`
7. **Pipeline Artifacts Emptying**: Empties pipeline artifacts bucket
8. **Pipeline Stack**: Deletes `serverless-saas-pipeline-lab6`
9. **SAM Artifacts**: Cleans up SAM-managed buckets with `lab6` in name
10. **Cognito User Pools**: Deletes all Lab6 Cognito pools (including domains)
11. **Verification**: Checks for remaining Lab6 resources

### Key Features

- **User Confirmation**: Prompts before starting cleanup
- **Graceful Handling**: Continues even if resources don't exist
- **Versioned Buckets**: Properly handles S3 buckets with versioning enabled
- **Pipeline Cleanup**: Includes pipeline stack and artifacts (added in latest update)
- **Comprehensive Verification**: Final check for any remaining Lab6 resources

## Resource Naming Convention

All Lab6 resources follow the naming convention from `RESOURCE_NAMING_CONVENTION.md`:

- **S3 Buckets**: `serverless-saas-lab6-{type}-${ShortId}`
- **Lambda Functions**: `serverless-saas-lab6-{function-name}`
- **DynamoDB Tables**: `ServerlessSaaS-{TableName}-lab6`
- **IAM Roles**: `{role-name}-lab6`
- **Cognito Pools**: `{PoolType}-ServerlessSaaS-lab6-UserPool`
- **Cognito Domains**: `serverless-saas-lab6-{type}-${ShortId}`
- **CloudFormation Stacks**: `serverless-saas-workshop-{type}-lab6`
- **Pipeline Stack**: `serverless-saas-pipeline-lab6`

## Common Issues and Solutions

### Issue: "Access Denied" on CloudFront URLs

**Cause**: S3 buckets are empty (client files not deployed)

**Solution**: Run deployment script which automatically deploys client files

### Issue: Node.js Build Fails

**Cause**: Node.js v25+ has compatibility issues with Angular

**Solution**: Script automatically falls back to Lab5 pre-built files (this is expected behavior)

### Issue: Pipeline Stack Not Found During Cleanup

**Cause**: Pipeline may not have been deployed

**Solution**: Cleanup script handles this gracefully and continues

### Issue: Bucket Still Has Objects After Emptying

**Cause**: Versioned buckets require special handling

**Solution**: Cleanup script handles versioning by deleting all versions and delete markers

## Deployment Commands

```
# Standard deployment (server + client)
cd Lab6/scripts
./deployment.sh

# Using screen for long deployments
./deploy-with-screen.sh
```

## Cleanup Commands

```
# Interactive cleanup with confirmation
cd Lab6/scripts
./cleanup.sh

# Follow prompts and type 'yes' to confirm
```

## Verification

After deployment, verify:
1. CloudFormation stacks exist: `serverless-saas-workshop-shared-lab6`, `serverless-saas-workshop-tenant-lab6`
2. S3 buckets contain client files
3. CloudFront URLs are accessible (may take a few minutes to propagate)
4. DynamoDB tables exist with `-lab6` suffix

After cleanup, verify:
1. No Lab6 CloudFormation stacks remain
2. No Lab6 S3 buckets remain
3. No Lab6 DynamoDB tables remain
4. No Lab6 Cognito User Pools remain
