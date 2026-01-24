#!/bin/bash -e

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# AWS Profile should be passed via --profile parameter

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE=""  # Optional, will use default profile if not provided
MAIN_STACK="serverless-saas-lab7"
TENANT_STACK="stack-pooled-lab7"

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
    echo "  --profile <profile>            AWS CLI profile name (optional, uses default if not provided)"
    echo "  --region <region>              AWS region (default: us-west-2)"
    echo "  --main-stack <name>            Main stack name (default: serverless-saas-lab7)"
    echo "  --tenant-stack <name>          Tenant stack name (default: stack-pooled-lab7)"
    echo "  --help                         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Use default values"
    echo "  $0 --profile serverless-saas-demo              # Use specific AWS profile"
    echo "  $0 --region us-east-1                           # Use custom region"
    echo "  $0 --main-stack my-lab7-stack                   # Use custom main stack name"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --main-stack)
            MAIN_STACK=$2
            shift 2
            ;;
        --tenant-stack)
            TENANT_STACK=$2
            shift 2
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

# Build AWS CLI profile argument if profile is provided
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Logging setup
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-${TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "========================================"
print_message "$BLUE" "Lab7 Cleanup Script"
print_message "$BLUE" "========================================"
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
fi
echo "AWS Region: $AWS_REGION"
echo "Main Stack: $MAIN_STACK"
echo "Tenant Stack: $TENANT_STACK"
echo ""

# Confirmation prompt
print_message "$YELLOW" "WARNING: This will delete all Lab7 resources in region $AWS_REGION"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    print_message "$YELLOW" "Cleanup cancelled"
    exit 0
fi
echo ""

START_TIME=$(date +%s)

# Stack names (using variables now)
print_message "$YELLOW" "Starting cleanup of Lab7 resources..."
echo ""

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" $PROFILE_ARG >/dev/null 2>&1
}

# Function to wait for stack deletion
wait_for_stack_deletion() {
    local stack_name=$1
    echo "Waiting for stack $stack_name to be deleted..."
    
    while stack_exists "$stack_name"; do
        local status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" $PROFILE_ARG --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [ "$status" == "DELETE_FAILED" ]; then
            print_message "$RED" "Stack deletion failed. Please check AWS Console for details."
            return 1
        fi
        
        echo "  Status: $status"
        sleep 10
    done
    
    print_message "$GREEN" "Stack $stack_name deleted successfully"
}

# Step 1: Identify resources from stacks (before deletion)
print_message "$YELLOW" "Step 1: Identifying resources from stacks..."

