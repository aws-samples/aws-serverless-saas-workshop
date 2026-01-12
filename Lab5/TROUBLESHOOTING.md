# Lab5 Troubleshooting Guide

## Common Issues and Solutions

### 1. ResourceNotFoundException: DynamoDB Table Not Found

**Error Message:**
```
An error occurred (ResourceNotFoundException) when calling the Scan operation: Requested resource not found
```

**Cause:** The pipeline Lambda function tried to scan the `ServerlessSaaS-TenantStackMapping-lab5` table before it was fully created.

**Solution:** The deployment script now includes automatic waits for DynamoDB tables. If you still encounter this:

```bash
# Manually verify tables exist
aws dynamodb list-tables --query 'TableNames[?contains(@, `lab5`)]'

# Wait for a specific table
aws dynamodb wait table-exists --table-name ServerlessSaaS-TenantStackMapping-lab5

# Retry the pipeline
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline
```

### 2. Stack ROLLBACK_COMPLETE: Missing CloudFormation Exports

**Error Message:**
```
No export named Serverless-SaaS-CognitoOperationUsersUserPoolClientId found
```

**Cause:** The tenant stack is trying to import exports without the `-lab5` suffix, but the shared stack exports them with the suffix.

**Root Cause:** The CodeCommit repository has old code that doesn't include the Lab5 naming updates.

**Solution:** The deployment script now automatically pushes your current branch to CodeCommit. If you need to manually fix:

```bash
# Check what's in CodeCommit
git fetch cc
git log cc/main --oneline -5

# Push your current branch to CodeCommit main
git push cc HEAD:main --force

# Trigger the pipeline to rebuild with new code
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline
```

### 3. Checking Stack Failure Details

To see why a tenant stack failed:

```bash
# List failed stacks
aws cloudformation list-stacks --stack-status-filter ROLLBACK_COMPLETE --query 'StackSummaries[?contains(StackName, `stack-`)].StackName'

# Get failure reason for a specific stack
aws cloudformation describe-stack-events \
  --stack-name stack-lab5-pooled \
  --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[Timestamp,LogicalResourceId,ResourceStatusReason]' \
  --output table

# Or use JSON for detailed analysis
aws cloudformation describe-stack-events \
  --stack-name stack-lab5-pooled \
  --output json | jq -r '.StackEvents[] | select(.ResourceStatus | test("FAILED|ROLLBACK")) | "\(.Timestamp) | \(.LogicalResourceId) | \(.ResourceStatusReason // "N/A")"'
```

### 4. Cleaning Up Failed Stacks

If you need to clean up and redeploy:

```bash
# Delete failed tenant stacks
aws cloudformation delete-stack --stack-name stack-lab5-pooled
aws cloudformation wait stack-delete-complete --stack-name stack-lab5-pooled

# Clear the tenant stack mapping table
aws dynamodb delete-item \
  --table-name ServerlessSaaS-TenantStackMapping-lab5 \
  --key '{"tenantId": {"S": "pooled"}}'

# Trigger pipeline to recreate
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline
```

### 5. Pipeline Not Picking Up Code Changes

**Symptom:** You made changes to the code but the pipeline is still deploying old code.

**Solution:**

```bash
# Verify what's in CodeCommit
git fetch cc
git diff cc/main

# Push your changes
git push cc HEAD:main --force

# Manually trigger pipeline
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline
```

### 6. Checking Lambda Function Logs

To debug Lambda function issues:

```bash
# Find the Lambda function name
aws lambda list-functions --query 'Functions[?contains(FunctionName, `deploytenantstack`)].FunctionName'

# Tail the logs
aws logs tail /aws/lambda/FUNCTION_NAME --follow

# Get recent errors
aws logs tail /aws/lambda/FUNCTION_NAME --since 1h --format short | grep -i error
```

### 7. Verifying CloudFormation Exports

Check if all required exports exist:

```bash
# List all Lab5 exports
aws cloudformation list-exports --query 'Exports[?contains(Name, `lab5`)].[Name,Value]' --output table

# Check specific export
aws cloudformation list-exports --query 'Exports[?Name==`Serverless-SaaS-CognitoOperationUsersUserPoolClientId-lab5`]'
```

### 8. Complete Cleanup and Redeploy

If everything is broken and you want to start fresh:

```bash
# 1. Delete all tenant stacks
for stack in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `stack-`)].StackName' --output text); do
  echo "Deleting $stack"
  aws cloudformation delete-stack --stack-name $stack
done

# 2. Wait for deletions
for stack in $(aws cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS --query 'StackSummaries[?contains(StackName, `stack-`)].StackName' --output text); do
  echo "Waiting for $stack to delete..."
  aws cloudformation wait stack-delete-complete --stack-name $stack
done

# 3. Delete the shared stack
aws cloudformation delete-stack --stack-name serverless-saas-workshop-shared-lab5
aws cloudformation wait stack-delete-complete --stack-name serverless-saas-workshop-shared-lab5

# 4. Delete the pipeline stack
aws cloudformation delete-stack --stack-name serverless-saas-pipeline
aws cloudformation wait stack-delete-complete --stack-name serverless-saas-pipeline

# 5. Redeploy everything
cd Lab5/scripts
./deployment.sh -s -c
```

## Deployment Order

The correct deployment order is:

1. **Pipeline** - Creates CodePipeline and CodeCommit repository
2. **Bootstrap** - Deploys shared infrastructure (DynamoDB tables, Cognito, etc.)
3. **Wait for DynamoDB** - Ensures tables are fully active
4. **Pipeline Execution** - Automatically triggered to deploy tenant stacks
5. **Client** - Deploys UI applications

The updated `deployment.sh` script handles this order automatically.

## Monitoring Deployment Progress

```bash
# Watch pipeline execution
aws codepipeline get-pipeline-state --name serverless-saas-pipeline

# Watch CloudFormation stack creation
watch -n 5 'aws cloudformation list-stacks --stack-status-filter CREATE_IN_PROGRESS UPDATE_IN_PROGRESS --query "StackSummaries[?contains(StackName, \"stack-\")].[StackName,StackStatus]" --output table'

# Check DynamoDB table status
aws dynamodb describe-table --table-name ServerlessSaaS-TenantStackMapping-lab5 --query 'Table.TableStatus'
```

## Getting Help

If you're still stuck:

1. Check the CloudWatch logs for the specific Lambda function
2. Review CloudFormation events for the failed stack
3. Verify all exports exist with the correct `-lab5` suffix
4. Ensure your code is pushed to CodeCommit main branch
5. Check that DynamoDB tables are in ACTIVE state
