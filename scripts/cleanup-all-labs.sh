#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$(dirname "$SCRIPT_DIR")"

# Create log file
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-all-labs-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "AWS Serverless SaaS Workshop"
echo "Cleanup All Labs Script"
echo "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to cleanup a lab
cleanup_lab() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    print_message "$YELLOW" "========================================="
    print_message "$YELLOW" "Cleaning up Lab${lab_num}..."
    print_message "$YELLOW" "========================================="
    
    if [ ! -d "$lab_dir" ]; then
        print_message "$RED" "Lab${lab_num} directory not found, skipping..."
        return 0
    fi
    
    # Check if cleanup script exists
    if [ -f "$lab_dir/scripts/cleanup.sh" ]; then
        print_message "$GREEN" "Running Lab${lab_num} cleanup script..."
        cd "$lab_dir/scripts"
        ./cleanup.sh
        cd "$WORKSHOP_ROOT"
        print_message "$GREEN" "Lab${lab_num} cleanup completed!"
    else
        print_message "$YELLOW" "No cleanup script found for Lab${lab_num}, performing manual cleanup..."
        cleanup_lab_manual "$lab_num"
    fi
    
    echo ""
}

# Function to manually cleanup labs without cleanup scripts
cleanup_lab_manual() {
    local lab_num=$1
    
    print_message "$YELLOW" "Performing manual cleanup for Lab${lab_num}..."
    
    # Delete CloudFormation stacks
    print_message "$YELLOW" "Deleting CloudFormation stacks for Lab${lab_num}..."
    
    # Get all stacks with lab suffix
    local stacks=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, 'lab${lab_num}')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$stacks" ]; then
        for stack in $stacks; do
            print_message "$YELLOW" "  Deleting stack: $stack"
            aws cloudformation delete-stack --stack-name "$stack" 2>/dev/null || true
        done
        
        # Wait for stacks to delete
        for stack in $stacks; do
            print_message "$YELLOW" "  Waiting for $stack to be deleted..."
            aws cloudformation wait stack-delete-complete --stack-name "$stack" 2>/dev/null || true
        done
        print_message "$GREEN" "CloudFormation stacks deleted"
    else
        print_message "$YELLOW" "No CloudFormation stacks found for Lab${lab_num}"
    fi
    
    # Delete S3 buckets
    print_message "$YELLOW" "Deleting S3 buckets for Lab${lab_num}..."
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'lab${lab_num}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            print_message "$YELLOW" "  Emptying and deleting bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        done
        print_message "$GREEN" "S3 buckets deleted"
    else
        print_message "$YELLOW" "No S3 buckets found for Lab${lab_num}"
    fi
    
    # Delete CloudWatch Log Groups
    print_message "$YELLOW" "Deleting CloudWatch Log Groups for Lab${lab_num}..."
    local log_groups=$(aws logs describe-log-groups \
        --query "logGroups[?contains(logGroupName, 'lab${lab_num}')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$log_groups" ]; then
        for log_group in $log_groups; do
            print_message "$YELLOW" "  Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
        done
        print_message "$GREEN" "CloudWatch Log Groups deleted"
    else
        print_message "$YELLOW" "No CloudWatch Log Groups found for Lab${lab_num}"
    fi
    
    print_message "$GREEN" "Manual cleanup for Lab${lab_num} completed"
}

# Parse command line arguments
LABS_TO_CLEANUP=()
CLEANUP_ALL=false

if [ $# -eq 0 ]; then
    CLEANUP_ALL=true
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                CLEANUP_ALL=true
                shift
                ;;
            --lab)
                LABS_TO_CLEANUP+=("$2")
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --all           Cleanup all labs (default if no options provided)"
                echo "  --lab <number>  Cleanup specific lab (can be used multiple times)"
                echo "  --help          Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                    # Cleanup all labs"
                echo "  $0 --all              # Cleanup all labs"
                echo "  $0 --lab 5            # Cleanup only Lab5"
                echo "  $0 --lab 5 --lab 6   # Cleanup Lab5 and Lab6"
                exit 0
                ;;
            *)
                print_message "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
fi

# Determine which labs to cleanup
if [ "$CLEANUP_ALL" = true ]; then
    LABS_TO_CLEANUP=(7 6 5 4 3 2 1)  # Reverse order to cleanup dependencies first
    print_message "$GREEN" "Cleaning up all labs in reverse order..."
else
    # Sort labs in reverse order
    IFS=$'\n' LABS_TO_CLEANUP=($(sort -rn <<<"${LABS_TO_CLEANUP[*]}"))
    unset IFS
    print_message "$GREEN" "Cleaning up selected labs: ${LABS_TO_CLEANUP[*]}"
fi

echo ""

# Record start time
START_TIME=$(date +%s)

# Cleanup each lab
for lab in "${LABS_TO_CLEANUP[@]}"; do
    cleanup_lab "$lab"
done

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

print_message "$GREEN" "========================================"
print_message "$GREEN" "All Lab Cleanup Complete!"
print_message "$GREEN" "Duration: ${DURATION} seconds"
print_message "$GREEN" "Log file: $LOG_FILE"
print_message "$GREEN" "========================================"
