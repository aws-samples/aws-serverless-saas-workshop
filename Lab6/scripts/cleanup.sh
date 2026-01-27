#!/bin/bash

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

# AWS Profile should be passed via --profile parameter

# Lab6 Complete Cleanup Script
# Removes all Lab6 resources in the correct order to avoid dependency issues

# Default values
AWS_PROFILE=""
STACK_NAME_PREFIX="serverless-saas-lab6"  # Default prefix for stack names
AWS_REGION="us-east-1"  # Default region
SKIP_CONFIRMATION=0
LAB_ID="lab6"  # Lab identifier for resource filtering

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "  --stack-name <name>       Stack name prefix (default: serverless-saas-lab6)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <name>          AWS CLI profile name (optional, uses machine's default if not provided)"
    echo "  -y, --yes                 Skip confirmation prompt"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Clean up with default settings"
    echo "  $0 --stack-name serverless-saas-lab6            # Clean up specific lab"
    echo "  $0 --profile serverless-saas-demo               # Use specific AWS profile"
    echo "  $0 --stack-name my-lab --profile my-profile     # Clean up with custom stack name and profile"
    echo "  $0 -y                                           # Skip confirmation prompt"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME_PREFIX=$2
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
            echo "Unknown parameter: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

# Build AWS CLI profile argument if profile is specified
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab6 Complete Cleanup Script"
print_message "$BLUE" "=========================================="
echo "Started: $(date)"
echo "Log file: $LOG_FILE"
echo ""
print_message "$YELLOW" "This will delete:"
echo "  - All tenant stacks (stack-*)"
echo "  - Shared infrastructure stack"
echo "  - Pipeline stack"
echo "  - S3 buckets (will be emptied first)"
echo "  - Cognito User Pools"
echo "  - SAM and CDK resources"
echo ""

if [ $SKIP_CONFIRMATION -eq 0 ]; then
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
      echo "Cleanup cancelled"
      exit 0
    fi
fi

echo ""
print_message "$YELLOW" "Starting cleanup..."
echo ""

REGION=$(aws configure get region $PROFILE_ARG)
CLEANUP_START=$(date +%s)

# Function to empty S3 bucket (including all versions and delete markers)
empty_bucket() {
  local bucket=$1
  echo "  Emptying bucket: $bucket"
  
  # Check if bucket exists
  if ! aws s3api $PROFILE_ARG head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "  ⚠ Bucket does not exist: $bucket"
    return
  fi
  
  # Check if bucket has versioning enabled
  VERSIONING=$(aws s3api $PROFILE_ARG get-bucket-versioning --bucket $bucket --query 'Status' --output text 2>/dev/null)
  
  if [[ "$VERSIONING" == "Enabled" ]]; then
    echo "    Bucket has versioning enabled, deleting all versions..."
    
    # Delete all object versions in parallel batches
    aws s3api $PROFILE_ARG list-object-versions --bucket $bucket --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$bucket"' --key \"\(.Key)\" --version-id \"\(.VersionId)\" &"' | \
      bash 2>/dev/null
    wait
    
    # Delete all delete markers in parallel batches
    aws s3api $PROFILE_ARG list-object-versions --bucket $bucket --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$bucket"' --key \"\(.Key)\" --version-id \"\(.VersionId)\" &"' | \
      bash 2>/dev/null
    wait
  fi
  
  # Delete current objects (for non-versioned buckets or remaining objects)
  aws s3 $PROFILE_ARG rm s3://$bucket --recursive 2>/dev/null
  
  if [[ $? -eq 0 ]] || [[ "$VERSIONING" == "Enabled" ]]; then
    echo "  ✓ Bucket emptied: $bucket"
  else
    echo "  ⚠ Could not empty bucket: $bucket"
  fi
}

# Function to verify stack belongs to this lab
verify_stack_ownership() {
  local stack=$1
  
  # Check if stack name contains the lab identifier
  if [[ "$stack" == *"$LAB_ID"* ]]; then
    return 0  # Stack belongs to this lab
  else
    return 1  # Stack does not belong to this lab
  fi
}

