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
AWS_REGION="us-east-1"
AWS_PROFILE=""
STACK_NAME=""
SKIP_CONFIRMATION=0
LAB_ID="lab3"  # Lab identifier for resource filtering

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

# Function to print usage
print_usage() {
    echo "Usage: $0 --stack-name <CloudFormation stack name> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       CloudFormation stack name prefix (required, e.g., serverless-saas-lab3)"
    echo "  --profile <profile>       AWS CLI profile name (optional, uses default profile if not specified)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  -y, --yes                 Skip confirmation prompt"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --stack-name serverless-saas-lab3"
    echo "  $0 --stack-name serverless-saas-lab3 --profile serverless-saas-demo"
    echo "  $0 --stack-name serverless-saas-lab3 --profile serverless-saas-demo -y"
    echo "  $0 --stack-name my-stack --profile my-profile --region us-east-1"
    echo ""
    echo "Note: This will clean up both shared and tenant stacks:"
    echo "  - <stack-name>-shared (e.g., serverless-saas-lab3-shared)"
    echo "  - <stack-name>-tenant (e.g., serverless-saas-lab3-tenant)"
}

# Check if no arguments provided
if [ $# -eq 0 ]; then
    print_message "$RED" "Error: Stack name is required"
    echo ""
    print_usage
    exit 1
fi

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME=$2
            shift 2
            ;;
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
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

# Validate required parameters
if [[ -z "$STACK_NAME" ]]; then
    print_message "$RED" "Error: --stack-name parameter is required"
    echo ""
    print_usage
    exit 1
fi

# Derive shared and tenant stack names from base stack name
# If user provides "serverless-saas-lab3", we create:
#   - serverless-saas-shared-lab3 (shared stack)
#   - serverless-saas-tenant-lab3 (tenant stack)
# If user provides "serverless-saas-shared-lab3", we use it as-is for shared stack
if [[ "$STACK_NAME" == *"-shared-lab3" ]]; then
    # User provided the full shared stack name
    SHARED_STACK_NAME="$STACK_NAME"
    # Derive tenant stack name by replacing "shared" with "tenant"
    TENANT_STACK_NAME="${STACK_NAME/-shared-/-tenant-}"
elif [[ "$STACK_NAME" == *"-lab3" ]]; then
    # User provided base name like "serverless-saas-lab3"
    # Extract prefix (e.g., "serverless-saas" from "serverless-saas-lab3")
    PREFIX="${STACK_NAME%-lab3}"
    SHARED_STACK_NAME="${PREFIX}-shared-lab3"
    TENANT_STACK_NAME="${PREFIX}-tenant-lab3"
else
    # If stack name doesn't end with -lab3, assume it's a custom name
    SHARED_STACK_NAME="${STACK_NAME}-shared"
    TENANT_STACK_NAME="${STACK_NAME}-tenant"
fi

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$YELLOW" "=========================================="
print_message "$YELLOW" "Lab3 Cleanup Script"
print_message "$YELLOW" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using default)"
fi
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Tenant Stack: $TENANT_STACK_NAME"
echo ""

print_message "$YELLOW" "Starting cleanup of Lab3 resources..."
echo ""

# Confirmation prompt (unless -y/--yes flag is used)
if [[ $SKIP_CONFIRMATION -eq 0 ]]; then
    print_message "$YELLOW" "⚠️  WARNING: This will delete all Lab3 resources including:"
    echo "  - CloudFormation stacks: $SHARED_STACK_NAME, $TENANT_STACK_NAME"
    echo "  - S3 buckets and their contents"
    echo "  - DynamoDB tables"
    echo "  - CloudWatch log groups"
    echo "  - SAM deployment buckets"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_message "$YELLOW" "Cleanup cancelled by user"
        exit 0
    fi
    echo ""
fi

# Record start time
START_TIME=$(date +%s)

# Step 1: Delete tenant stacks with lab-specific filtering
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Deleting tenant stacks for $LAB_ID"
print_message "$BLUE" "=========================================="

# Query for tenant stacks with lab-specific filtering
# Pattern: stack-* AND contains lab3
if [[ -n "$AWS_PROFILE" ]]; then
    TENANT_STACKS=$(aws cloudformation list-stacks \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, '$LAB_ID') && starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
        --output text 2>/dev/null || echo "")
else
    TENANT_STACKS=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, '$LAB_ID') && starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
        --output text 2>/dev/null || echo "")
fi

