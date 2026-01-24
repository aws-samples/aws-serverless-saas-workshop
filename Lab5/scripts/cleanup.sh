#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# SECURITY NOTE: Deletion Order is Critical!
# ============================================
# This script follows a specific deletion order to prevent CloudFront Origin Hijacking:
# 1. Delete CloudFormation stacks (which delete CloudFront distributions)
# 2. Wait for CloudFront to be fully deleted (15-30 minutes)
# 3. THEN delete S3 buckets
#
# Why? If we delete S3 buckets BEFORE CloudFront distributions are deleted:
# - CloudFront still points to the deleted bucket name
# - An attacker can create a bucket with the same name in their account
# - CloudFront will serve the attacker's content to your users
# - This is a serious security vulnerability (CloudFront Origin Hijacking)
#
# DO NOT change this order without understanding the security implications!

set -e

# AWS Profile should be passed via --profile parameter

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-west-2"
SHARED_STACK_NAME="serverless-saas-shared-lab5"
PIPELINE_STACK_NAME="serverless-saas-pipeline-lab5"
SKIP_CONFIRMATION=0
AWS_PROFILE=""

# Function to build AWS CLI profile argument
# Returns "--profile <profile>" if PROFILE is set, empty string otherwise
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       Stack name prefix (default: serverless-saas-lab5)"
    echo "                            Sets both shared and pipeline stack names automatically"
    echo "  --shared-stack <name>     Shared stack name (default: serverless-saas-shared-lab5)"
    echo "  --pipeline-stack <name>   Pipeline stack name (default: serverless-saas-pipeline-lab5)"
    echo "  --region <region>         AWS region (default: us-west-2)"
    echo "  --profile <profile>       AWS CLI profile to use (optional, uses default if not specified)"
    echo "  -y, --yes                 Skip confirmation prompt"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Clean up with defaults"
    echo "  $0 --stack-name serverless-saas-lab5            # Clean up using stack name prefix"
    echo "  $0 --region us-east-1                           # Clean up in specific region"
    echo "  $0 --profile serverless-saas-demo               # Use specific AWS profile"
    echo "  $0 --stack-name my-lab --profile my-profile     # Clean up with custom stack name and profile"
    echo "  $0 -y                                           # Skip confirmation"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME_PREFIX=$2
            # Derive stack names from prefix
            SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME_PREFIX##*-}"
            PIPELINE_STACK_NAME="serverless-saas-pipeline-${STACK_NAME_PREFIX##*-}"
            # If the prefix already contains "serverless-saas-shared" or "serverless-saas-pipeline", use it as-is
            if [[ "$STACK_NAME_PREFIX" == serverless-saas-shared-* ]]; then
                SHARED_STACK_NAME="$STACK_NAME_PREFIX"
                PIPELINE_STACK_NAME="serverless-saas-pipeline-${STACK_NAME_PREFIX##*-}"
            elif [[ "$STACK_NAME_PREFIX" == serverless-saas-pipeline-* ]]; then
                PIPELINE_STACK_NAME="$STACK_NAME_PREFIX"
                SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME_PREFIX##*-}"
            fi
            shift 2
            ;;
        --shared-stack)
            SHARED_STACK_NAME=$2
            shift 2
            ;;
        --pipeline-stack)
            PIPELINE_STACK_NAME=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=1
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            print_message "$RED" "Unknown parameter: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab5 Complete Cleanup Script"
print_message "$BLUE" "=========================================="
echo "Started: $(date)"
echo "Log file: $LOG_FILE"
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Pipeline Stack: $PIPELINE_STACK_NAME"
echo ""
print_message "$YELLOW" "This will delete:"
print_message "$YELLOW" "  - All tenant stacks (stack-*)"
print_message "$YELLOW" "  - Shared infrastructure stack"
print_message "$YELLOW" "  - Pipeline stack"
print_message "$YELLOW" "  - S3 buckets (will be emptied first)"
print_message "$YELLOW" "  - CDK bootstrap resources"
print_message "$YELLOW" "  - Cognito User Pools"
echo ""