# Function to delete stack
delete_stack() {
  local stack=$1
  echo "  Deleting stack: $stack"
  aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "  ✓ Delete initiated: $stack"
    return 0
  else
    echo "  ⚠ Could not delete: $stack (may not exist)"
    return 1
  fi
}

# Function to delete stack with CDK role handling
delete_stack_with_cdk_role() {
  local stack=$1
  local role_created=false
  
  echo "  Deleting stack: $stack"
  
  # Try to delete the stack normally first
  local delete_output=$(aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack 2>&1)
  local delete_status=$?
  
  # Check if deletion failed due to missing CDK role
  if [[ $delete_status -ne 0 ]] && echo "$delete_output" | grep -q "is invalid or cannot be assumed"; then
    echo "  ⚠ Stack requires CDK execution role that was deleted"
    echo "  Creating temporary CDK execution role..."
    
    # Extract account ID from the error message or use current account
    local account_id=$(aws sts $PROFILE_ARG get-caller-identity --query Account --output text 2>/dev/null)
    local role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-${AWS_REGION}"
    
    # Create temporary role
    aws iam $PROFILE_ARG create-role \
      --role-name "$role_name" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
      >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
      role_created=true
      echo "  ✓ Temporary role created: $role_name"
      
      # Attach admin policy
      aws iam $PROFILE_ARG attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
        >/dev/null 2>&1
      
      # Wait a moment for role to propagate
      sleep 3
      
      # Try deletion again
      aws cloudformation $PROFILE_ARG delete-stack --stack-name $stack 2>/dev/null
      if [[ $? -eq 0 ]]; then
        echo "  ✓ Delete initiated: $stack"
        
        # Wait for deletion to complete before cleaning up role
        echo "  Waiting for stack deletion to complete..."
        aws cloudformation $PROFILE_ARG wait stack-delete-complete --stack-name $stack 2>/dev/null
        
        # Clean up temporary role
        echo "  Cleaning up temporary CDK role..."
        aws iam $PROFILE_ARG detach-role-policy \
          --role-name "$role_name" \
          --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
          >/dev/null 2>&1
        
        aws iam $PROFILE_ARG delete-role \
          --role-name "$role_name" \
          >/dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
          echo "  ✓ Temporary CDK role deleted"
        else
          echo "  ⚠ Could not delete temporary role: $role_name"
          echo "    You may need to delete it manually"
        fi
        
        return 0
      else
        echo "  ✗ Failed to delete stack even with temporary role"
        
        # Try to clean up role even if stack deletion failed
        aws iam $PROFILE_ARG detach-role-policy \
          --role-name "$role_name" \
          --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
          >/dev/null 2>&1
        aws iam $PROFILE_ARG delete-role \
          --role-name "$role_name" \
          >/dev/null 2>&1
        
        return 1
      fi
    else
      echo "  ✗ Failed to create temporary CDK role"
      echo "    Please run the cleanup script again or delete the stack manually"
      return 1
    fi
  elif [[ $delete_status -eq 0 ]]; then
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
  aws cloudformation $PROFILE_ARG wait stack-delete-complete --stack-name $stack 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "  ✓ Deleted: $stack"
  else
    echo "  ⚠ Deletion may have failed or stack doesn't exist: $stack"
  fi
}

# Step 1: Delete tenant stacks (in parallel)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Deleting tenant stacks"
print_message "$BLUE" "=========================================="

TENANT_STACKS=$(aws cloudformation $PROFILE_ARG list-stacks \
  --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE CREATE_FAILED ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `stack-`) && contains(StackName, `lab6`)].StackName' \
  --output text 2>/dev/null)

if [[ -z "$TENANT_STACKS" ]]; then
  print_message "$YELLOW" "  No tenant stacks found"
else
  # Delete all tenant stacks in parallel
  for stack in $TENANT_STACKS; do
    delete_stack $stack
  done
  
  echo ""
  print_message "$YELLOW" "  Waiting for tenant stacks to delete (parallel)..."
  # Wait for all deletions in parallel
  for stack in $TENANT_STACKS; do
    wait_for_deletion $stack &
  done
  wait
fi

print_message "$GREEN" "✓ Tenant stacks cleanup complete"
echo ""