if [ -n "$TENANT_STACKS" ]; then
    print_message "$GREEN" "Found tenant stacks for $LAB_ID:"
    for stack in $TENANT_STACKS; do
        print_message "$GREEN" "  - $stack"
    done
    echo ""
    
    # Delete each tenant stack with verification
    for stack in $TENANT_STACKS; do
        if verify_stack_ownership "$stack" "$LAB_ID"; then
            print_message "$YELLOW" "  Deleting stack: $stack"
            if [[ -n "$AWS_PROFILE" ]]; then
                aws cloudformation delete-stack --profile "$AWS_PROFILE" --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null || true
            else
                aws cloudformation delete-stack --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null || true
            fi
            print_message "$GREEN" "  ✓ Delete initiated: $stack"
        else
            print_message "$YELLOW" "  Skipping stack: $stack (not owned by $LAB_ID)"
        fi
    done
    
    # Wait for deletion
    print_message "$YELLOW" "Waiting for tenant stacks to delete..."
    for stack in $TENANT_STACKS; do
        if verify_stack_ownership "$stack" "$LAB_ID"; then
            print_message "$YELLOW" "  Waiting for deletion: $stack"
            if [[ -n "$AWS_PROFILE" ]]; then
                aws cloudformation wait stack-delete-complete --profile "$AWS_PROFILE" --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null || true
            else
                aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null || true
            fi
            print_message "$GREEN" "  ✓ Deleted: $stack"
        fi
    done
    
    print_message "$GREEN" "✓ Tenant stacks cleanup complete for $LAB_ID"
else
    print_message "$YELLOW" "No tenant stacks found for $LAB_ID"
fi
echo ""

# Step 2: Identify resources from stacks (before deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 2: Identifying resources from stacks"
print_message "$BLUE" "=========================================="

# Get bucket names from shared stack outputs
if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --profile "$AWS_PROFILE" \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")

    LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --profile "$AWS_PROFILE" \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")

    APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --profile "$AWS_PROFILE" \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    # Get API Gateway IDs for log deletion
    SHARED_API_ID=$(aws cloudformation describe-stacks \
        --profile "$AWS_PROFILE" \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    TENANT_API_ID=$(aws cloudformation describe-stacks \
        --profile "$AWS_PROFILE" \
        --stack-name "$TENANT_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" \
        --output text 2>/dev/null || echo "")
else
    ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")

    LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")

    APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    # Get API Gateway IDs for log deletion
    SHARED_API_ID=$(aws cloudformation describe-stacks \
        --stack-name "$SHARED_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    TENANT_API_ID=$(aws cloudformation describe-stacks \
        --stack-name "$TENANT_STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" \
        --output text 2>/dev/null || echo "")
fi

# Report found resources
for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_APP_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
        print_message "$GREEN" "  Found S3 bucket: $bucket (will delete after CloudFront)"
    fi
done

if [ -n "$SHARED_API_ID" ] && [ "$SHARED_API_ID" != "None" ]; then
    print_message "$GREEN" "  Found Shared API Gateway ID: $SHARED_API_ID"
fi

if [ -n "$TENANT_API_ID" ] && [ "$TENANT_API_ID" != "None" ]; then
    print_message "$GREEN" "  Found Tenant API Gateway ID: $TENANT_API_ID"
fi

# Step 3: Delete CloudWatch Log Groups (BEFORE stack deletion)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 3: Deleting CloudWatch Log Groups"
print_message "$BLUE" "=========================================="

# Delete API Gateway execution logs first
print_message "$YELLOW" "  Deleting API Gateway execution logs..."

# Delete logs for known API Gateway IDs
for api_id in "$SHARED_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        print_message "$YELLOW" "    Deleting log group: $LOG_GROUP_NAME"
        if [[ -n "$AWS_PROFILE" ]]; then
            aws logs delete-log-group --profile "$AWS_PROFILE" --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
        else
            aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true
        fi
    fi
done

# Check for orphaned API Gateway logs (logs where API Gateway no longer exists)
print_message "$YELLOW" "  Checking for orphaned API Gateway logs..."
if [[ -n "$AWS_PROFILE" ]]; then
    ORPHANED_API_LOGS=$(aws logs describe-log-groups \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
        --output text 2>/dev/null || echo "")
else
    ORPHANED_API_LOGS=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
        --output text 2>/dev/null || echo "")
fi

if [ -n "$ORPHANED_API_LOGS" ]; then
    for log_group in $ORPHANED_API_LOGS; do
        # Extract API Gateway ID from log group name
        API_ID=$(echo "$log_group" | sed 's/API-Gateway-Execution-Logs_\([^/]*\).*/\1/')
        
        # Check if API Gateway still exists
        if [[ -n "$AWS_PROFILE" ]]; then
            API_EXISTS=$(aws apigateway get-rest-api --profile "$AWS_PROFILE" --rest-api-id "$API_ID" --region "$AWS_REGION" 2>/dev/null || echo "")
        else
            API_EXISTS=$(aws apigateway get-rest-api --rest-api-id "$API_ID" --region "$AWS_REGION" 2>/dev/null || echo "")
        fi
        
        # If API Gateway doesn't exist, delete the orphaned log group
        if [ -z "$API_EXISTS" ]; then
            print_message "$YELLOW" "    Deleting orphaned log group: $log_group"
            if [[ -n "$AWS_PROFILE" ]]; then
                aws logs delete-log-group --profile "$AWS_PROFILE" --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
            else
                aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
            fi
        fi
    done
fi

print_message "$GREEN" "  API Gateway execution logs deleted"

# Delete Lambda function log groups
if [[ -n "$AWS_PROFILE" ]]; then
    LOG_GROUPS=$(aws logs describe-log-groups \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, 'lab3')].logGroupName" \
        --output text 2>/dev/null || echo "")
