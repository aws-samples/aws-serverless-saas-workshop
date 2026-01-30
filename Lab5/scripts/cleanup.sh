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

# Source parameter parsing template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib/parameter-parsing-template.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Lab-specific configuration
DEFAULT_STACK_NAME="serverless-saas-lab5"
LAB_NUMBER="5"
LAB_ID="lab5"  # Lab identifier for resource filtering

# Function to show help text
show_help() {
    show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
}

# Parse command line parameters
parse_cleanup_parameters "$@"

# Derive shared and pipeline stack names from base stack name
SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME##*-}"
PIPELINE_STACK_NAME="serverless-saas-pipeline-${STACK_NAME##*-}"

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

# Function to verify stack ownership
# Ensures that a stack belongs to this lab before deletion
verify_stack_ownership() {
    local stack_name=$1
    local lab_id=$2
    
    # Check if stack name contains lab identifier
    if [[ "$stack_name" == *"$lab_id"* ]]; then
        return 0  # Stack belongs to this lab
    else
        print_message "$RED" "WARNING: Stack $stack_name does not belong to $lab_id"
        return 1  # Stack does not belong to this lab
    fi
}

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
echo "Stack name: $STACK_NAME"
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Pipeline Stack: $PIPELINE_STACK_NAME"
echo ""
print_message "$YELLOW" "This will delete:"
print_message "$YELLOW" "  - All tenant stacks for $LAB_ID (stack-*$LAB_ID*)"
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
  VERSIONING=$(aws s3api $PROFILE_ARG get-bucket-versioning --bucket $bucket --region "$AWS_REGION" --query 'Status' --output text 2>/dev/null || echo "")
  
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

# Function to delete stack with CDK role handling
delete_stack_with_cdk_role() {
  local stack=$1
  local role_created=false
  PROFILE_ARG=$(get_profile_arg)
  
  print_message "$YELLOW" "  Deleting stack: $stack"
  
  # Try to delete the stack normally first
  local delete_output=$(aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack --region "$AWS_REGION" 2>&1)
  local delete_status=$?
  
  # Check if deletion failed due to missing CDK role
  if [[ $delete_status -ne 0 ]] && echo "$delete_output" | grep -q "is invalid or cannot be assumed"; then
    print_message "$YELLOW" "  ⚠ Stack requires CDK execution role that was deleted"
    print_message "$YELLOW" "  Creating temporary CDK execution role..."
    
    # Extract account ID from the error message or use current account
    local account_id=$(aws sts $PROFILE_ARG get-caller-identity --query Account --output text 2>/dev/null || echo "")
    local role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-${AWS_REGION}"
    
    # Create temporary role
    aws iam $PROFILE_ARG create-role \
      --role-name "$role_name" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
      --region "$AWS_REGION" >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
      role_created=true
      print_message "$GREEN" "  ✓ Temporary role created: $role_name"
      
      # Attach admin policy
      aws iam $PROFILE_ARG attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
        --region "$AWS_REGION" >/dev/null 2>&1
      
      # Wait a moment for role to propagate
      sleep 3
      
      # Try deletion again
      aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack --region "$AWS_REGION" 2>/dev/null
      if [[ $? -eq 0 ]]; then
        print_message "$GREEN" "  ✓ Delete initiated: $stack"
        
        # Wait for deletion to complete before cleaning up role
        print_message "$YELLOW" "  Waiting for stack deletion to complete..."
        aws cloudformation $PROFILE_ARG wait stack-delete-complete --stack-name $stack --region "$AWS_REGION" 2>/dev/null
        
        # Clean up temporary role
        print_message "$YELLOW" "  Cleaning up temporary CDK role..."
        aws iam $PROFILE_ARG detach-role-policy \
          --role-name "$role_name" \
          --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
          --region "$AWS_REGION" >/dev/null 2>&1
        
        aws iam $PROFILE_ARG delete-role \
          --role-name "$role_name" \
          --region "$AWS_REGION" >/dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
          print_message "$GREEN" "  ✓ Temporary CDK role deleted"
        else
          print_message "$YELLOW" "  ⚠ Could not delete temporary role: $role_name"
          print_message "$YELLOW" "    You may need to delete it manually"
        fi
        
        return 0
      else
        print_message "$RED" "  ✗ Failed to delete stack even with temporary role"
        
        # Try to clean up role even if stack deletion failed
        aws iam $PROFILE_ARG detach-role-policy \
          --role-name "$role_name" \
          --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
          --region "$AWS_REGION" >/dev/null 2>&1
        aws iam $PROFILE_ARG delete-role \
          --role-name "$role_name" \
          --region "$AWS_REGION" >/dev/null 2>&1
        
        return 1
      fi
    else
      print_message "$RED" "  ✗ Failed to create temporary CDK role"
      print_message "$YELLOW" "    Please run the cleanup script again or delete the stack manually"
      return 1
    fi
  elif [[ $delete_status -eq 0 ]]; then
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
print_message "$BLUE" "Step 1: Deleting tenant stacks for $LAB_ID"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
# Query for tenant stacks with lab-specific filtering
# Pattern: stack-* AND contains lab5
TENANT_STACKS=$(aws cloudformation $PROFILE_ARG list-stacks \
  --region "$AWS_REGION" \
  --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE CREATE_FAILED ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'stack-') && contains(StackName, '$LAB_ID')].StackName" \
  --output text 2>/dev/null)

