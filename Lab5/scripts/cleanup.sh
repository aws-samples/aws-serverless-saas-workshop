#!/bin/bash

echo "=========================================="
echo "Lab5 Complete Cleanup Script"
echo "=========================================="
echo ""
echo "This will delete:"
echo "  - All tenant stacks (stack-*)"
echo "  - Shared infrastructure stack"
echo "  - Pipeline stack"
echo "  - S3 buckets (will be emptied first)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled"
  exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

REGION=$(aws configure get region)

# Function to empty S3 bucket (including all versions and delete markers)
empty_bucket() {
  local bucket=$1
  echo "  Emptying bucket: $bucket"
  
  # Check if bucket has versioning enabled
  VERSIONING=$(aws s3api get-bucket-versioning --bucket $bucket --query 'Status' --output text 2>/dev/null)
  
  if [[ "$VERSIONING" == "Enabled" ]]; then
    echo "    Bucket has versioning enabled, deleting all versions..."
    
    # Delete all object versions
    aws s3api list-object-versions --bucket $bucket --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api delete-object --bucket '"$bucket"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Delete all delete markers
    aws s3api list-object-versions --bucket $bucket --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api delete-object --bucket '"$bucket"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
  fi
  
  # Delete current objects (for non-versioned buckets or remaining objects)
  aws s3 rm s3://$bucket --recursive 2>/dev/null
  
  if [[ $? -eq 0 ]] || [[ "$VERSIONING" == "Enabled" ]]; then
    echo "  ✓ Bucket emptied: $bucket"
  else
    echo "  ⚠ Could not empty bucket: $bucket (may not exist)"
  fi
}

# Function to delete stack
delete_stack() {
  local stack=$1
  echo "  Deleting stack: $stack"
  aws cloudformation delete-stack --stack-name $stack 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "  ✓ Delete initiated: $stack"
    return 0
  else
    echo "  ⚠ Could not delete: $stack (may not exist)"
    return 1
  fi
}

# Function to wait for stack deletion
wait_for_deletion() {
  local stack=$1
  echo "  Waiting for deletion: $stack"
  aws cloudformation wait stack-delete-complete --stack-name $stack 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "  ✓ Deleted: $stack"
  else
    echo "  ⚠ Deletion may have failed or stack doesn't exist: $stack"
  fi
}

# Step 1: Delete tenant stacks
echo "=========================================="
echo "Step 1: Deleting tenant stacks"
echo "=========================================="

TENANT_STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE CREATE_FAILED ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `stack-`)].StackName' \
  --output text 2>/dev/null)

if [[ -z "$TENANT_STACKS" ]]; then
  echo "No tenant stacks found"
else
  for stack in $TENANT_STACKS; do
    delete_stack $stack
  done
  
  echo ""
  echo "Waiting for tenant stacks to delete..."
  for stack in $TENANT_STACKS; do
    wait_for_deletion $stack
  done
fi

echo "✓ Tenant stacks cleanup complete"
echo ""

# Step 2: Get S3 buckets before deleting shared stack
echo "=========================================="
echo "Step 2: Identifying S3 buckets"
echo "=========================================="

ADMIN_BUCKET=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab5 \
  --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null)
LANDING_BUCKET=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab5 \
  --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null)
APP_BUCKET=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab5 \
  --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text 2>/dev/null)

echo "Found buckets:"
[[ ! -z "$ADMIN_BUCKET" ]] && echo "  - $ADMIN_BUCKET"
[[ ! -z "$LANDING_BUCKET" ]] && echo "  - $LANDING_BUCKET"
[[ ! -z "$APP_BUCKET" ]] && echo "  - $APP_BUCKET"
echo ""

# Step 3: Empty S3 buckets
echo "=========================================="
echo "Step 3: Emptying S3 buckets"
echo "=========================================="

[[ ! -z "$ADMIN_BUCKET" ]] && empty_bucket $ADMIN_BUCKET
[[ ! -z "$LANDING_BUCKET" ]] && empty_bucket $LANDING_BUCKET
[[ ! -z "$APP_BUCKET" ]] && empty_bucket $APP_BUCKET

echo "✓ S3 buckets emptied"
echo ""