else
    LOG_GROUPS=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, 'lab3')].logGroupName" \
        --output text 2>/dev/null || echo "")
fi

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        print_message "$YELLOW" "  Deleting log group: $log_group"
        if [[ -n "$AWS_PROFILE" ]]; then
            aws logs delete-log-group --profile "$AWS_PROFILE" --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
        else
            aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    print_message "$GREEN" "CloudWatch Log Groups deleted"
else
    print_message "$YELLOW" "  No CloudWatch Log Groups found"
fi

# Step 4: Delete tenant stack first (dependencies)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 4: Deleting tenant stack"
print_message "$BLUE" "=========================================="
print_message "$YELLOW" "  Deleting stack: $TENANT_STACK_NAME"

if [[ -n "$AWS_PROFILE" ]]; then
    if aws cloudformation describe-stacks --profile "$AWS_PROFILE" --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        aws cloudformation delete-stack --profile "$AWS_PROFILE" --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION"
        
        print_message "$YELLOW" "Waiting for stack $TENANT_STACK_NAME to be deleted..."
        while true; do
            STATUS=$(aws cloudformation describe-stacks \
                --profile "$AWS_PROFILE" \
                --stack-name "$TENANT_STACK_NAME" \
                --region "$AWS_REGION" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "DELETE_COMPLETE")
            
            if [ "$STATUS" == "DELETE_COMPLETE" ] || [ "$STATUS" == "DELETE_FAILED" ]; then
                break
            fi
            
            print_message "$YELLOW" "  Status: $STATUS"
            sleep 10
        done
        
        if [ "$STATUS" == "DELETE_COMPLETE" ]; then
            print_message "$GREEN" "Stack $TENANT_STACK_NAME deleted successfully"
        else
            print_message "$RED" "Stack deletion failed with status: $STATUS"
        fi
    else
        print_message "$YELLOW" "  Stack $TENANT_STACK_NAME not found"
    fi
else
    if aws cloudformation describe-stacks --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        aws cloudformation delete-stack --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION"
        
        print_message "$YELLOW" "Waiting for stack $TENANT_STACK_NAME to be deleted..."
        while true; do
            STATUS=$(aws cloudformation describe-stacks \
                --stack-name "$TENANT_STACK_NAME" \
                --region "$AWS_REGION" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "DELETE_COMPLETE")
            
            if [ "$STATUS" == "DELETE_COMPLETE" ] || [ "$STATUS" == "DELETE_FAILED" ]; then
                break
            fi
            
            print_message "$YELLOW" "  Status: $STATUS"
            sleep 10
        done
        
        if [ "$STATUS" == "DELETE_COMPLETE" ]; then
            print_message "$GREEN" "Stack $TENANT_STACK_NAME deleted successfully"
        else
            print_message "$RED" "Stack deletion failed with status: $STATUS"
        fi
    else
        print_message "$YELLOW" "  Stack $TENANT_STACK_NAME not found"
    fi
fi

# Step 5: Delete shared stack
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 5: Deleting shared stack"
print_message "$BLUE" "=========================================="
print_message "$YELLOW" "  Deleting stack: $SHARED_STACK_NAME"

