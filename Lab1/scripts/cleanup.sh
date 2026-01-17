#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

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

# Parse command line arguments
STACK_NAME=""

if [ $# -eq 0 ]; then
    print_message "$RED" "Error: Stack name is required"
    echo ""
    echo "Usage: $0 --stack-name <CloudFormation stack name>"
    echo ""
    echo "Example:"
    echo "  $0 --stack-name serverless-saas-workshop-lab1"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME=$2
            shift 2
            ;;
        --help)
            echo "Usage: $0 --stack-name <CloudFormation stack name>"
            echo ""
            echo "Options:"
            echo "  --stack-name <name>  CloudFormation stack name to cleanup"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            print_message "$RED" "Unknown parameter: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ -z "$STACK_NAME" ]; then
    print_message "$RED" "Error: Stack name is required"
    exit 1
fi

print_message "$YELLOW" "Starting cleanup of Lab1 resources..."
print_message "$YELLOW" "Stack name: $STACK_NAME"
echo ""

# Record start time
START_TIME=$(date +%s)

# Step 1: Get S3 buckets from stack outputs
print_message "$YELLOW" "Step 1: Cleaning up S3 buckets..."

APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$APP_SITE_BUCKET" ] && [ "$APP_SITE_BUCKET" != "None" ]; then
    print_message "$YELLOW" "  Emptying bucket: $APP_SITE_BUCKET"
    aws s3 rm "s3://$APP_SITE_BUCKET" --recursive 2>/dev/null || true
    print_message "$GREEN" "S3 bucket emptied"
else
    print_message "$YELLOW" "  No S3 bucket found in stack outputs"
fi

# Step 2: Delete CloudFormation stack
print_message "$YELLOW" "Step 2: Deleting CloudFormation stack..."
print_message "$YELLOW" "  Deleting stack: $STACK_NAME"

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    print_message "$YELLOW" "Waiting for stack $STACK_NAME to be deleted..."
    while true; do
        STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query "Stacks[0].StackStatus" \
            --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [ "$STATUS" == "DELETE_COMPLETE" ] || [ "$STATUS" == "DELETE_FAILED" ]; then
            break
        fi
        
        print_message "$YELLOW" "  Status: $STATUS"
        sleep 10
    done
    
    if [ "$STATUS" == "DELETE_COMPLETE" ]; then
        print_message "$GREEN" "Stack $STACK_NAME deleted successfully"
    else
        print_message "$RED" "Stack deletion failed with status: $STATUS"
    fi
else
    print_message "$YELLOW" "  Stack $STACK_NAME not found"
fi

# Step 3: Delete CloudWatch Log Groups
print_message "$YELLOW" "Step 3: Deleting CloudWatch Log Groups..."

LOG_GROUPS=$(aws logs describe-log-groups \
    --query "logGroups[?contains(logGroupName, 'lab1')].logGroupName" \
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

# Step 4: Verify cleanup
print_message "$YELLOW" "Step 4: Verifying cleanup..."

REMAINING_RESOURCES=0

# Check for remaining stacks
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_message "$RED" "  Warning: Stack $STACK_NAME still exists"
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