if [[ $SKIP_CONFIRMATION -eq 0 ]]; then
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        exit 0
    fi
fi

echo ""
print_message "$GREEN" "Starting cleanup..."
echo ""

CLEANUP_START=$(date +%s)

# Function to empty S3 bucket (including all versions and delete markers)
empty_bucket() {
  local bucket=$1
  PROFILE_ARG=$(get_profile_arg)
  print_message "$YELLOW" "  Emptying bucket: $bucket"
  
  # Check if bucket has versioning enabled
  VERSIONING=$(aws s3api $PROFILE_ARG get-bucket-versioning --bucket $bucket --region "$AWS_REGION" --query 'Status' --output text 2>/dev/null)
  
  if [[ "$VERSIONING" == "Enabled" ]]; then
    print_message "$YELLOW" "    Bucket has versioning enabled, deleting all versions..."
    
    # Delete all object versions
    aws s3api $PROFILE_ARG list-object-versions --bucket $bucket --region "$AWS_REGION" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$bucket"' --region '"$AWS_REGION"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Delete all delete markers
    aws s3api $PROFILE_ARG list-object-versions --bucket $bucket --region "$AWS_REGION" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$bucket"' --region '"$AWS_REGION"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
  fi
  
  # Delete current objects (for non-versioned buckets or remaining objects)
  aws s3 $PROFILE_ARG rm s3://$bucket --recursive --region "$AWS_REGION" 2>/dev/null
  
  if [[ $? -eq 0 ]] || [[ "$VERSIONING" == "Enabled" ]]; then
    print_message "$GREEN" "  ✓ Bucket emptied: $bucket"
  else
    print_message "$YELLOW" "  ⚠ Could not empty bucket: $bucket (may not exist)"
  fi
}

# Function to delete stack
delete_stack() {
  local stack=$1
  PROFILE_ARG=$(get_profile_arg)
  print_message "$YELLOW" "  Deleting stack: $stack"
  aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack --region "$AWS_REGION" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Delete initiated: $stack"
    return 0
  else
    print_message "$YELLOW" "  ⚠ Could not delete: $stack (may not exist)"
    return 1
  fi
}

# Function to wait for stack deletion
wait_for_deletion() {
  local stack=$1
  PROFILE_ARG=$(get_profile_arg)
  print_message "$YELLOW" "  Waiting for deletion: $stack"
  aws cloudformation $PROFILE_ARG wait stack-delete-complete --stack-name $stack --region "$AWS_REGION" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Deleted: $stack"
  else
    print_message "$YELLOW" "  ⚠ Deletion may have failed or stack doesn't exist: $stack"
  fi
}

# Step 1: Delete tenant stacks
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Deleting tenant stacks"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
TENANT_STACKS=$(aws cloudformation $PROFILE_ARG list-stacks \
  --region "$AWS_REGION" \
  --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE CREATE_FAILED ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `stack-`)].StackName' \
  --output text 2>/dev/null)

if [[ -z "$TENANT_STACKS" ]]; then
  print_message "$YELLOW" "No tenant stacks found"
else
  for stack in $TENANT_STACKS; do
    delete_stack $stack
  done
  
  echo ""
  print_message "$YELLOW" "Waiting for tenant stacks to delete..."
  for stack in $TENANT_STACKS; do
    wait_for_deletion $stack
  done
fi

print_message "$GREEN" "✓ Tenant stacks cleanup complete"
echo ""

# Step 2: Identify resources from stacks (before deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Identifying resources from stacks"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
ADMIN_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null)
LANDING_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null)
APP_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text 2>/dev/null)

# Get API Gateway IDs for log deletion
SHARED_API_ID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" --output text 2>/dev/null)