if [[ -n "$AWS_PROFILE" ]]; then
    if aws cloudformation describe-stacks --profile "$AWS_PROFILE" --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        aws cloudformation delete-stack --profile "$AWS_PROFILE" --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION"
        
        print_message "$YELLOW" "Waiting for stack $SHARED_STACK_NAME to be deleted..."
        while true; do
            STATUS=$(aws cloudformation describe-stacks \
                --profile "$AWS_PROFILE" \
                --stack-name "$SHARED_STACK_NAME" \
                --region "$AWS_REGION" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "DELETE_COMPLETE")
            
            if [ "$STATUS" == "DELETE_COMPLETE" ] || [ "$STATUS" == "DELETE_FAILED" ]; then
                break
            fi
            
            print_message "$YELLOW" "  Status: $STATUS"
            sleep 10
        done
        
        if [ "$STATUS" == "DELETE_COMPLETE" ]; then
            print_message "$GREEN" "Stack $SHARED_STACK_NAME deleted successfully"
        else
            print_message "$RED" "Stack deletion failed with status: $STATUS"
        fi
    else
        print_message "$YELLOW" "  Stack $SHARED_STACK_NAME not found"
    fi
else
    if aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        aws cloudformation delete-stack --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION"
        
        print_message "$YELLOW" "Waiting for stack $SHARED_STACK_NAME to be deleted..."
        while true; do
            STATUS=$(aws cloudformation describe-stacks \
                --stack-name "$SHARED_STACK_NAME" \
                --region "$AWS_REGION" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "DELETE_COMPLETE")
            
            if [ "$STATUS" == "DELETE_COMPLETE" ] || [ "$STATUS" == "DELETE_FAILED" ]; then
                break
            fi
            
            print_message "$YELLOW" "  Status: $STATUS"
            sleep 10
        done
        
        if [ "$STATUS" == "DELETE_COMPLETE" ]; then
            print_message "$GREEN" "Stack $SHARED_STACK_NAME deleted successfully"
        else
            print_message "$RED" "Stack deletion failed with status: $STATUS"
        fi
    else
        print_message "$YELLOW" "  Stack $SHARED_STACK_NAME not found"
    fi
fi

# Step 6: Now safely delete S3 buckets (after CloudFront is deleted)
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 6: Safely deleting S3 buckets (CloudFront deleted)"
print_message "$BLUE" "=========================================="

# Empty and delete application buckets
for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_APP_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
        if [[ -n "$AWS_PROFILE" ]]; then
            if aws s3 ls "s3://$bucket" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
                print_message "$YELLOW" "  Emptying bucket: $bucket"
                aws s3 rm "s3://$bucket" --profile "$AWS_PROFILE" --recursive --region "$AWS_REGION" 2>/dev/null || true
                print_message "$YELLOW" "  Deleting bucket: $bucket"
                aws s3 rb "s3://$bucket" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true
                print_message "$GREEN" "  S3 bucket deleted: $bucket"
            else
                print_message "$YELLOW" "  Bucket already deleted or not found: $bucket"
            fi
        else
            if aws s3 ls "s3://$bucket" --region "$AWS_REGION" &> /dev/null; then
                print_message "$YELLOW" "  Emptying bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive --region "$AWS_REGION" 2>/dev/null || true
                print_message "$YELLOW" "  Deleting bucket: $bucket"
                aws s3 rb "s3://$bucket" --region "$AWS_REGION" 2>/dev/null || true
                print_message "$GREEN" "  S3 bucket deleted: $bucket"
            else
                print_message "$YELLOW" "  Bucket already deleted or not found: $bucket"
            fi
        fi
    fi
done

print_message "$GREEN" "S3 buckets deleted"

# Step 7: Delete DynamoDB tables
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 7: Deleting DynamoDB tables"
print_message "$BLUE" "=========================================="

if [[ -n "$AWS_PROFILE" ]]; then
    TABLES=$(aws dynamodb list-tables \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "TableNames[?contains(@, 'lab3')]" \
        --output text 2>/dev/null || echo "")
else
    TABLES=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query "TableNames[?contains(@, 'lab3')]" \
        --output text 2>/dev/null || echo "")
fi

if [ -n "$TABLES" ]; then
    for table in $TABLES; do
        print_message "$YELLOW" "  Deleting table: $table"
        if [[ -n "$AWS_PROFILE" ]]; then
            aws dynamodb delete-table --profile "$AWS_PROFILE" --table-name "$table" --region "$AWS_REGION" 2>/dev/null || true
        else
            aws dynamodb delete-table --table-name "$table" --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    print_message "$GREEN" "DynamoDB tables deleted"
else
    print_message "$YELLOW" "  No DynamoDB tables found"
fi

# Step 8: Clean up SAM bootstrap buckets from samconfig.toml files
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 8: Cleaning up SAM bootstrap buckets from samconfig.toml files"
print_message "$BLUE" "=========================================="