# Step 4: Delete shared stack
echo "=========================================="
echo "Step 4: Deleting shared infrastructure"
echo "=========================================="

if delete_stack "serverless-saas-workshop-shared-lab5"; then
  wait_for_deletion "serverless-saas-workshop-shared-lab5"
fi

echo "✓ Shared infrastructure cleanup complete"
echo ""

# Step 5: Get pipeline artifacts bucket
echo "=========================================="
echo "Step 5: Cleaning up pipeline artifacts"
echo "=========================================="

PIPELINE_BUCKET=$(aws s3 ls | grep serverless-saas-pipeline-artifactsbucket | awk '{print $3}')

if [[ ! -z "$PIPELINE_BUCKET" ]]; then
  echo "Found pipeline bucket: $PIPELINE_BUCKET"
  empty_bucket $PIPELINE_BUCKET
else
  echo "No pipeline artifacts bucket found"
fi

echo ""

# Step 6: Delete pipeline stack
echo "=========================================="
echo "Step 6: Deleting pipeline"
echo "=========================================="

if delete_stack "serverless-saas-pipeline"; then
  wait_for_deletion "serverless-saas-pipeline"
fi

echo "✓ Pipeline cleanup complete"
echo ""

# Step 7: Clean up CDK bootstrap resources
echo "=========================================="
echo "Step 7: Cleaning up CDK bootstrap resources"
echo "=========================================="

# Find CDK bootstrap bucket
CDK_BUCKET=$(aws s3 ls | grep cdktoolkit | awk '{print $3}')

if [[ ! -z "$CDK_BUCKET" ]]; then
  echo "Found CDK bootstrap bucket: $CDK_BUCKET"
  empty_bucket $CDK_BUCKET
  echo "  Deleting bucket: $CDK_BUCKET"
  aws s3 rb s3://$CDK_BUCKET 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "  ✓ Bucket deleted: $CDK_BUCKET"
  else
    echo "  ⚠ Could not delete bucket: $CDK_BUCKET"
  fi
else
  echo "No CDK bootstrap bucket found"
fi

# Delete CDKToolkit stack
if delete_stack "CDKToolkit"; then
  wait_for_deletion "CDKToolkit"
fi

echo "✓ CDK bootstrap cleanup complete"
echo ""

# Step 8: Clean up SAM build artifacts
echo "=========================================="
echo "Step 8: Cleaning up SAM build artifacts"
echo "=========================================="

# Find Lab5 SAM buckets
LAB5_SAM_BUCKETS=$(aws s3 ls | grep -E "aws-sam-cli-managed.*lab5|serverless-saas.*lab5" | awk '{print $3}')

if [[ ! -z "$LAB5_SAM_BUCKETS" ]]; then
  echo "Found Lab5 SAM buckets:"
  for bucket in $LAB5_SAM_BUCKETS; do
    echo "  - $bucket"
    empty_bucket $bucket
    # Delete the bucket after emptying
    echo "  Deleting bucket: $bucket"
    aws s3 rb s3://$bucket 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Bucket deleted: $bucket"
    else
      echo "  ⚠ Could not delete bucket: $bucket"
    fi
  done
else
  echo "No Lab5 SAM buckets found"
fi

echo "✓ SAM artifacts cleanup complete"
echo ""

# Step 8b: Clean up CDK assets bucket
echo "=========================================="
echo "Step 8b: Cleaning up CDK assets bucket"
echo "=========================================="

CDK_ASSETS_BUCKET=$(aws s3 ls | grep "cdk-hnb659fds-assets" | awk '{print $3}')