if [[ -z "$TENANT_STACKS" ]]; then
  print_message "$YELLOW" "No tenant stacks found for $LAB_ID"
else
  print_message "$GREEN" "Found tenant stacks for $LAB_ID:"
  for stack in $TENANT_STACKS; do
    print_message "$GREEN" "  - $stack"
  done
  echo ""
  
  # Delete each tenant stack with verification
  for stack in $TENANT_STACKS; do
    if verify_stack_ownership "$stack" "$LAB_ID"; then
      delete_stack $stack
    else
      print_message "$YELLOW" "Skipping stack: $stack (not owned by $LAB_ID)"
    fi
  done
  
  echo ""
  print_message "$YELLOW" "Waiting for tenant stacks to delete..."
  for stack in $TENANT_STACKS; do
    # Only wait for stacks that belong to this lab
    if verify_stack_ownership "$stack" "$LAB_ID"; then
      wait_for_deletion $stack
    fi
  done
fi

print_message "$GREEN" "✓ Tenant stacks cleanup complete for $LAB_ID"
echo ""

# Step 2: Identify resources from stacks (before deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Identifying resources from stacks"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
ADMIN_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
LANDING_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
APP_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text 2>/dev/null || echo "")

# Get API Gateway IDs for log deletion
SHARED_API_ID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" --output text 2>/dev/null || echo "")

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

PROFILE_ARG=$(get_profile_arg)
if aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    print_message "$YELLOW" "  Deleting stack: $SHARED_STACK_NAME"
    aws cloudformation $PROFILE_ARG delete-stack --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION"
    
    print_message "$YELLOW" "Waiting for stack $SHARED_STACK_NAME to be deleted..."
    print_message "$YELLOW" "⏳ This may take 15-30 minutes for CloudFront distributions to fully delete"
    print_message "$YELLOW" "⏳ DO NOT interrupt this process - CloudFront must be fully deleted before S3 buckets"
    echo ""
    
    # Use AWS CLI wait command for reliable stack deletion monitoring
    if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION"; then
        print_message "$GREEN" "✓ Stack $SHARED_STACK_NAME deleted successfully (including CloudFront distributions)"
        print_message "$GREEN" "✓ CloudFront distributions are fully deleted - safe to proceed"
        echo ""
    else
        print_message "$RED" "Stack deletion failed or timed out"
        print_message "$RED" "Please check AWS Console for stack status"
        exit 1
    fi