# Step 2: Identify resources from stacks (before deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Identifying resources from stacks"
print_message "$BLUE" "=========================================="

ADMIN_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 \
  --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null)
LANDING_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 \
  --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null)
APP_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 \
  --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text 2>/dev/null)

# Get API Gateway IDs for log deletion
SHARED_API_ID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 \
  --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" --output text 2>/dev/null)
TENANT_API_ID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-tenant-lab6 \
  --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" --output text 2>/dev/null)

echo "Found resources:"
[[ ! -z "$ADMIN_BUCKET" ]] && echo "  - S3 Bucket: $ADMIN_BUCKET (will delete after CloudFront)"
[[ ! -z "$LANDING_BUCKET" ]] && echo "  - S3 Bucket: $LANDING_BUCKET (will delete after CloudFront)"
[[ ! -z "$APP_BUCKET" ]] && echo "  - S3 Bucket: $APP_BUCKET (will delete after CloudFront)"
[[ ! -z "$SHARED_API_ID" ]] && echo "  - Shared API Gateway ID: $SHARED_API_ID"
[[ ! -z "$TENANT_API_ID" ]] && echo "  - Tenant API Gateway ID: $TENANT_API_ID"
echo ""

# Step 3: Delete CloudWatch Log Groups (BEFORE stack deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 3: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Delete API Gateway execution logs first
echo "Deleting API Gateway execution logs..."

# Delete logs for known API Gateway IDs
for api_id in "$SHARED_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        echo "  Deleting log group: $LOG_GROUP_NAME"
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" $PROFILE_ARG 2>/dev/null || true
    fi
done

