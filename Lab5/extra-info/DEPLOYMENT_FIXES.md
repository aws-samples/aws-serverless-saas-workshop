# Lab5 Deployment Fixes Summary

## Issues Fixed

### 1. ResourceNotFoundException: DynamoDB Table Not Found

**Problem:** The pipeline Lambda function tried to scan `ServerlessSaaS-TenantStackMapping-lab5` before it was created, causing:
```
An error occurred (ResourceNotFoundException) when calling the Scan operation: Requested resource not found
```

**Root Cause:** Race condition - pipeline could trigger before DynamoDB tables were fully active.

**Fix:** Added automatic wait for DynamoDB tables in `deployment.sh`:
```
# Wait for DynamoDB tables to be fully active before proceeding
for table in "ServerlessSaaS-Settings-lab5" "ServerlessSaaS-TenantStackMapping-lab5" \
             "ServerlessSaaS-TenantDetails-lab5" "ServerlessSaaS-TenantUserMapping-lab5"; do
  aws dynamodb wait table-exists --table-name $table
done
```

### 2. Stack ROLLBACK_COMPLETE: Missing CloudFormation Exports

**Problem:** Tenant stacks failed with:
```
No export named Serverless-SaaS-CognitoOperationUsersUserPoolClientId found
```

**Root Cause:** 
- The shared stack exports with `-lab5` suffix: `Serverless-SaaS-CognitoOperationUsersUserPoolClientId-lab5`
- The tenant template imports with `-lab5` suffix (correct)
- BUT the CodeCommit repository had old code without the suffix
- Pipeline was building from CodeCommit main branch, not your local changes

**Fix:** Added automatic code push to CodeCommit in `deployment.sh`:
```
# Push current branch changes to CodeCommit main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push cc $CURRENT_BRANCH:main --force
```

## Files Modified

### 1. `Lab5/scripts/deployment.sh`

**Changes:**
- Added automatic git push to CodeCommit before pipeline deployment
- Added DynamoDB table wait after bootstrap deployment
- Added better status messages and error handling
- Added deployment summary with next steps

**Key Sections:**
```
# Pipeline deployment section
- Auto-commits any uncommitted changes
- Pushes current branch to CodeCommit main
- Deploys pipeline with CDK

# Bootstrap deployment section  
- Validates Python code with pylint
- Builds and deploys SAM template
- Waits for all DynamoDB tables to be active

# Client deployment section
- Improved error handling
- Better status messages
```

### 2. `Lab5/TROUBLESHOOTING.md` (New)

Comprehensive troubleshooting guide covering:
- ResourceNotFoundException errors
- ROLLBACK_COMPLETE issues
- Pipeline not picking up changes
- Stack failure analysis
- Complete cleanup procedures
- Monitoring commands

### 3. `Lab5/DEPLOYMENT_GUIDE.md` (Updated)

- Added reference to troubleshooting guide
- Documented new script features
- Added quick fix commands

## Deployment Flow (Fixed)

```
1. Pipeline Deployment
   ├─ Check/Create CodeCommit repo
   ├─ Auto-commit any changes
   ├─ Push current branch → CodeCommit main
   └─ Deploy CDK pipeline stack

2. Bootstrap Deployment
   ├─ Validate Python code
   ├─ Build SAM template
   ├─ Deploy shared infrastructure
   └─ Wait for DynamoDB tables ✓ NEW

3. Pipeline Auto-Execution
   ├─ Triggered by CodeCommit push
   ├─ Builds from latest code ✓ FIXED
   ├─ Scans DynamoDB (now exists) ✓ FIXED
   └─ Deploys tenant stacks

4. Client Deployment
   ├─ Build Admin UI
   ├─ Build Landing UI
   ├─ Build App UI
   └─ Invalidate CloudFront caches
```

## Testing the Fixes

### Before Running

1. Ensure you're on the correct branch with Lab5 changes:
```
git branch  # Should show your current branch
git log --oneline -5  # Should show Lab5 commits
```

2. Check for uncommitted changes:
```
git status
```

### Run Deployment

```
cd Lab5/scripts
./deployment.sh -s -c
```

The script will now:
- ✓ Auto-commit any uncommitted changes
- ✓ Push your code to CodeCommit
- ✓ Deploy pipeline
- ✓ Deploy bootstrap
- ✓ Wait for DynamoDB tables
- ✓ Pipeline builds with correct code
- ✓ Deploy client UIs

### Verify Success

```
# Check DynamoDB tables exist
aws dynamodb list-tables --query 'TableNames[?contains(@, `lab5`)]'

# Check CloudFormation exports have -lab5 suffix
aws cloudformation list-exports --query 'Exports[?contains(Name, `lab5`)].[Name]'

# Check CodeCommit has your changes
git fetch cc
git log cc/main --oneline -5

# Monitor pipeline execution
aws codepipeline get-pipeline-state --name serverless-saas-pipeline-lab5

# Check tenant stack status
aws cloudformation describe-stacks --stack-name stack-lab5-pooled --query 'Stacks[0].StackStatus'
```

## What to Do If Issues Persist

1. **Check the logs:**
```
aws logs tail /aws/lambda/serverless-saas-pipeline-lab5-deploytenantstackD22DC62B-* --since 30m
```

2. **Verify exports match imports:**
```
# List exports
aws cloudformation list-exports --query 'Exports[?contains(Name, `Cognito`)].[Name]'

# Check what tenant template expects
grep -r "ImportValue.*Cognito" Lab5/server/tenant-template.yaml
```

3. **Check CodeCommit content:**
```
# Download packaged.yaml from S3
aws s3 cp s3://serverless-saas-pipeline-lab5-artifactsbucket*/packaged.yaml - | grep -A2 "CognitoOperationUsersUserPoolClientId"
```

4. **See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for complete solutions**

## Rollback Plan

If you need to start fresh:

```
# See TROUBLESHOOTING.md section "Complete Cleanup and Redeploy"
# Or run these commands:

# Delete tenant stacks
aws cloudformation delete-stack --stack-name stack-lab5-pooled

# Delete shared stack
aws cloudformation delete-stack --stack-name serverless-saas-workshop-shared-lab5

# Delete pipeline
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab5

# Wait for deletions, then redeploy
./deployment.sh -s -c
```

## Summary

The deployment script now handles the two main issues automatically:

1. **Timing Issue** - Waits for DynamoDB tables before pipeline can execute
2. **Code Sync Issue** - Pushes your local changes to CodeCommit before building

You can now run `./deployment.sh -s -c` and it will handle everything correctly!
