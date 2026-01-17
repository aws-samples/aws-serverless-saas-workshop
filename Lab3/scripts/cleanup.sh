#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log file
LOG_FILE="cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Lab3 Cleanup Script"
echo "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

SHARED_STACK_NAME="serverless-saas-workshop-shared-lab3"
TENANT_STACK_NAME="serverless-saas-workshop-tenant-lab3"

print_message "$YELLOW" "Starting cleanup of Lab3 resources..."
echo ""

# Record start time
START_TIME=$(date +%s)

# Step 1: Get S3 buckets from stack outputs
print_message "$YELLOW" "Step 1: Cleaning up S3 buckets..."

# Get bucket names from shared stack outputs
ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$SHARED_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$SHARED_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$SHARED_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Empty buckets
for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_APP_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
        print_message "$YELLOW" "  Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    fi
done

print_message "$GREEN" "S3 buckets emptied"

# Step 2: Delete tenant stack first (dependencies)
print_message "$YELLOW" "Step 2: Deleting tenant stack..."
print_message "$YELLOW" "  Deleting stack: $TENANT_STACK_NAME"

if aws cloudformation describe-stacks --stack-name "$TENANT_STACK_NAME" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$TENANT_STACK_NAME"
    
    print_message "$YELLOW" "Waiting for stack $TENANT_STACK_NAME to be deleted..."
    while true; do
        STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$TENANT_STACK_NAME" \
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

# Step 3: Delete shared stack
print_message "$YELLOW" "Step 3: Deleting shared stack..."
print_message "$YELLOW" "  Deleting stack: $SHARED_STACK_NAME"

if aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$SHARED_STACK_NAME"
    
    print_message "$YELLOW" "Waiting for stack $SHARED_STACK_NAME to be deleted..."
    while true; do
        STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$SHARED_STACK_NAME" \
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

# Step 4: Delete CloudWatch Log Groups
print_message "$YELLOW" "Step 4: Deleting CloudWatch Log Groups..."

LOG_GROUPS=$(aws logs describe-log-groups \
    --query "logGroups[?contains(logGroupName, 'lab3')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        print_message "$YELLOW" "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
    done
    print_message "$GREEN" "CloudWatch Log Groups deleted"
else
    print_message "$YELLOW" "  No CloudWatch Log Groups found"
fi

# Step 5: Delete DynamoDB tables
print_message "$YELLOW" "Step 5: Deleting DynamoDB tables..."

TABLES=$(aws dynamodb list-tables \
    --query "TableNames[?contains(@, 'lab3')]" \
    --output text 2>/dev/null || echo "")

if [ -n "$TABLES" ]; then
    for table in $TABLES; do
        print_message "$YELLOW" "  Deleting table: $table"
        aws dynamodb delete-table --table-name "$table" 2>/dev/null || true
    done
    print_message "$GREEN" "DynamoDB tables deleted"
else
    print_message "$YELLOW" "  No DynamoDB tables found"
fi

# Step 6: Verify cleanup
print_message "$YELLOW" "Step 6: Verifying cleanup..."

REMAINING_RESOURCES=0

# Check for remaining stacks
for stack in "$SHARED_STACK_NAME" "$TENANT_STACK_NAME"; do
    if aws cloudformation describe-stacks --stack-name "$stack" &>/dev/null; then
        print_message "$RED" "  Warning: Stack $stack still exists"
        REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
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