# Check for orphaned API Gateway logs (logs where API Gateway no longer exists)
echo "Checking for orphaned API Gateway logs..."
ORPHANED_API_LOGS=$(aws logs describe-log-groups \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_API_LOGS" ]; then
    for log_group in $ORPHANED_API_LOGS; do
        # Extract API Gateway ID from log group name
        API_ID=$(echo "$log_group" | sed 's/API-Gateway-Execution-Logs_\([^/]*\).*/\1/')
        
        # Check if API Gateway still exists
        API_EXISTS=$(aws apigateway get-rest-api --rest-api-id "$API_ID" $PROFILE_ARG 2>/dev/null || echo "")
        
        # If API Gateway doesn't exist, delete the orphaned log group
        if [ -z "$API_EXISTS" ]; then
            echo "  Deleting orphaned log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" $PROFILE_ARG 2>/dev/null || true
        fi
    done
fi

print_message "$GREEN" "✓ API Gateway execution logs deleted"

# Delete Lambda function log groups
LOG_GROUPS=$(aws logs describe-log-groups \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'lab6')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        echo "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" $PROFILE_ARG 2>/dev/null || true
    done
    echo "✓ Lambda log groups deleted"
else
    echo "  No Lambda log groups found"
fi

print_message "$GREEN" "✓ CloudWatch Log Groups cleanup complete"
echo ""

# Step 4: Delete tenant template stack FIRST (depends on shared stack exports)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 4: Deleting tenant template stack"
print_message "$BLUE" "=========================================="

if delete_stack "serverless-saas-tenant-lab6"; then
  wait_for_deletion "serverless-saas-tenant-lab6"
fi

print_message "$GREEN" "✓ Tenant template cleanup complete"
echo ""

# Step 5: Delete shared stack (deletes CloudFront distributions)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 5: Deleting shared infrastructure (includes CloudFront)"
print_message "$BLUE" "=========================================="

if delete_stack "serverless-saas-shared-lab6"; then
  wait_for_deletion "serverless-saas-shared-lab6"
fi

print_message "$GREEN" "✓ Shared infrastructure cleanup complete (CloudFront deleted)"
echo ""

# Step 6: Safely delete S3 buckets (after CloudFront is deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 6: Safely deleting S3 buckets (CloudFront deleted)"
print_message "$BLUE" "=========================================="

# Empty buckets in parallel for faster cleanup
[[ ! -z "$ADMIN_BUCKET" ]] && empty_bucket $ADMIN_BUCKET &
[[ ! -z "$LANDING_BUCKET" ]] && empty_bucket $LANDING_BUCKET &
[[ ! -z "$APP_BUCKET" ]] && empty_bucket $APP_BUCKET &
wait

print_message "$GREEN" "✓ S3 buckets deleted (secure - CloudFront was deleted first)"
echo ""

# Step 7: Identify pipeline artifacts bucket
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 7: Identifying pipeline artifacts bucket"
print_message "$BLUE" "=========================================="

PIPELINE_BUCKET=$(aws s3 $PROFILE_ARG ls | grep "serverless-saas-pipeline-lab6-pipelineartifactsbucket" | awk '{print $3}')

if [[ ! -z "$PIPELINE_BUCKET" ]]; then
  print_message "$YELLOW" "Found pipeline bucket: $PIPELINE_BUCKET"
else
  print_message "$YELLOW" "No pipeline artifacts bucket found"
fi

echo ""

# Step 8: Empty pipeline artifacts bucket
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 8: Emptying pipeline artifacts bucket"
print_message "$BLUE" "=========================================="

if [[ ! -z "$PIPELINE_BUCKET" ]]; then
  empty_bucket $PIPELINE_BUCKET
fi

print_message "$GREEN" "✓ Pipeline artifacts emptied"
echo ""

# Step 9: Delete pipeline stack
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 9: Deleting pipeline"
print_message "$BLUE" "=========================================="

# Use the CDK role-aware deletion function for pipeline stack
delete_stack_with_cdk_role "serverless-saas-pipeline-lab6"

print_message "$GREEN" "✓ Pipeline cleanup complete"
echo ""

# Step 10: Clean up SAM build artifacts
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 10: Cleaning up SAM build artifacts"
print_message "$BLUE" "=========================================="

# Find Lab6 SAM buckets (including bootstrap and pipeline artifacts)
LAB6_SAM_BUCKETS=$(aws s3 $PROFILE_ARG ls | grep -E "aws-sam-cli-managed.*lab6|serverless-saas.*lab6|sam-bootstrap-bucket.*lab6|serverless-saas-pipeline-l-artifactsbucket" | awk '{print $3}')

if [[ ! -z "$LAB6_SAM_BUCKETS" ]]; then
  print_message "$YELLOW" "Found Lab6 SAM buckets:"
  for bucket in $LAB6_SAM_BUCKETS; do
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
  echo "No Lab6 SAM buckets found"
fi

print_message "$GREEN" "✓ SAM artifacts cleanup complete"
echo ""

# Step 11: Clean up CDK assets bucket
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 11: Cleaning up CDK assets bucket"
print_message "$BLUE" "=========================================="

CDK_ASSETS_BUCKET=$(aws s3 $PROFILE_ARG ls | grep "cdk-hnb659fds-assets" | awk '{print $3}')

if [[ ! -z "$CDK_ASSETS_BUCKET" ]]; then
  print_message "$YELLOW" "Found CDK assets bucket: $CDK_ASSETS_BUCKET"
  empty_bucket $CDK_ASSETS_BUCKET
  
  # Verify bucket is completely empty before deletion
  REMAINING_VERSIONS=$(aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --output json 2>/dev/null | jq -r '(.Versions // []) + (.DeleteMarkers // []) | length')
  
  if [[ "$REMAINING_VERSIONS" == "0" ]]; then
    print_message "$YELLOW" "  Deleting bucket: $CDK_ASSETS_BUCKET"
    aws s3 $PROFILE_ARG rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
    if [[ $? -eq 0 ]]; then
      print_message "$GREEN" "  ✓ Bucket deleted: $CDK_ASSETS_BUCKET"
    else
      print_message "$YELLOW" "  ⚠ Could not delete bucket: $CDK_ASSETS_BUCKET"
    fi
  else
    print_message "$YELLOW" "  ⚠ Warning: $REMAINING_VERSIONS versions/markers still exist in bucket"
    print_message "$YELLOW" "  Attempting force deletion of remaining versions..."
    
    # Force delete any remaining versions
    aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Force delete any remaining delete markers
    aws s3api $PROFILE_ARG list-object-versions --bucket $CDK_ASSETS_BUCKET --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[]? | "aws s3api '"$PROFILE_ARG"' delete-object --bucket '"$CDK_ASSETS_BUCKET"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
      bash 2>/dev/null
    
    # Try deletion again
    print_message "$YELLOW" "  Retrying bucket deletion: $CDK_ASSETS_BUCKET"
    aws s3 $PROFILE_ARG rb s3://$CDK_ASSETS_BUCKET 2>/dev/null
    if [[ $? -eq 0 ]]; then
      print_message "$GREEN" "  ✓ Bucket deleted: $CDK_ASSETS_BUCKET"
    else
      print_message "$YELLOW" "  ⚠ Could not delete bucket: $CDK_ASSETS_BUCKET (manual deletion may be required)"
    fi
  fi
else
  print_message "$YELLOW" "No CDK assets bucket found"
fi

print_message "$GREEN" "✓ CDK assets cleanup complete"
echo ""

# Step 12: Clean up CDK bootstrap resources (including CDKToolkit stack)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 12: Cleaning up CDK bootstrap resources"
print_message "$BLUE" "=========================================="

# Find CDK bootstrap bucket
CDK_BUCKET=$(aws s3 $PROFILE_ARG ls | grep cdktoolkit | awk '{print $3}')

if [[ ! -z "$CDK_BUCKET" ]]; then
  print_message "$YELLOW" "Found CDK bootstrap bucket: $CDK_BUCKET"
  empty_bucket $CDK_BUCKET
  print_message "$YELLOW" "  Deleting bucket: $CDK_BUCKET"
  aws s3 $PROFILE_ARG rb s3://$CDK_BUCKET 2>/dev/null
  if [[ $? -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Bucket deleted: $CDK_BUCKET"
  else
    print_message "$YELLOW" "  ⚠ Could not delete bucket: $CDK_BUCKET"
  fi
else
  print_message "$YELLOW" "No CDK bootstrap bucket found"
fi

# Delete CDKToolkit stack (moved here to be AFTER pipeline stack deletion)
if delete_stack "CDKToolkit"; then
  wait_for_deletion "CDKToolkit"
fi

print_message "$GREEN" "✓ CDK bootstrap cleanup complete"
echo ""

# Step 13: Delete IAM roles (MUST be LAST after all stacks deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 13: Cleaning up IAM roles"
print_message "$BLUE" "=========================================="

# List IAM roles with lab6 in the name
IAM_ROLES=$(aws iam $PROFILE_ARG list-roles --query "Roles[?contains(RoleName, 'lab6')].RoleName" --output text 2>/dev/null || echo "")

if [[ ! -z "$IAM_ROLES" ]]; then
  print_message "$YELLOW" "Found Lab6 IAM roles:"
  for role in $IAM_ROLES; do
    print_message "$YELLOW" "  Processing IAM role: $role"
    
    # Detach managed policies
    ATTACHED_POLICIES=$(aws iam $PROFILE_ARG list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
    
    for policy_arn in $ATTACHED_POLICIES; do
      print_message "$YELLOW" "    Detaching policy: $policy_arn"
      aws iam $PROFILE_ARG detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
    done
    
    # Delete inline policies
    INLINE_POLICIES=$(aws iam $PROFILE_ARG list-role-policies --role-name "$role" --query "PolicyNames[]" --output text 2>/dev/null || echo "")
    
    for policy_name in $INLINE_POLICIES; do
      print_message "$YELLOW" "    Deleting inline policy: $policy_name"
      aws iam $PROFILE_ARG delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
    done
    
    # Delete the role
    print_message "$YELLOW" "    Deleting role: $role"
    aws iam $PROFILE_ARG delete-role --role-name "$role" 2>/dev/null || true
  done
  print_message "$GREEN" "✓ IAM roles cleaned up"
else
  print_message "$YELLOW" "No Lab6 IAM roles found"
fi

echo ""

# Step 14: Clean up Cognito User Pools
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 14: Cleaning up Cognito User Pools"
print_message "$BLUE" "=========================================="

# Find and delete Lab6 Cognito User Pools
LAB6_POOLS=$(aws cognito-idp $PROFILE_ARG list-user-pools --max-results 60 --output json 2>/dev/null | jq -r '.UserPools[] | select(.Name | contains("lab6")) | .Id')

if [[ ! -z "$LAB6_POOLS" ]]; then
  print_message "$YELLOW" "Found Lab6 Cognito User Pools:"
  for pool_id in $LAB6_POOLS; do
    POOL_NAME=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Name' --output text 2>/dev/null)
    print_message "$YELLOW" "  Processing pool: $POOL_NAME ($pool_id)"
    
    # Delete domain first if it exists
    DOMAIN=$(aws cognito-idp $PROFILE_ARG describe-user-pool --user-pool-id $pool_id --query 'UserPool.Domain' --output text 2>/dev/null)
    if [[ ! -z "$DOMAIN" && "$DOMAIN" != "None" ]]; then
      print_message "$YELLOW" "    Deleting domain: $DOMAIN"
      aws cognito-idp $PROFILE_ARG delete-user-pool-domain --domain $DOMAIN --user-pool-id $pool_id 2>/dev/null
      sleep 5
    fi
    
    # Now delete the pool
    print_message "$YELLOW" "    Deleting pool: $POOL_NAME"
    aws cognito-idp $PROFILE_ARG delete-user-pool --user-pool-id $pool_id 2>/dev/null
    if [[ $? -eq 0 ]]; then
      print_message "$GREEN" "  ✓ Pool deleted: $POOL_NAME"
    else
      print_message "$YELLOW" "  ⚠ Could not delete pool: $POOL_NAME"
    fi
  done
else
  print_message "$YELLOW" "No Lab6 Cognito User Pools found"
fi

print_message "$GREEN" "✓ Cognito User Pools cleanup complete"
echo ""

# Step 15: Verify cleanup
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 15: Verifying cleanup"
print_message "$BLUE" "=========================================="

REMAINING_EXPORTS=$(aws cloudformation $PROFILE_ARG list-exports --query 'Exports[?contains(Name, `lab6`)].Name' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_EXPORTS" ]]; then
  print_message "$YELLOW" "⚠ Warning: Some Lab6 exports still exist:"
  echo "$REMAINING_EXPORTS"
  print_message "$YELLOW" "These should be cleaned up automatically when their stacks are deleted"
else
  print_message "$GREEN" "✓ No Lab6 exports remaining"
fi

echo ""

REMAINING_TABLES=$(aws dynamodb $PROFILE_ARG list-tables --query 'TableNames[?contains(@, `lab6`)]' --output text 2>/dev/null)
if [[ ! -z "$REMAINING_TABLES" ]]; then
  print_message "$YELLOW" "⚠ Warning: Some Lab6 DynamoDB tables still exist:"
  echo "$REMAINING_TABLES"
  print_message "$YELLOW" "These should be cleaned up automatically when the shared stack is deleted"
else
  print_message "$GREEN" "✓ No Lab6 DynamoDB tables remaining"
fi

echo ""

REMAINING_STACKS=$(aws cloudformation $PROFILE_ARG list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `lab6`)].StackName' \
  --output text 2>/dev/null)
if [[ ! -z "$REMAINING_STACKS" ]]; then
  print_message "$YELLOW" "⚠ Warning: Some stacks still exist:"
  echo "$REMAINING_STACKS"
else
  print_message "$GREEN" "✓ No Lab6 stacks remaining"
fi

CLEANUP_END=$(date +%s)
CLEANUP_DURATION=$((CLEANUP_END - CLEANUP_START))
CLEANUP_MINUTES=$((CLEANUP_DURATION / 60))
CLEANUP_SECONDS=$((CLEANUP_DURATION % 60))

echo ""
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Cleanup Complete!"
print_message "$BLUE" "=========================================="
print_message "$GREEN" "Completed: $(date)"
print_message "$GREEN" "Duration: ${CLEANUP_MINUTES}m ${CLEANUP_SECONDS}s"
print_message "$GREEN" "Log file: $LOG_FILE"
echo ""
print_message "$YELLOW" "You can now run a fresh deployment:"
print_message "$YELLOW" "  cd Lab6/scripts"
print_message "$YELLOW" "  ./deploy-with-screen.sh    # Recommended for long deployments"
print_message "$YELLOW" "  ./deployment.sh -s -c      # Direct deployment"
echo ""