else
    print_message "$YELLOW" "  Stack $SHARED_STACK_NAME not found"
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

PROFILE_ARG=$(get_profile_arg)
print_message "$YELLOW" "  Deleting stack: $PIPELINE_STACK_NAME"

# Try to delete the stack normally first
delete_output=$(aws cloudformation $PROFILE_ARG delete-stack --stack-name "$PIPELINE_STACK_NAME" --region "$AWS_REGION" 2>&1)
delete_status=$?

# Check if deletion failed due to missing CDK role
if [[ $delete_status -ne 0 ]] && echo "$delete_output" | grep -q "is invalid or cannot be assumed"; then
    print_message "$YELLOW" "  ⚠ Stack requires CDK execution role that was deleted"
    print_message "$YELLOW" "  Creating temporary CDK execution role..."
    
    # Extract account ID
    account_id=$(aws sts $PROFILE_ARG get-caller-identity --query Account --output text 2>/dev/null || echo "")
    role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-${AWS_REGION}"
    
    # Create temporary role
    aws iam $PROFILE_ARG create-role \
        --role-name "$role_name" \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        print_message "$GREEN" "  ✓ Temporary role created: $role_name"
        
        # Attach admin policy
        aws iam $PROFILE_ARG attach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
            --region "$AWS_REGION" >/dev/null 2>&1
        
        # Wait for role to propagate
        sleep 3
        
        # Try deletion again
        aws cloudformation $PROFILE_ARG delete-stack --stack-name "$PIPELINE_STACK_NAME" --region "$AWS_REGION" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            print_message "$GREEN" "  ✓ Delete initiated: $PIPELINE_STACK_NAME"
            
            print_message "$YELLOW" "Waiting for stack $PIPELINE_STACK_NAME to be deleted..."
            print_message "$YELLOW" "⏳ This may take several minutes"
            echo ""
            
            # Use AWS CLI wait command for reliable stack deletion monitoring
            if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "$PIPELINE_STACK_NAME" --region "$AWS_REGION"; then
                print_message "$GREEN" "✓ Stack $PIPELINE_STACK_NAME deleted successfully"
                echo ""
            else
                print_message "$RED" "Stack deletion failed or timed out"
                print_message "$RED" "Please check AWS Console for stack status"
                exit 1
            fi
            
            # Clean up temporary role
            print_message "$YELLOW" "  Cleaning up temporary CDK role..."
            aws iam $PROFILE_ARG detach-role-policy \
                --role-name "$role_name" \
                --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
                --region "$AWS_REGION" >/dev/null 2>&1
            
            aws iam $PROFILE_ARG delete-role \
                --role-name "$role_name" \
                --region "$AWS_REGION" >/dev/null 2>&1
            
            if [[ $? -eq 0 ]]; then
                print_message "$GREEN" "  ✓ Temporary CDK role deleted"
            else
                print_message "$YELLOW" "  ⚠ Could not delete temporary role: $role_name"
                print_message "$YELLOW" "    You may need to delete it manually"
            fi
        else
            print_message "$RED" "  ✗ Failed to delete stack even with temporary role"
            
            # Try to clean up role even if stack deletion failed
            aws iam $PROFILE_ARG detach-role-policy \
                --role-name "$role_name" \
                --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
                --region "$AWS_REGION" >/dev/null 2>&1
            aws iam $PROFILE_ARG delete-role \
                --role-name "$role_name" \
                --region "$AWS_REGION" >/dev/null 2>&1
        fi
    else
        print_message "$RED" "  ✗ Failed to create temporary CDK role"
        print_message "$YELLOW" "    Please run the cleanup script again or delete the stack manually"
    fi