# Clean up shared stack SAM bucket
SHARED_SAM_BUCKET=$(grep s3_bucket ../server/shared-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$SHARED_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found shared SAM bucket in shared-samconfig.toml: $SHARED_SAM_BUCKET"
    if [[ -n "$AWS_PROFILE" ]]; then
        if aws s3 ls "s3://$SHARED_SAM_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
            print_message "$YELLOW" "  Emptying bucket: $SHARED_SAM_BUCKET"
            aws s3 rm "s3://$SHARED_SAM_BUCKET" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true
            print_message "$YELLOW" "  Deleting bucket: $SHARED_SAM_BUCKET"
            aws s3api delete-bucket --bucket $SHARED_SAM_BUCKET --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  Shared SAM bootstrap bucket deleted"
        else
            print_message "$YELLOW" "  Shared SAM bucket not found or already deleted"
        fi
    else
        if aws s3 ls "s3://$SHARED_SAM_BUCKET" --region "$AWS_REGION" &> /dev/null; then
            print_message "$YELLOW" "  Emptying bucket: $SHARED_SAM_BUCKET"
            aws s3 rm "s3://$SHARED_SAM_BUCKET" --recursive --region "$AWS_REGION" 2>/dev/null || true
            print_message "$YELLOW" "  Deleting bucket: $SHARED_SAM_BUCKET"
            aws s3api delete-bucket --bucket $SHARED_SAM_BUCKET --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  Shared SAM bootstrap bucket deleted"
        else
            print_message "$YELLOW" "  Shared SAM bucket not found or already deleted"
        fi
    fi
else
    print_message "$YELLOW" "  No shared SAM bucket found in shared-samconfig.toml"
fi

# Clean up tenant stack SAM bucket
TENANT_SAM_BUCKET=$(grep s3_bucket ../server/tenant-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$TENANT_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found tenant SAM bucket in tenant-samconfig.toml: $TENANT_SAM_BUCKET"
    if [[ -n "$AWS_PROFILE" ]]; then
        if aws s3 ls "s3://$TENANT_SAM_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
            print_message "$YELLOW" "  Emptying bucket: $TENANT_SAM_BUCKET"
            aws s3 rm "s3://$TENANT_SAM_BUCKET" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true
            print_message "$YELLOW" "  Deleting bucket: $TENANT_SAM_BUCKET"
            aws s3api delete-bucket --bucket $TENANT_SAM_BUCKET --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  Tenant SAM bootstrap bucket deleted"
        else
            print_message "$YELLOW" "  Tenant SAM bucket not found or already deleted"
        fi
    else
        if aws s3 ls "s3://$TENANT_SAM_BUCKET" --region "$AWS_REGION" &> /dev/null; then
            print_message "$YELLOW" "  Emptying bucket: $TENANT_SAM_BUCKET"
            aws s3 rm "s3://$TENANT_SAM_BUCKET" --recursive --region "$AWS_REGION" 2>/dev/null || true
            print_message "$YELLOW" "  Deleting bucket: $TENANT_SAM_BUCKET"
            aws s3api delete-bucket --bucket $TENANT_SAM_BUCKET --region "$AWS_REGION" 2>/dev/null || true
            print_message "$GREEN" "  Tenant SAM bootstrap bucket deleted"
        else
            print_message "$YELLOW" "  Tenant SAM bucket not found or already deleted"
        fi
    fi
else
    print_message "$YELLOW" "  No tenant SAM bucket found in tenant-samconfig.toml"
fi

print_message "$GREEN" "SAM bootstrap bucket cleanup complete"

# Step 9: Verify cleanup
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 9: Verifying cleanup"
print_message "$BLUE" "=========================================="

REMAINING_RESOURCES=0

# Check for remaining stacks
for stack in "$SHARED_STACK_NAME" "$TENANT_STACK_NAME"; do
    if [[ -n "$AWS_PROFILE" ]]; then
        if aws cloudformation describe-stacks --profile "$AWS_PROFILE" --stack-name "$stack" --region "$AWS_REGION" &>/dev/null; then
            print_message "$RED" "  Warning: Stack $stack still exists"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    else
        if aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" &>/dev/null; then
            print_message "$RED" "  Warning: Stack $stack still exists"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    fi
done

if [ $REMAINING_RESOURCES -eq 0 ]; then
    print_message "$GREEN" "All Lab3 resources have been cleaned up successfully!"
else
    print_message "$YELLOW" "Some resources may still exist. Please check manually."
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab3 Cleanup Complete!"
print_message "$GREEN" "Duration: ${DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
