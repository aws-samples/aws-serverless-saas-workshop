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
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified
STACK_NAME_PREFIX="serverless-saas-lab4"  # Default prefix for stack names
SHARED_STACK_NAME=""  # Will be set based on stack name prefix
TENANT_STACK_NAME=""  # Will be set based on stack name prefix
SKIP_CONFIRMATION=0

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
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

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       Stack name prefix (default: serverless-saas-lab4)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS profile to use (optional, uses machine's default if not specified)"
    echo "  -y, --yes                 Skip confirmation prompt"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Clean up with default settings"
    echo "  $0 --stack-name serverless-saas-lab4            # Clean up specific lab"
    echo "  $0 --region us-east-1                           # Clean up in specific region"
    echo "  $0 --profile my-profile                         # Clean up with specific AWS profile"
    echo "  $0 --stack-name my-lab --profile my-profile -y  # Clean up with custom stack name and profile, skip confirmation"
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
            print_message "$RED" "Unknown parameter: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

# Set stack names based on prefix
SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME_PREFIX##*-}"
TENANT_STACK_NAME="serverless-saas-tenant-${STACK_NAME_PREFIX##*-}"

# If the prefix already contains "serverless-saas-shared" or "serverless-saas-tenant", use it as-is
if [[ "$STACK_NAME_PREFIX" == serverless-saas-shared-* ]]; then
    SHARED_STACK_NAME="$STACK_NAME_PREFIX"
    TENANT_STACK_NAME="serverless-saas-tenant-${STACK_NAME_PREFIX##*-}"
elif [[ "$STACK_NAME_PREFIX" == serverless-saas-tenant-* ]]; then
    TENANT_STACK_NAME="$STACK_NAME_PREFIX"
    SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME_PREFIX##*-}"
fi

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$YELLOW" "=========================================="
print_message "$YELLOW" "Lab4 Cleanup Script"
print_message "$YELLOW" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using machine's default profile)"
fi
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Tenant Stack: $TENANT_STACK_NAME"
echo ""

print_message "$YELLOW" "Starting cleanup of Lab4 resources..."
echo ""

# Confirmation prompt (unless -y/--yes flag is used)
if [[ $SKIP_CONFIRMATION -eq 0 ]]; then
    print_message "$YELLOW" "⚠️  WARNING: This will delete all Lab4 resources including:"
    echo "  - CloudFormation stacks: $SHARED_STACK_NAME, $TENANT_STACK_NAME"
    echo "  - S3 buckets and their contents"
    echo "  - DynamoDB tables"
    echo "  - CloudWatch log groups"
    echo "  - SAM deployment buckets"
    echo "  - IAM roles and policies"
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

# Step 1: Identify resources from stacks (before deletion)
print_message "$YELLOW" "Step 1: Identifying resources from stacks..."

# Get bucket names from shared stack outputs
PROFILE_ARG=$(get_profile_arg)
ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Get API Gateway IDs for log deletion
SHARED_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

TENANT_API_ID=$(aws cloudformation describe-stacks \
    $PROFILE_ARG \
    --stack-name "$TENANT_STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='TenantApiGatewayId'].OutputValue" \
    --output text 2>/dev/null || echo "")

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

# Step 2: Delete CloudWatch Log Groups (BEFORE stack deletion)
print_message "$YELLOW" "Step 2: Deleting CloudWatch Log Groups..."

# Delete API Gateway execution logs first
print_message "$YELLOW" "  Deleting API Gateway execution logs..."

# Delete logs for known API Gateway IDs
for api_id in "$SHARED_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        print_message "$YELLOW" "    Deleting log group: $LOG_GROUP_NAME"
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    fi
done

# Check for orphaned API Gateway logs (logs where API Gateway no longer exists)
print_message "$YELLOW" "  Checking for orphaned API Gateway logs..."
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
            print_message "$YELLOW" "    Deleting orphaned log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        fi
    done
fi

print_message "$GREEN" "  API Gateway execution logs deleted"

# Delete Lambda function log groups
# Pattern 1: Shared stack logs (with CloudFormation resource IDs)
# Example: /aws/lambda/serverless-saas-shared-lab4-LambdaFunctions-1H2IGFR4ATAVZ-UpdateUserFunction
SHARED_LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'serverless-saas-shared-lab4')].logGroupName" \
    --output text 2>/dev/null || echo "")