elif [[ $delete_status -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Delete initiated: $PIPELINE_STACK_NAME"
    
    print_message "$YELLOW" "Waiting for stack $PIPELINE_STACK_NAME to be deleted..."
    print_message "$YELLOW" "⏳ This may take several minutes"
    echo ""
    
    # Use AWS CLI wait command for reliable stack deletion monitoring
    if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "$PIPELINE_STACK_NAME" --region "$AWS_REGION"; then
        print_message "$GREEN" "✓ Stack $PIPELINE_STACK_NAME deleted successfully"
        echo ""
    else
        print_message "$RED" "Stack deletion failed or timed out"
        print_message "$RED" "Please check AWS Console for stack status"
        exit 1
    fi
else
    print_message "$YELLOW" "  ⚠ Could not delete: $PIPELINE_STACK_NAME (may not exist)"
fi

print_message "$GREEN" "✓ Pipeline cleanup complete"
echo ""

# Step 8: Clean up SAM build artifacts
echo "=========================================="
echo "Step 8: Cleaning up SAM build artifacts"
echo "=========================================="

# Find Lab5 SAM buckets (including bootstrap and pipeline artifacts)
PROFILE_ARG=$(get_profile_arg)
LAB5_SAM_BUCKETS=$(aws s3 $PROFILE_ARG ls | grep -E "aws-sam-cli-managed.*lab5|serverless-saas.*lab5|sam-bootstrap-bucket.*lab5|serverless-saas-pipeline-l-artifactsbucket" | awk '{print $3}')

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

# Step 9: Clean up CDK assets bucket
echo "=========================================="
echo "Step 9: Cleaning up CDK assets bucket"
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

# Step 10: Clean up CDK bootstrap resources (including CDKToolkit stack)
echo "=========================================="
echo "Step 10: Cleaning up CDK bootstrap resources"
echo "=========================================="

# CRITICAL: Check if Lab6 is deployed before deleting CDKToolkit
# CDKToolkit is a SHARED resource between Lab5 and Lab6
# We can only delete it if Lab6 is NOT deployed
PROFILE_ARG=$(get_profile_arg)
LAB6_DEPLOYED=false

# Check for Lab6 pipeline stack (uses CDK)
# Use || echo "" to prevent set -e from exiting when stack doesn't exist
LAB6_PIPELINE=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "serverless-saas-pipeline-lab6" --region "$AWS_REGION" 2>/dev/null || echo "")
if [[ -n "$LAB6_PIPELINE" ]]; then
  LAB6_DEPLOYED=true
  echo "⚠️  Lab6 pipeline stack detected - CDKToolkit is still in use"
fi

# Check for Lab6 shared stack (might have CDK dependencies)
if [[ "$LAB6_DEPLOYED" == false ]]; then
  LAB6_SHARED=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION" 2>/dev/null || echo "")
  if [[ -n "$LAB6_SHARED" ]]; then
    LAB6_DEPLOYED=true
    echo "⚠️  Lab6 shared stack detected - CDKToolkit might still be in use"
  fi
fi

# Find CDK bootstrap bucket
CDK_BUCKET=$(aws s3 $PROFILE_ARG ls --region "$AWS_REGION" | grep cdktoolkit | awk '{print $3}')

if [[ ! -z "$CDK_BUCKET" ]]; then
  echo "Found CDK bootstrap bucket: $CDK_BUCKET"
  
  if [[ "$LAB6_DEPLOYED" == true ]]; then
    echo "⚠️  Skipping CDK bucket deletion - Lab6 is still deployed and may need CDK resources"
  else
    empty_bucket $CDK_BUCKET
    echo "  Deleting bucket: $CDK_BUCKET"
    aws s3 $PROFILE_ARG rb s3://$CDK_BUCKET --region "$AWS_REGION" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  ✓ Bucket deleted: $CDK_BUCKET"
    else
      echo "  ⚠ Could not delete bucket: $CDK_BUCKET"
    fi
  fi
else
  echo "No CDK bootstrap bucket found"
fi

# Delete CDKToolkit stack only if Lab6 is NOT deployed
if [[ "$LAB6_DEPLOYED" == true ]]; then
  echo "⚠️  Skipping CDKToolkit stack deletion - Lab6 is still deployed"
  echo "   Lab6 pipeline stack uses the shared CDK execution role from CDKToolkit"
  echo "   CDKToolkit will be deleted when Lab6 is cleaned up"
else
  echo "✓ Lab6 is not deployed - safe to delete CDKToolkit"
  if delete_stack "CDKToolkit"; then
    wait_for_deletion "CDKToolkit"
  fi
fi

echo "✓ CDK bootstrap cleanup complete"
echo ""

# Step 11: Delete IAM roles (MUST be LAST after all stacks deleted)
echo "=========================================="
echo "Step 11: Cleaning up IAM roles"
echo "=========================================="

# List IAM roles with lab5 in the name
PROFILE_ARG=$(get_profile_arg)
IAM_ROLES=$(aws iam $PROFILE_ARG list-roles --query "Roles[?contains(RoleName, 'lab5')].RoleName" --output text 2>/dev/null || echo "")

if [[ ! -z "$IAM_ROLES" ]]; then
  echo "Found Lab5 IAM roles:"
  for role in $IAM_ROLES; do
    echo "  Processing IAM role: $role"
    
    # Detach managed policies
    ATTACHED_POLICIES=$(aws iam $PROFILE_ARG list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
    
    for policy_arn in $ATTACHED_POLICIES; do
      echo "    Detaching policy: $policy_arn"
      aws iam $PROFILE_ARG detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
    done
    
    # Delete inline policies
    INLINE_POLICIES=$(aws iam $PROFILE_ARG list-role-policies --role-name "$role" --query "PolicyNames[]" --output text 2>/dev/null || echo "")
    
    for policy_name in $INLINE_POLICIES; do
      echo "    Deleting inline policy: $policy_name"
      aws iam $PROFILE_ARG delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
    done
    
    # Delete the role
    echo "    Deleting role: $role"
    aws iam $PROFILE_ARG delete-role --role-name "$role" 2>/dev/null || true
  done
  echo "✓ IAM roles cleaned up"
else
  echo "No Lab5 IAM roles found"
fi

echo ""

# Step 12: Clean up Cognito User Pools
echo "=========================================="
echo "Step 12: Cleaning up Cognito User Pools"
echo "=========================================="

# Find and delete Lab5 Cognito User Pools
PROFILE_ARG=$(get_profile_arg)
LAB5_POOLS=$(aws cognito-idp $PROFILE_ARG list-user-pools --max-results 60 --output json 2>/dev/null | jq -r '.UserPools[] | select(.Name | contains("lab5")) | .Id')

if [[ ! -z "$LAB5_POOLS" ]]; then
  echo "Found Lab5 Cognito User Pools:"
  for pool_id in $LAB5_POOLS; do
    POOL_NAME=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Name' --output text 2>/dev/null || echo "")
    echo "  Processing pool: $POOL_NAME ($pool_id)"
    
    # Delete domain first if it exists
    DOMAIN=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Domain' --output text 2>/dev/null || echo "")
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

# Step 13: Verify cleanup
echo "=========================================="
echo "Step 13: Verifying cleanup"
echo "=========================================="

PROFILE_ARG=$(get_profile_arg)
REMAINING_EXPORTS=$(aws cloudformation $PROFILE_ARG list-exports --query 'Exports[?contains(Name, `lab5`)].Name' --output text 2>/dev/null || echo "")
if [[ ! -z "$REMAINING_EXPORTS" ]]; then
  echo "⚠ Warning: Some Lab5 exports still exist:"
  echo "$REMAINING_EXPORTS"
  echo "These should be cleaned up automatically when their stacks are deleted"
else
  echo "✓ No Lab5 exports remaining"
fi

echo ""

REMAINING_TABLES=$(aws dynamodb $PROFILE_ARG list-tables --query 'TableNames[?contains(@, `lab5`)]' --output text 2>/dev/null || echo "")
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
print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab5 Cleanup Complete!"
print_message "$GREEN" "Duration: ${CLEANUP_DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