print_message "$YELLOW" "Found resources:"
[[ ! -z "$ADMIN_BUCKET" ]] && print_message "$YELLOW" "  - S3 Bucket: $ADMIN_BUCKET (will delete after CloudFront)"
[[ ! -z "$LANDING_BUCKET" ]] && print_message "$YELLOW" "  - S3 Bucket: $LANDING_BUCKET (will delete after CloudFront)"
[[ ! -z "$APP_BUCKET" ]] && print_message "$YELLOW" "  - S3 Bucket: $APP_BUCKET (will delete after CloudFront)"
[[ ! -z "$SHARED_API_ID" ]] && print_message "$YELLOW" "  - API Gateway ID: $SHARED_API_ID"
echo ""

# Step 3: Delete CloudWatch Log Groups (BEFORE stack deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 3: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Delete API Gateway execution logs first
print_message "$YELLOW" "Deleting API Gateway execution logs..."

# Delete logs for known API Gateway IDs
if [ -n "$SHARED_API_ID" ] && [ "$SHARED_API_ID" != "None" ]; then
    LOG_GROUP_NAME="API-Gateway-Execution-Logs_${SHARED_API_ID}/prod"
    print_message "$YELLOW" "  Deleting log group: $LOG_GROUP_NAME"
    aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
fi

# Check for orphaned API Gateway logs (logs where API Gateway no longer exists)
print_message "$YELLOW" "Checking for orphaned API Gateway logs..."
ORPHANED_API_LOGS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_API_LOGS" ]; then
    for log_group in $ORPHANED_API_LOGS; do
        # Extract API Gateway ID from log group name
        API_ID=$(echo "$log_group" | sed 's/API-Gateway-Execution-Logs_\([^/]*\).*/\1/')
        
        # Check if API Gateway still exists
        API_EXISTS=$(aws apigateway get-rest-api --rest-api-id "$API_ID" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || echo "")
        
        # If API Gateway doesn't exist, delete the orphaned log group
        if [ -z "$API_EXISTS" ]; then
            print_message "$YELLOW" "  Deleting orphaned log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        fi
    done
fi

print_message "$GREEN" "✓ API Gateway execution logs deleted"

# Delete Lambda function log groups
LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'lab5')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        print_message "$YELLOW" "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "✓ Lambda log groups deleted"
else
    print_message "$YELLOW" "  No Lambda log groups found"
fi

print_message "$GREEN" "✓ CloudWatch Log Groups cleanup complete"
echo ""

# Step 4: Delete shared stack (deletes CloudFront distributions)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 4: Deleting shared infrastructure (includes CloudFront)"
print_message "$BLUE" "=========================================="

if delete_stack "$SHARED_STACK_NAME"; then
  wait_for_deletion "$SHARED_STACK_NAME"
fi

print_message "$GREEN" "✓ Shared infrastructure cleanup complete (CloudFront deleted)"
echo ""

# Step 5: Safely delete S3 buckets (after CloudFront is deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 5: Safely deleting S3 buckets (CloudFront deleted)"
print_message "$BLUE" "=========================================="

[[ ! -z "$ADMIN_BUCKET" ]] && empty_bucket $ADMIN_BUCKET
[[ ! -z "$LANDING_BUCKET" ]] && empty_bucket $LANDING_BUCKET
[[ ! -z "$APP_BUCKET" ]] && empty_bucket $APP_BUCKET

print_message "$GREEN" "✓ S3 buckets deleted (secure - CloudFront was deleted first)"
echo ""

# Step 6: Get pipeline artifacts bucket
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 6: Cleaning up pipeline artifacts"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
PIPELINE_BUCKET=$(aws s3 $PROFILE_ARG ls --region "$AWS_REGION" | grep "${PIPELINE_STACK_NAME}-artifactsbucket" | awk '{print $3}')

if [[ ! -z "$PIPELINE_BUCKET" ]]; then
  print_message "$YELLOW" "Found pipeline bucket: $PIPELINE_BUCKET"
  empty_bucket $PIPELINE_BUCKET
else
  print_message "$YELLOW" "No pipeline artifacts bucket found"