# Pattern 2: Tenant stack logs (with CloudFormation resource IDs)
# Example: /aws/lambda/serverless-saas-tenant-lab4-BusinessServicesAuthorizerFunction
TENANT_LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "logGroups[?contains(logGroupName, 'serverless-saas-tenant-lab4')].logGroupName" \
    --output text 2>/dev/null || echo "")

# Combine both patterns
ALL_LOG_GROUPS="$SHARED_LOG_GROUPS $TENANT_LOG_GROUPS"

if [ -n "$ALL_LOG_GROUPS" ]; then
    for log_group in $ALL_LOG_GROUPS; do
        if [ -n "$log_group" ]; then
            print_message "$YELLOW" "  Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        fi
    done
    print_message "$GREEN" "CloudWatch Log Groups deleted"
else
    print_message "$YELLOW" "  No CloudWatch Log Groups found"
fi

# Step 3: Delete tenant stack first (dependencies)
print_message "$YELLOW" "Step 3: Deleting tenant stack..."
print_message "$YELLOW" "  Deleting stack: $TENANT_STACK_NAME"

if aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    aws cloudformation delete-stack $PROFILE_ARG --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION"
    
    print_message "$YELLOW" "Waiting for stack $TENANT_STACK_NAME to be deleted..."
    while true; do
        STATUS=$(aws cloudformation describe-stacks \
            $PROFILE_ARG \
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

# Step 4: Delete shared stack
print_message "$YELLOW" "Step 4: Deleting shared stack..."
print_message "$YELLOW" "  Deleting stack: $SHARED_STACK_NAME"

if aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG
    
    print_message "$YELLOW" "Waiting for stack $SHARED_STACK_NAME to be deleted..."
    while true; do
        STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$SHARED_STACK_NAME" \
            --region "$AWS_REGION" \
            $PROFILE_ARG \
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

# Step 5: Now safely delete S3 buckets (after CloudFront is deleted)
print_message "$YELLOW" "Step 5: Safely deleting S3 buckets (CloudFront deleted)..."

# Empty and delete application buckets from stack outputs
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

# Also search for buckets by naming pattern (fallback for when stack outputs aren't available)
print_message "$YELLOW" "  Searching for Lab 4 buckets by naming pattern..."
LAB4_BUCKETS=$(aws s3api list-buckets \
    $PROFILE_ARG \
    --query "Buckets[?contains(Name, 'serverless-saas-workshop-lab4') || contains(Name, 'lab4-adminappbucket') || contains(Name, 'lab4-landingappbucket') || contains(Name, 'lab4-appbucket')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$LAB4_BUCKETS" ]; then
    for bucket in $LAB4_BUCKETS; do
        if [ -n "$bucket" ]; then
            print_message "$YELLOW" "  Found bucket by pattern: $bucket"
            if aws s3 ls "s3://$bucket" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
                print_message "$YELLOW" "  Emptying bucket: $bucket"
                aws s3 rm "s3://$bucket" $PROFILE_ARG --recursive --region "$AWS_REGION" 2>/dev/null || true
                print_message "$YELLOW" "  Deleting bucket: $bucket"
                aws s3 rb "s3://$bucket" $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
                print_message "$GREEN" "  S3 bucket deleted: $bucket"
            fi
        fi
    done
fi

print_message "$GREEN" "S3 buckets deleted"

# Step 6: Delete DynamoDB tables
print_message "$YELLOW" "Step 6: Deleting DynamoDB tables..."

TABLES=$(aws dynamodb list-tables \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "TableNames[?contains(@, 'lab4') || contains(@, 'pooled-lab4')]" \
    --output text 2>/dev/null || echo "")

if [ -n "$TABLES" ]; then
    for table in $TABLES; do
        print_message "$YELLOW" "  Deleting table: $table"
        aws dynamodb delete-table --table-name "$table" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "DynamoDB tables deleted"
else
    print_message "$YELLOW" "  No DynamoDB tables found"
fi

# Step 6.5: Clean up SAM bootstrap buckets from samconfig.toml files
print_message "$YELLOW" "Step 6.5: Cleaning up SAM bootstrap buckets from samconfig.toml files..."

PROFILE_ARG=$(get_profile_arg)

# Clean up shared stack SAM bucket
SHARED_SAM_BUCKET=$(grep s3_bucket ../server/shared-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$SHARED_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found shared SAM bucket in shared-samconfig.toml: $SHARED_SAM_BUCKET"
    if aws s3 ls "s3://$SHARED_SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $SHARED_SAM_BUCKET"
        aws s3 rm "s3://$SHARED_SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $SHARED_SAM_BUCKET"
        aws s3api delete-bucket --bucket $SHARED_SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  Shared SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  Shared SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No shared SAM bucket found in shared-samconfig.toml"
fi

# Clean up tenant stack SAM bucket
TENANT_SAM_BUCKET=$(grep s3_bucket ../server/tenant-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$TENANT_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found tenant SAM bucket in tenant-samconfig.toml: $TENANT_SAM_BUCKET"
    if aws s3 ls "s3://$TENANT_SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $TENANT_SAM_BUCKET"
        aws s3 rm "s3://$TENANT_SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $TENANT_SAM_BUCKET"
        aws s3api delete-bucket --bucket $TENANT_SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  Tenant SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  Tenant SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No tenant SAM bucket found in tenant-samconfig.toml"
fi

print_message "$GREEN" "SAM bootstrap bucket cleanup complete"

# Step 7: Delete IAM roles and policies
print_message "$YELLOW" "Step 7: Cleaning up IAM roles and policies..."

# List IAM roles with lab4 in the name
IAM_ROLES=$(aws iam list-roles \
    $PROFILE_ARG \
    --query "Roles[?contains(RoleName, 'lab4')].RoleName" \
    --output text 2>/dev/null || echo "")

if [ -n "$IAM_ROLES" ]; then
    for role in $IAM_ROLES; do
        print_message "$YELLOW" "  Processing IAM role: $role"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role" \
            $PROFILE_ARG \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            print_message "$YELLOW" "    Detaching policy: $policy_arn"
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" $PROFILE_ARG 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role" \
            $PROFILE_ARG \
            --query "PolicyNames[]" \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            print_message "$YELLOW" "    Deleting inline policy: $policy_name"
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" $PROFILE_ARG 2>/dev/null || true
        done
        
        # Delete the role
        print_message "$YELLOW" "    Deleting role: $role"
        aws iam delete-role --role-name "$role" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "IAM roles cleaned up"
else
    print_message "$YELLOW" "  No IAM roles found"
fi

# Step 8: Verify cleanup
print_message "$YELLOW" "Step 8: Verifying cleanup..."

REMAINING_RESOURCES=0

# Check for remaining stacks
for stack in "$SHARED_STACK_NAME" "$TENANT_STACK_NAME"; do
    if aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" $PROFILE_ARG &>/dev/null; then
        print_message "$RED" "  Warning: Stack $stack still exists"
        REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
    fi
done

if [ $REMAINING_RESOURCES -eq 0 ]; then
    print_message "$GREEN" "All Lab4 resources have been cleaned up successfully!"
else
    print_message "$YELLOW" "Some resources may still exist. Please check manually."
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab4 Cleanup Complete!"
print_message "$GREEN" "Duration: ${DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
