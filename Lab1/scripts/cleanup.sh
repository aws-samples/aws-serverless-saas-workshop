#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# SECURITY NOTE: Deletion Order is Critical!
# ============================================
# This script follows a specific deletion order to prevent CloudFront Origin Hijacking:
# 1. Delete CloudFormation stack (which deletes CloudFront distributions)
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

# Source exit codes module
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"

# Default stack name for Lab1
DEFAULT_STACK_NAME="serverless-saas-lab1"
LAB_NUMBER="1"
LAB_ID="lab1"  # Lab identifier for resource filtering

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab1-cleanup.log"
else
    # Individual Lab Mode: Create timestamped directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_DIR="logs/$TIMESTAMP"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/cleanup.log"
fi

# Redirect all output to log file and console
# Skip if running in test mode (test framework handles logging)
if [[ -z "$E2E_TEST_MODE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo "========================================"
echo "Lab1 Cleanup Script"
echo "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
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

# Parse command line arguments using template
parse_cleanup_parameters "$@"

print_message "$YELLOW" "Starting cleanup of Lab1 resources..."
display_cleanup_configuration

# Confirmation prompt
if [ $SKIP_CONFIRMATION -eq 0 ]; then
    print_message "$YELLOW" "⚠️  WARNING: This will permanently delete all Lab1 resources!"
    print_message "$YELLOW" "Stack: $STACK_NAME"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"
    fi
fi

# Setup exit handlers for graceful shutdown
setup_exit_handlers

# Record start time
START_TIME=$(date +%s)

# Step 1: Get S3 bucket names and API Gateway IDs from stack outputs (but don't delete yet)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Identifying resources from stack"
print_message "$BLUE" "=========================================="

APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"} \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$APP_SITE_BUCKET" ] && [ "$APP_SITE_BUCKET" != "None" ]; then
    print_message "$GREEN" "  Found S3 bucket: $APP_SITE_BUCKET (will delete after CloudFront)"
else
    print_message "$YELLOW" "  No S3 bucket found in stack outputs"
fi

# Get API Gateway ID from stack outputs (before stack is deleted)
API_GATEWAY_ID=$(aws cloudformation describe-stacks \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"} \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='APIGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$API_GATEWAY_ID" ] && [ "$API_GATEWAY_ID" != "None" ]; then
    print_message "$GREEN" "  Found API Gateway ID: $API_GATEWAY_ID"
else
    print_message "$YELLOW" "  No API Gateway ID found in stack outputs"
fi

# Step 2: Delete CloudWatch Log Groups (BEFORE deleting the stack)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Delete API Gateway execution logs
if [ -n "$API_GATEWAY_ID" ] && [ "$API_GATEWAY_ID" != "None" ]; then
    LOG_GROUP_NAME="API-Gateway-Execution-Logs_${API_GATEWAY_ID}/prod"
    if aws logs describe-log-groups $PROFILE_ARG --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[0].logGroupName" --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        print_message "$YELLOW" "  Deleting API Gateway log group: $LOG_GROUP_NAME"
        aws logs delete-log-group $PROFILE_ARG --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  API Gateway log group deleted"
    else
        print_message "$YELLOW" "  API Gateway log group not found"
    fi
else
    print_message "$YELLOW" "  Could not get API Gateway ID from stack (stack may not exist)"
fi

# Delete Lambda function log groups
LOG_GROUPS=$(aws logs describe-log-groups \
    $PROFILE_ARG \
    --region "$AWS_REGION" \
    --query "logGroups[?contains(logGroupName, '/aws/lambda/') && contains(logGroupName, '$STACK_NAME')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        print_message "$YELLOW" "  Deleting Lambda log group: $log_group"
        aws logs delete-log-group $PROFILE_ARG --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
    done
    print_message "$GREEN" "  Lambda log groups deleted"
else
    print_message "$YELLOW" "  No Lambda log groups found"
fi

# Fallback: Search for any orphaned API Gateway logs
print_message "$YELLOW" "  Checking for orphaned API Gateway logs..."
ORPHANED_API_LOGS=$(aws logs describe-log-groups \
    $PROFILE_ARG \
    --region "$AWS_REGION" \
    --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_API_LOGS" ]; then
    print_message "$YELLOW" "  Found orphaned API Gateway logs - checking if they belong to deleted APIs..."
    for log_group in $ORPHANED_API_LOGS; do
        # Extract API Gateway ID from log group name
        api_id=$(echo "$log_group" | sed 's/API-Gateway-Execution-Logs_\(.*\)\/prod/\1/')
        
        # Check if this API Gateway still exists
        api_exists=$(aws apigateway get-rest-api --rest-api-id "$api_id" $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [ -z "$api_exists" ]; then
            print_message "$YELLOW" "  Deleting orphaned API Gateway log group: $log_group (API Gateway no longer exists)"
            aws logs delete-log-group $PROFILE_ARG --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
else
    print_message "$GREEN" "  No orphaned API Gateway logs found"
fi

print_message "$GREEN" "CloudWatch Log Groups cleanup complete"

# Step 3: Delete CloudFormation stack (this will delete CloudFront distributions)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 3: Deleting CloudFormation stack"
print_message "$BLUE" "=========================================="
print_message "$YELLOW" "  Deleting stack: $STACK_NAME"

STACK_EXISTS=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$STACK_EXISTS" ]; then
    aws cloudformation delete-stack $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION"
    
    print_message "$YELLOW" "Waiting for stack $STACK_NAME to be deleted..."
    print_message "$YELLOW" "⏳ This may take 15-30 minutes for CloudFront distributions to fully delete"
    print_message "$YELLOW" "⏳ DO NOT interrupt this process - CloudFront must be fully deleted before S3 buckets"
    echo ""
    
    # Use AWS CLI wait command for reliable stack deletion monitoring
    if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION"; then
        print_message "$GREEN" "✓ Stack $STACK_NAME deleted successfully (including CloudFront distributions)"
        print_message "$GREEN" "✓ CloudFront distributions are fully deleted - safe to delete S3 buckets"
        echo ""
    else
        print_message "$RED" "Stack deletion failed or timed out"
        print_message "$RED" "Please check AWS Console for stack status"
        exit_with_code $EXIT_FAILURE "Stack deletion failed: $STACK_NAME"
    fi
else
    print_message "$YELLOW" "  Stack $STACK_NAME not found"
fi

# Step 4: Now safely delete S3 buckets (after CloudFront is deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 4: Safely deleting S3 buckets (CloudFront deleted)"
print_message "$BLUE" "=========================================="

if [ -n "$APP_SITE_BUCKET" ] && [ "$APP_SITE_BUCKET" != "None" ]; then
    if aws s3 ls "s3://$APP_SITE_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $APP_SITE_BUCKET"
        aws s3 rm "s3://$APP_SITE_BUCKET" --recursive ${AWS_PROFILE:+--profile "$AWS_PROFILE"} --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $APP_SITE_BUCKET"
        aws s3api delete-bucket --bucket $APP_SITE_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  S3 bucket deleted"
    else
        print_message "$YELLOW" "  Bucket already deleted or not found"
    fi
fi

# Step 5: Clean up any remaining S3 buckets
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 5: Cleaning up any remaining S3 buckets"
print_message "$BLUE" "=========================================="

REMAINING_BUCKETS=$(aws s3 ls $PROFILE_ARG | grep "serverless-saas-lab1" | awk '{print $3}' || echo "")

if [ -n "$REMAINING_BUCKETS" ]; then
    for bucket in $REMAINING_BUCKETS; do
        print_message "$YELLOW" "  Deleting bucket: $bucket"
        aws s3 rb "s3://$bucket" --force $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
    done
    print_message "$GREEN" "Remaining S3 buckets deleted"
else
    print_message "$YELLOW" "  No remaining S3 buckets found"
fi

# Step 6: Clean up SAM bootstrap bucket from samconfig.toml
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 6: Cleaning up SAM bootstrap bucket from samconfig.toml"
print_message "$BLUE" "=========================================="

# Get the bucket name from samconfig.toml
SAM_BUCKET=$(grep s3_bucket ../server/samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found SAM bucket in samconfig.toml: $SAM_BUCKET"
    if aws s3 ls "s3://$SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $SAM_BUCKET"
        aws s3 rm "s3://$SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $SAM_BUCKET"
        aws s3api delete-bucket --bucket $SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No SAM bucket found in samconfig.toml"
fi
echo ""

# Step 7: Verify cleanup
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 7: Verifying cleanup"
print_message "$BLUE" "=========================================="

REMAINING_RESOURCES=0

# Check for remaining stacks
STACK_CHECK=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$STACK_CHECK" ]; then
    print_message "$RED" "  Warning: Stack $STACK_NAME still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

# Check for remaining S3 buckets
REMAINING_BUCKETS=$(aws s3 ls $PROFILE_ARG | grep "serverless-saas-lab1" | awk '{print $3}' || echo "")

if [ -n "$REMAINING_BUCKETS" ]; then
    print_message "$RED" "  Warning: S3 buckets still exist: $REMAINING_BUCKETS"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

if [ $REMAINING_RESOURCES -eq 0 ]; then
    print_message "$GREEN" "All Lab1 resources have been cleaned up successfully!"
else
    print_message "$YELLOW" "Some resources may still exist. Please check manually."
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab1 Cleanup Complete!"
print_message "$GREEN" "Duration: ${DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"

# Final verification using cleanup-verification module
echo ""
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Final Verification"
print_message "$BLUE" "=========================================="

source "$SCRIPT_DIR/../../scripts/lib/cleanup-verification.sh"

if verify_complete_cleanup "$LAB_ID" "$PROFILE_ARG"; then
    print_message "$GREEN" "✓ All Lab1 resources successfully deleted"
    exit_with_code $EXIT_SUCCESS "Lab1 cleanup completed successfully"
else
    verification_exit_code=$?
    if [ $verification_exit_code -eq 3 ]; then
        print_message "$YELLOW" "⚠ Cleanup completed but orphaned resources detected"
        print_message "$YELLOW" "  See manual cleanup commands above"
        exit_with_code $EXIT_ORPHANED_RESOURCES "Orphaned resources detected after cleanup"
    else
        print_message "$RED" "✗ Verification failed"
        exit_with_code $EXIT_FAILURE "Cleanup verification failed"
    fi
fi