fi

echo ""

# Step 7: Delete pipeline stack
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 7: Deleting pipeline"
print_message "$BLUE" "=========================================="

if delete_stack "$PIPELINE_STACK_NAME"; then
  wait_for_deletion "$PIPELINE_STACK_NAME"
fi

print_message "$GREEN" "✓ Pipeline cleanup complete"
echo ""

# Step 8: Clean up CDK bootstrap resources
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 8: Cleaning up CDK bootstrap resources"
print_message "$BLUE" "=========================================="

# Find CDK bootstrap bucket
PROFILE_ARG=$(get_profile_arg)
CDK_BUCKET=$(aws s3 $PROFILE_ARG ls --region "$AWS_REGION" | grep cdktoolkit | awk '{print $3}')

if [[ ! -z "$CDK_BUCKET" ]]; then
  print_message "$YELLOW" "Found CDK bootstrap bucket: $CDK_BUCKET"
  empty_bucket $CDK_BUCKET
  print_message "$YELLOW" "  Deleting bucket: $CDK_BUCKET"
  aws s3 $PROFILE_ARG rb s3://$CDK_BUCKET --region "$AWS_REGION" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Bucket deleted: $CDK_BUCKET"
  else
    print_message "$YELLOW" "  ⚠ Could not delete bucket: $CDK_BUCKET"
  fi
else
  print_message "$YELLOW" "No CDK bootstrap bucket found"
fi

# Delete CDKToolkit stack
if delete_stack "CDKToolkit"; then
  wait_for_deletion "CDKToolkit"
fi

print_message "$GREEN" "✓ CDK bootstrap cleanup complete"
echo ""

# Step 9: Clean up SAM build artifacts
echo "=========================================="
echo "Step 9: Cleaning up SAM build artifacts"
echo "=========================================="

# Find Lab5 SAM buckets
PROFILE_ARG=$(get_profile_arg)
LAB5_SAM_BUCKETS=$(aws s3 $PROFILE_ARG ls | grep -E "aws-sam-cli-managed.*lab5|serverless-saas.*lab5" | awk '{print $3}')

if [[ ! -z "$LAB5_SAM_BUCKETS" ]]; then
  echo "Found Lab5 SAM buckets:"
  for bucket in $LAB5_SAM_BUCKETS; do
    echo "  - $bucket"
    empty_bucket $bucket
    # Delete the bucket after emptying
    echo "  Deleting bucket: $bucket"
    aws s3 $PROFILE_ARG rb s3://$bucket 2>/dev/null
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

# Step 10: Clean up CDK assets bucket
echo "=========================================="
echo "Step 10: Cleaning up CDK assets bucket"
echo "=========================================="

PROFILE_ARG=$(get_profile_arg)
CDK_ASSETS_BUCKET=$(aws s3 $PROFILE_ARG ls | grep "cdk-hnb659fds-assets" | awk '{print $3}')

if [[ ! -z "$CDK_ASSETS_BUCKET" ]]; then
  echo "Found CDK assets bucket: $CDK_ASSETS_BUCKET"
  empty_bucket $CDK_ASSETS_BUCKET
  
  # Verify bucket is completely empty before deletion
  REMAINING_VERSIONS=$(aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --output json 2>/dev/null | jq -r '(.Versions // []) + (.DeleteMarkers // []) | length')
  
  if [[ "$REMAINING_VERSIONS" == "0" ]]; then
    echo "  Deleting bucket: $CDK_ASSETS_BUCKET"
    aws s3 $PROFILE_ARG rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Bucket deleted: $CDK_ASSETS_BUCKET"
    else
      echo "  ⚠ Could not delete bucket: $CDK_ASSETS_BUCKET"
    fi
  else
    echo "  ⚠ Warning: $REMAINING_VERSIONS versions/markers still exist in bucket"
    echo "  Attempting force deletion of remaining versions..."
    
    # Force delete any remaining versions
    aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Force delete any remaining delete markers
    aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Try deletion again
    echo "  Retrying bucket deletion: $CDK_ASSETS_BUCKET"
    aws s3 $PROFILE_ARG rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
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

