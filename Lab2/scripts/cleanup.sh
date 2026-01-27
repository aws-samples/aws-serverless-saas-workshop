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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="serverless-saas-lab2"
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified
SKIP_CONFIRMATION=0
LAB_ID="lab2"  # Lab identifier for resource filtering

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Lab2 Cleanup Script"
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

# Function to build AWS CLI profile argument
# Returns "--profile <profile>" if AWS_PROFILE is set, empty string otherwise
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME=$2
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
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name <name>  CloudFormation stack name to cleanup (default: serverless-saas-lab2)"
            echo "  --region <region>    AWS region (default: us-east-1)"
            echo "  --profile <profile>  AWS CLI profile name (optional, uses default profile if not specified)"
            echo "  -y, --yes            Skip confirmation prompt"
            echo "  --help               Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --stack-name serverless-saas-lab2"
            echo "  $0 --stack-name my-stack --region us-east-1"
            echo "  $0 --stack-name my-stack --profile my-profile"
            echo "  $0 --stack-name serverless-saas-lab2 -y"
            exit 0
            ;;
        *)
            print_message "$RED" "Unknown parameter: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_message "$YELLOW" "Starting cleanup of Lab2 resources..."
print_message "$YELLOW" "Stack name: $STACK_NAME"
print_message "$YELLOW" "AWS Region: $AWS_REGION"
if [[ -n "$AWS_PROFILE" ]]; then
    print_message "$YELLOW" "AWS Profile: $AWS_PROFILE"
else
    print_message "$YELLOW" "AWS Profile: (using machine's default profile)"
fi
echo ""

# Confirmation prompt
if [ $SKIP_CONFIRMATION -eq 0 ]; then
    print_message "$YELLOW" "⚠️  WARNING: This will permanently delete all Lab2 resources!"
    print_message "$YELLOW" "Stack: $STACK_NAME"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        exit 0
    fi
fi

# Record start time
START_TIME=$(date +%s)

# Step 1: Get S3 bucket names and API Gateway IDs from stack outputs (but don't delete yet)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Identifying resources from stack"
print_message "$BLUE" "=========================================="

# Build profile argument
PROFILE_ARG=$(get_profile_arg)

# Get bucket names from stack outputs
ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Report found buckets (will delete after CloudFront)
for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_APP_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
        print_message "$GREEN" "  Found S3 bucket: $bucket (will delete after CloudFront)"
    fi
done

# Get API Gateway IDs from stack outputs (before stack is deleted)
ADMIN_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

TENANT_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$ADMIN_API_ID" ] && [ "$ADMIN_API_ID" != "None" ]; then
    print_message "$GREEN" "  Found Admin API Gateway ID: $ADMIN_API_ID"
fi

if [ -n "$TENANT_API_ID" ] && [ "$TENANT_API_ID" != "None" ]; then
    print_message "$GREEN" "  Found Tenant API Gateway ID: $TENANT_API_ID"
fi

# Step 2: Delete CloudWatch Log Groups (BEFORE deleting the stack)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Delete API Gateway execution logs
for api_id in "$ADMIN_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        if aws logs describe-log-groups $PROFILE_ARG --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[0].logGroupName" --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
            print_message "$YELLOW" "  Deleting API Gateway log group: $LOG_GROUP_NAME"
            aws logs delete-log-group $PROFILE_ARG --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  API Gateway log group deleted"
        else
            print_message "$YELLOW" "  API Gateway log group not found"
        fi
    fi
done

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

if aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
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
        exit 1
    fi
else
    print_message "$YELLOW" "  Stack $STACK_NAME not found"
fi

# Step 4: Now safely delete S3 buckets (after CloudFront is deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 4: Safely deleting S3 buckets (CloudFront deleted)"
print_message "$BLUE" "=========================================="

# Empty and delete application buckets
for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_APP_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
        if aws s3 ls "s3://$bucket" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
            print_message "$YELLOW" "  Emptying bucket: $bucket"
            aws s3 rm "s3://$bucket" $PROFILE_ARG --recursive --region "$AWS_REGION" 2>/dev/null || true
            print_message "$YELLOW" "  Deleting bucket: $bucket"
            aws s3 rb "s3://$bucket" $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  S3 bucket deleted: $bucket"
        else
            print_message "$YELLOW" "  Bucket already deleted or not found: $bucket"
        fi
    fi
done

# Clean up SAM bootstrap bucket from samconfig.toml
print_message "$YELLOW" "Cleaning up SAM bootstrap bucket from samconfig.toml..."

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

print_message "$GREEN" "S3 buckets deleted"

# Step 5: Delete CloudWatch Log Groups
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 5: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Get API Gateway IDs from stack outputs to delete their execution logs
ADMIN_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

TENANT_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Delete API Gateway execution logs
for api_id in "$ADMIN_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        if aws logs describe-log-groups $PROFILE_ARG --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[0].logGroupName" --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
            print_message "$YELLOW" "  Deleting API Gateway log group: $LOG_GROUP_NAME"
            aws logs delete-log-group $PROFILE_ARG --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
        fi
    fi
done

# Fallback: Search for any orphaned API Gateway logs that might belong to this lab
print_message "$YELLOW" "  Checking for orphaned API Gateway logs..."
ORPHANED_API_LOGS=$(aws logs describe-log-groups \
    $PROFILE_ARG \
    --region "$AWS_REGION" \
    --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_API_LOGS" ]; then
    print_message "$YELLOW" "  Found orphaned API Gateway logs - checking if they belong to this lab..."
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
fi

print_message "$GREEN" "CloudWatch Log Groups deleted"

# Step 6: Verify cleanup
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 6: Verifying cleanup"
print_message "$BLUE" "=========================================="

REMAINING_RESOURCES=0

# Check for remaining stacks
if aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    print_message "$RED" "  Warning: Stack $STACK_NAME still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

if [ $REMAINING_RESOURCES -eq 0 ]; then
    print_message "$GREEN" "All Lab2 resources have been cleaned up successfully!"
else
    print_message "$YELLOW" "Some resources may still exist. Please check manually."
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab2 Cleanup Complete!"
print_message "$GREEN" "Duration: ${DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