# Get API Gateway IDs from stack outputs (before deletion)
MAIN_API_ID=$(aws cloudformation describe-stacks --stack-name "$MAIN_STACK" --region "$AWS_REGION" $PROFILE_ARG \
  --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayId'].OutputValue" --output text 2>/dev/null || echo "")
TENANT_API_ID=$(aws cloudformation describe-stacks --stack-name "$TENANT_STACK" --region "$AWS_REGION" $PROFILE_ARG \
  --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayId'].OutputValue" --output text 2>/dev/null || echo "")

echo "Found resources:"
[[ ! -z "$MAIN_API_ID" && "$MAIN_API_ID" != "None" ]] && echo "  - Main API Gateway ID: $MAIN_API_ID"
[[ ! -z "$TENANT_API_ID" && "$TENANT_API_ID" != "None" ]] && echo "  - Tenant API Gateway ID: $TENANT_API_ID"
echo ""

# Step 2: Delete CloudWatch Log Groups (BEFORE stack deletion)
print_message "$YELLOW" "Step 2: Deleting CloudWatch Log Groups..."

# Delete API Gateway execution logs first
echo "Deleting API Gateway execution logs..."

# Delete logs for known API Gateway IDs
for api_id in "$MAIN_API_ID" "$TENANT_API_ID"; do
    if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
        LOG_GROUP_NAME="API-Gateway-Execution-Logs_${api_id}/prod"
        echo "  Deleting log group: $LOG_GROUP_NAME"
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    fi
done

# Check for orphaned API Gateway logs (logs where API Gateway no longer exists)
echo "Checking for orphaned API Gateway logs..."
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
            echo "  Deleting orphaned log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        fi
    done
fi

echo "✓ API Gateway execution logs deleted"

# Delete Lambda function log groups
LOG_GROUPS=$(aws logs describe-log-groups --region "$AWS_REGION" $PROFILE_ARG --query "logGroups[?contains(logGroupName, 'lab7')].logGroupName" --output text)

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        echo "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "Lambda log groups deleted"
else
    echo "  No Lab7 Lambda log groups found"
fi

print_message "$GREEN" "CloudWatch Log Groups cleanup complete"
echo ""

# Step 3: Clean up S3 buckets
print_message "$YELLOW" "Step 3: Cleaning up S3 buckets..."
BUCKETS=$(aws s3api list-buckets $PROFILE_ARG --query "Buckets[?contains(Name, 'serverless-saas-lab7')].Name" --output text)

if [ -n "$BUCKETS" ]; then
    for bucket in $BUCKETS; do
        echo "  Emptying bucket: $bucket"
        aws s3 rm s3://$bucket --recursive --quiet --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        echo "  Deleting bucket: $bucket"
        aws s3api delete-bucket --bucket $bucket --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "S3 buckets cleaned up"
else
    echo "  No Lab7 S3 buckets found"
fi
echo ""

# Step 4: Delete tenant stack (if exists)
print_message "$YELLOW" "Step 4: Deleting tenant stack..."

if stack_exists "$TENANT_STACK"; then
    echo "  Deleting stack: $TENANT_STACK"
    aws cloudformation delete-stack --stack-name "$TENANT_STACK" --region "$AWS_REGION" $PROFILE_ARG
    wait_for_stack_deletion "$TENANT_STACK"
else
    echo "  Stack $TENANT_STACK not found"
fi
echo ""

# Step 5: Delete main CloudFormation stack
print_message "$YELLOW" "Step 5: Deleting main CloudFormation stack..."
if stack_exists "$MAIN_STACK"; then
    echo "  Deleting stack: $MAIN_STACK"
    aws cloudformation delete-stack --stack-name "$MAIN_STACK" --region "$AWS_REGION" $PROFILE_ARG
    wait_for_stack_deletion "$MAIN_STACK"
else
    echo "  Stack $MAIN_STACK not found"
fi
echo ""

# Step 6: Delete DynamoDB tables
print_message "$YELLOW" "Step 6: Deleting DynamoDB tables..."

# Attribution table
TABLE_NAME="TenantCostAndUsageAttribution-lab7"
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" $PROFILE_ARG >/dev/null 2>&1; then
    echo "  Deleting table: $TABLE_NAME"
    aws dynamodb delete-table --table-name "$TABLE_NAME" --region "$AWS_REGION" $PROFILE_ARG >/dev/null 2>&1 || true
else
    echo "  Table $TABLE_NAME not found"
fi

# Tenant product table (if not deleted by stack)
PRODUCT_TABLE="Product-pooled-lab7"
if aws dynamodb describe-table --table-name "$PRODUCT_TABLE" --region "$AWS_REGION" $PROFILE_ARG >/dev/null 2>&1; then
    echo "  Deleting table: $PRODUCT_TABLE"
    aws dynamodb delete-table --table-name "$PRODUCT_TABLE" --region "$AWS_REGION" $PROFILE_ARG >/dev/null 2>&1 || true
else
    echo "  Table $PRODUCT_TABLE not found"
fi

print_message "$GREEN" "DynamoDB tables cleaned up"
echo ""

# Step 7: Delete Lambda functions with lab7 prefix
print_message "$YELLOW" "Step 7: Deleting Lambda functions..."
FUNCTIONS=$(aws lambda list-functions --region "$AWS_REGION" $PROFILE_ARG --query "Functions[?contains(FunctionName, 'lab7')].FunctionName" --output text)

if [ -n "$FUNCTIONS" ]; then
    for func in $FUNCTIONS; do
        echo "  Deleting function: $func"
        aws lambda delete-function --function-name "$func" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "Lambda functions deleted"
else
    echo "  No Lab7 Lambda functions found"
fi
echo ""

# Step 8: Delete EventBridge Rules
print_message "$YELLOW" "Step 8: Deleting EventBridge Rules..."
RULES=$(aws events list-rules --region "$AWS_REGION" $PROFILE_ARG --query "Rules[?contains(Name, 'lab7')].Name" --output text)

if [ -n "$RULES" ]; then
    for rule in $RULES; do
        echo "  Removing targets from rule: $rule"
        TARGETS=$(aws events list-targets-by-rule --rule "$rule" --region "$AWS_REGION" $PROFILE_ARG --query "Targets[].Id" --output text)
        if [ -n "$TARGETS" ]; then
            aws events remove-targets --rule "$rule" --ids $TARGETS --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
        fi
        echo "  Deleting rule: $rule"
        aws events delete-rule --name "$rule" --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "EventBridge Rules deleted"
else
    echo "  No Lab7 EventBridge Rules found"
fi
echo ""

# Step 9: Clean up SAM bootstrap bucket from samconfig.toml
print_message "$YELLOW" "Step 9: Cleaning up SAM bootstrap bucket from samconfig.toml..."

# Get the bucket name from samconfig.toml
SAM_BUCKET=$(grep s3_bucket ../samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

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

# Step 10: Delete IAM Roles
print_message "$YELLOW" "Step 10: Deleting IAM Roles..."
ROLES=$(aws iam list-roles $PROFILE_ARG --query "Roles[?contains(RoleName, 'lab7')].RoleName" --output text)

if [ -n "$ROLES" ]; then
    for role in $ROLES; do
        echo "  Detaching policies from role: $role"
        
        # Detach managed policies
        MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" $PROFILE_ARG --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || true)
        for policy in $MANAGED_POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" $PROFILE_ARG 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" $PROFILE_ARG --query "PolicyNames[]" --output text 2>/dev/null || true)
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" $PROFILE_ARG 2>/dev/null || true
        done
        
        echo "  Deleting role: $role"
        aws iam delete-role --role-name "$role" $PROFILE_ARG 2>/dev/null || true
    done
    print_message "$GREEN" "IAM Roles deleted"
else
    echo "  No Lab7 IAM Roles found"
fi
echo ""

# Step 11: Verify cleanup
print_message "$YELLOW" "Step 11: Verifying cleanup..."
REMAINING_STACKS=$(aws cloudformation list-stacks --region "$AWS_REGION" $PROFILE_ARG --query "StackSummaries[?contains(StackName, 'lab7') && StackStatus!='DELETE_COMPLETE'].StackName" --output text)
REMAINING_FUNCTIONS=$(aws lambda list-functions --region "$AWS_REGION" $PROFILE_ARG --query "Functions[?contains(FunctionName, 'lab7')].FunctionName" --output text)
REMAINING_BUCKETS=$(aws s3api list-buckets $PROFILE_ARG --query "Buckets[?contains(Name, 'serverless-saas-lab7')].Name" --output text)

if [ -z "$REMAINING_STACKS" ] && [ -z "$REMAINING_FUNCTIONS" ] && [ -z "$REMAINING_BUCKETS" ]; then
    print_message "$GREEN" "All Lab7 resources have been cleaned up successfully!"
else
    print_message "$YELLOW" "Some resources may still exist:"
    [ -n "$REMAINING_STACKS" ] && echo "  Stacks: $REMAINING_STACKS"
    [ -n "$REMAINING_FUNCTIONS" ] && echo "  Functions: $REMAINING_FUNCTIONS"
    [ -n "$REMAINING_BUCKETS" ] && echo "  Buckets: $REMAINING_BUCKETS"
fi
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

print_message "$GREEN" "========================================"
print_message "$GREEN" "Lab7 Cleanup Complete!"
print_message "$GREEN" "========================================"
echo "Duration: ${DURATION} seconds"
echo "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