# Step 11: Verify cleanup
echo "=========================================="
echo "Step 11: Cleaning up Cognito User Pools"
echo "=========================================="

# Find and delete Lab5 Cognito User Pools
PROFILE_ARG=$(get_profile_arg)
LAB5_POOLS=$(aws cognito-idp $PROFILE_ARG list-user-pools --max-results 60 --output json 2>/dev/null | jq -r '.UserPools[] | select(.Name | contains("lab5")) | .Id')

if [[ ! -z "$LAB5_POOLS" ]]; then
  echo "Found Lab5 Cognito User Pools:"
  for pool_id in $LAB5_POOLS; do
    POOL_NAME=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Name' --output text 2>/dev/null)
    echo "  Processing pool: $POOL_NAME ($pool_id)"
    
    # Delete domain first if it exists
    DOMAIN=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Domain' --output text 2>/dev/null)
    if [[ ! -z "$DOMAIN" && "$DOMAIN" != "None" ]]; then
      echo "    Deleting domain: $DOMAIN"
      aws cognito-idp $PROFILE_ARG delete-user-pool-domain --domain $DOMAIN --user-pool-id $pool_id 2>/dev/null
    fi
    
    # Now delete the pool
    echo "    Deleting pool: $POOL_NAME"
    aws cognito-idp $PROFILE_ARG delete-user-pool --user-pool-id $pool_id 2>/dev/null
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

# Step 12: Verify cleanup
echo "=========================================="
echo "Step 12: Verifying cleanup"
echo "=========================================="

PROFILE_ARG=$(get_profile_arg)
REMAINING_EXPORTS=$(aws cloudformation $PROFILE_ARG list-exports --query 'Exports[?contains(Name, `lab5`)].Name' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_EXPORTS" ]]; then
  echo "⚠ Warning: Some Lab5 exports still exist:"
  echo "$REMAINING_EXPORTS"
  echo "These should be cleaned up automatically when their stacks are deleted"
else
  echo "✓ No Lab5 exports remaining"
fi

echo ""

REMAINING_TABLES=$(aws dynamodb $PROFILE_ARG list-tables --query 'TableNames[?contains(@, `lab5`)]' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_TABLES" ]]; then
  echo "⚠ Warning: Some Lab5 DynamoDB tables still exist:"
  echo "$REMAINING_TABLES"
  echo "These should be cleaned up automatically when the shared stack is deleted"
else
  echo "✓ No Lab5 DynamoDB tables remaining"
fi

echo ""

REMAINING_STACKS=$(aws cloudformation $PROFILE_ARG list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `lab5`) || contains(StackName, `serverless-saas-pipeline-lab5`)].StackName' \
  --output text 2>/dev/null)
if [[ ! -z "$REMAINING_STACKS" ]]; then
  echo "⚠ Warning: Some stacks still exist:"
  echo "$REMAINING_STACKS"
else
  echo "✓ No Lab5 stacks remaining"
fi

CLEANUP_END=$(date +%s)
CLEANUP_DURATION=$((CLEANUP_END - CLEANUP_START))
CLEANUP_MINUTES=$((CLEANUP_DURATION / 60))
CLEANUP_SECONDS=$((CLEANUP_DURATION % 60))

echo ""
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Cleanup Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Completed: $(date)"
print_message "$GREEN" "Duration: ${CLEANUP_MINUTES}m ${CLEANUP_SECONDS}s"
echo ""
print_message "$BLUE" "Log file: $LOG_FILE"
echo ""
print_message "$YELLOW" "You can now run a fresh deployment:"
print_message "$YELLOW" "  cd Lab5/scripts"
print_message "$YELLOW" "  ./deployment.sh -s -c      # Deploy server and client"
print_message "$YELLOW" "  ./deployment.sh -b         # Deploy only bootstrap"
echo ""