if [[ ! -z "$CDK_ASSETS_BUCKET" ]]; then
  echo "Found CDK assets bucket: $CDK_ASSETS_BUCKET"
  empty_bucket $CDK_ASSETS_BUCKET
  
  # Verify bucket is completely empty before deletion
  REMAINING_VERSIONS=$(aws s3api list-object-versions --bucket $CDK_ASSETS_BUCKET --output json 2>/dev/null | jq -r '(.Versions // []) + (.DeleteMarkers // []) | length')
  
  if [[ "$REMAINING_VERSIONS" == "0" ]]; then
    echo "  Deleting bucket: $CDK_ASSETS_BUCKET"
    aws s3 rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Bucket deleted: $CDK_ASSETS_BUCKET"
    else
      echo "  ⚠ Could not delete bucket: $CDK_ASSETS_BUCKET"
    fi
  else
    echo "  ⚠ Warning: $REMAINING_VERSIONS versions/markers still exist in bucket"
    echo "  Attempting force deletion of remaining versions..."
    
    # Force delete any remaining versions
    aws s3api list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Force delete any remaining delete markers
    aws s3api list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Try deletion again
    echo "  Retrying bucket deletion: $CDK_ASSETS_BUCKET"
    aws s3 rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Bucket deleted: $CDK_ASSETS_BUCKET"
    else
      echo "  ⚠ Could not delete bucket: $CDK_ASSETS_BUCKET (manual deletion may be required)"
    fi
  fi
else
  echo "No CDK assets bucket found"
fi

echo "✓ CDK assets cleanup complete"
echo ""

# Step 9: Verify cleanup
echo "=========================================="
echo "Step 9: Cleaning up Cognito User Pools"
echo "=========================================="

# Find and delete Lab5 Cognito User Pools
LAB5_POOLS=$(aws cognito-idp list-user-pools --max-results 60 --output json 2>/dev/null | jq -r '.UserPools[] | select(.Name | contains("lab5")) | .Id')

if [[ ! -z "$LAB5_POOLS" ]]; then
  echo "Found Lab5 Cognito User Pools:"
  for pool_id in $LAB5_POOLS; do
    POOL_NAME=$(aws cognito-idp describe-user-pool --user-pool-id $pool_id --query 'UserPool.Name' --output text 2>/dev/null)
    echo "  Processing pool: $POOL_NAME ($pool_id)"
    
    # Delete domain first if it exists
    DOMAIN=$(aws cognito-idp describe-user-pool --user-pool-id $pool_id --query 'UserPool.Domain' --output text 2>/dev/null)
    if [[ ! -z "$DOMAIN" && "$DOMAIN" != "None" ]]; then
      echo "    Deleting domain: $DOMAIN"
      aws cognito-idp delete-user-pool-domain --domain $DOMAIN --user-pool-id $pool_id 2>/dev/null
    fi
    
    # Now delete the pool
    echo "    Deleting pool: $POOL_NAME"
    aws cognito-idp delete-user-pool --user-pool-id $pool_id 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Pool deleted: $POOL_NAME"
    else
      echo "  ⚠ Could not delete pool: $POOL_NAME"
    fi
  done
else
  echo "No Lab5 Cognito User Pools found"
fi

echo "✓ Cognito User Pools cleanup complete"
echo ""

# Step 10: Verify cleanup
echo "=========================================="
echo "Step 10: Verifying cleanup"
echo "=========================================="

REMAINING_EXPORTS=$(aws cloudformation list-exports --query 'Exports[?contains(Name, `lab5`)].Name' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_EXPORTS" ]]; then
  echo "⚠ Warning: Some Lab5 exports still exist:"
  echo "$REMAINING_EXPORTS"
  echo "These should be cleaned up automatically when their stacks are deleted"
else
  echo "✓ No Lab5 exports remaining"
fi

echo ""

REMAINING_TABLES=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `lab5`)]' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_TABLES" ]]; then
  echo "⚠ Warning: Some Lab5 DynamoDB tables still exist:"
  echo "$REMAINING_TABLES"
  echo "These should be cleaned up automatically when the shared stack is deleted"
else
  echo "✓ No Lab5 DynamoDB tables remaining"
fi

echo ""

REMAINING_STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `lab5`) || contains(StackName, `serverless-saas-pipeline`)].StackName' \
  --output text 2>/dev/null)
if [[ ! -z "$REMAINING_STACKS" ]]; then
  echo "⚠ Warning: Some stacks still exist:"
  echo "$REMAINING_STACKS"
else
  echo "✓ No Lab5 stacks remaining"
fi

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "You can now run a fresh deployment:"
echo "  cd Lab5/scripts"
echo "  ./deployment.sh -s -c"
echo ""
echo "Or use screen for long deployments:"
echo "  ./deploy-with-screen.sh"
echo ""
