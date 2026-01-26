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

# Function to check if a lab exists (has deployed resources)
check_lab_exists() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    # Check if lab directory exists
    if [ ! -d "$lab_dir" ]; then
        return 1
    fi
    
    # Check if lab has any CloudFormation stacks
    local stacks=""
    case $lab_num in
        1)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "${LAB1_STACK_NAME:-serverless-saas-lab1}" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        2)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-lab2" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        3)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab3" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        4)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab4" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        5)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab5" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        6)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab6" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        7)
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-lab7" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
    esac
    
    if [ -n "$stacks" ] && [ "$stacks" != "None" ]; then
        return 0  # Lab exists
    else
        return 1  # Lab doesn't exist
    fi
}

# Function to verify all resources are deleted
verify_complete_cleanup() {
    print_message "$YELLOW" "========================================"
    print_message "$YELLOW" "Final Verification - Checking for Remaining Resources"
    print_message "$YELLOW" "========================================"
    
    local remaining_resources=0
    
    # Check for remaining CloudFormation stacks
    print_message "$YELLOW" "Checking for remaining CloudFormation stacks..."
    local remaining_stacks=$(aws cloudformation list-stacks \
        ${PROFILE:+--profile "$PROFILE"} \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, 'serverless-saas-lab') || contains(StackName, 'stack-')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_stacks" ]; then
        print_message "$RED" "  ⚠️  Found remaining stacks:"
        for stack in $remaining_stacks; do
            print_message "$RED" "    - $stack"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining CloudFormation stacks"
    fi
    
    # Check for remaining S3 buckets
    print_message "$YELLOW" "Checking for remaining S3 buckets..."
    local remaining_buckets=$(aws s3 ls ${PROFILE:+--profile "$PROFILE"} | grep -E "serverless-saas-lab|sam-bootstrap-bucket-lab|cdk-hnb659fds" | awk '{print $3}' || echo "")
    
    if [ -n "$remaining_buckets" ]; then
        print_message "$RED" "  ⚠️  Found remaining S3 buckets:"
        for bucket in $remaining_buckets; do
            print_message "$RED" "    - $bucket"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining S3 buckets"
    fi
    
    # Check for remaining CloudWatch Log Groups
    print_message "$YELLOW" "Checking for remaining CloudWatch Log Groups..."
    local remaining_logs=$(aws logs describe-log-groups \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --query "logGroups[?contains(logGroupName, 'serverless-saas-lab') || contains(logGroupName, 'stack-lab')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_logs" ]; then
        print_message "$RED" "  ⚠️  Found remaining CloudWatch Log Groups:"
        for log_group in $remaining_logs; do
            print_message "$RED" "    - $log_group"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining CloudWatch Log Groups"
    fi
    
    # Check for remaining IAM Roles
    print_message "$YELLOW" "Checking for remaining IAM Roles..."
    local remaining_roles=$(aws iam list-roles \
        ${PROFILE:+--profile "$PROFILE"} \
        --query "Roles[?contains(RoleName, 'serverless-saas-lab') || contains(RoleName, 'stack-lab')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_roles" ]; then
        print_message "$RED" "  ⚠️  Found remaining IAM Roles:"
        for role in $remaining_roles; do
            print_message "$RED" "    - $role"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining IAM Roles"
    fi
    
    # Check for remaining DynamoDB tables
    print_message "$YELLOW" "Checking for remaining DynamoDB tables..."
    local remaining_tables=$(aws dynamodb list-tables \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --query "TableNames[?contains(@, 'lab')]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_tables" ]; then
        print_message "$RED" "  ⚠️  Found remaining DynamoDB tables:"
        for table in $remaining_tables; do
            print_message "$RED" "    - $table"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining DynamoDB tables"
    fi
    
    # Check for remaining Cognito User Pools
    print_message "$YELLOW" "Checking for remaining Cognito User Pools..."
    local remaining_pools_west=$(aws cognito-idp list-user-pools \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --max-results 60 \
        --query "UserPools[?contains(Name, 'lab')].Name" \
        --output text 2>/dev/null || echo "")
    
    local remaining_pools_east=$(aws cognito-idp list-user-pools \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --max-results 60 \
        --query "UserPools[?contains(Name, 'lab')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_pools_west" ] || [ -n "$remaining_pools_east" ]; then
        print_message "$RED" "  ⚠️  Found remaining Cognito User Pools:"
        if [ -n "$remaining_pools_west" ]; then
            print_message "$RED" "    Region: us-east-1"
            for pool in $remaining_pools_west; do
                print_message "$RED" "      - $pool"
            done
        fi
        if [ -n "$remaining_pools_east" ]; then
            print_message "$RED" "    Region: us-east-1"
            for pool in $remaining_pools_east; do
                print_message "$RED" "      - $pool"
            done
        fi
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining Cognito User Pools"
    fi
    
    echo ""
    if [ $remaining_resources -eq 0 ]; then
        print_message "$GREEN" "✓ All workshop resources have been completely cleaned up!"
        return 0
    else
        print_message "$YELLOW" "⚠️  Some resources may still exist. Please review the list above."
        return 1
    fi
}

# Function to cleanup a lab
cleanup_lab() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    print_message "$YELLOW" "========================================="
    print_message "$YELLOW" "Cleaning up Lab${lab_num}..."
    print_message "$YELLOW" "========================================="
    
    # Interactive confirmation
    if [ "$INTERACTIVE" = true ]; then
        read -p "Cleanup Lab${lab_num}? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "$YELLOW" "Skipping Lab${lab_num} cleanup"
            return 0
        fi
    fi
    
    if [ ! -d "$lab_dir" ]; then
        print_message "$RED" "Lab${lab_num} directory not found, skipping..."
        return 0
    fi
    
    # Check if cleanup script exists
    if [ -f "$lab_dir/scripts/cleanup.sh" ]; then
        print_message "$GREEN" "Running Lab${lab_num} cleanup script..."
        cd "$lab_dir/scripts"
        
        # Run cleanup script with appropriate parameters
        local cleanup_cmd=""
        case $lab_num in
            1)
                # Lab1 requires --stack-name parameter
                cleanup_cmd="./cleanup.sh --stack-name ${LAB1_STACK_NAME:-serverless-saas-lab1} -y"
                if [ -n "$PROFILE" ]; then
                    cleanup_cmd="$cleanup_cmd --profile $PROFILE"
                fi
                print_message "$YELLOW" "Using stack name: ${LAB1_STACK_NAME:-serverless-saas-lab1}"
                ;;
            3)
                # Lab3 requires --stack-name parameter
                cleanup_cmd="./cleanup.sh --stack-name serverless-saas-lab3 -y"
                if [ -n "$PROFILE" ]; then
                    cleanup_cmd="$cleanup_cmd --profile $PROFILE"
                fi
                ;;
            4)
                # Lab4 requires --stack-name parameter
                cleanup_cmd="./cleanup.sh --stack-name serverless-saas-lab4 -y"
                if [ -n "$PROFILE" ]; then
                    cleanup_cmd="$cleanup_cmd --profile $PROFILE"
                fi
                ;;
            *)
                # All other labs support -y flag
                cleanup_cmd="./cleanup.sh -y"
                if [ -n "$PROFILE" ]; then
                    cleanup_cmd="$cleanup_cmd --profile $PROFILE"
                fi
                ;;
        esac
        
        # Run cleanup script
        if eval "$cleanup_cmd"; then
            print_message "$GREEN" "Lab${lab_num} cleanup completed!"
            cd "$WORKSHOP_ROOT"
            return 0
        else
            print_message "$RED" "Lab${lab_num} cleanup failed!"
            cd "$WORKSHOP_ROOT"
            return 1
        fi
    else
        print_message "$YELLOW" "No cleanup script found for Lab${lab_num}, performing manual cleanup..."
        cleanup_lab_manual "$lab_num"
    fi
    
    echo ""
}

# Function to cleanup labs in parallel
cleanup_labs_parallel() {
    local labs_to_clean=("$@")
    
    print_message "$YELLOW" "Starting parallel cleanup of labs: ${labs_to_clean[*]}..."
    
    # Create temporary files to capture exit codes
    local status_files=()
    local pids=()
    
    # Start cleanup for each lab in background
    for lab in "${labs_to_clean[@]}"; do
        local status_file=$(mktemp)
        status_files+=("$status_file")
        
        (
            if cleanup_lab "$lab"; then
                echo "0" > "$status_file"
            else
                echo "1" > "$status_file"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all cleanups to complete
    print_message "$YELLOW" "Waiting for parallel cleanups to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Check results and track successes/failures
    local all_success=true
    for i in "${!labs_to_clean[@]}"; do
        local lab="${labs_to_clean[$i]}"
        local status=$(cat "${status_files[$i]}")
        
        if [ "$status" -eq 0 ]; then
            SUCCESSFUL_CLEANUPS+=("$lab")
            print_message "$GREEN" "Lab${lab} parallel cleanup completed successfully!"
        else
            FAILED_CLEANUPS+=("$lab")
            print_message "$RED" "Lab${lab} parallel cleanup failed!"
            all_success=false
        fi
        
        # Cleanup temp file
        rm -f "${status_files[$i]}"
    done
    
    # Return failure if any lab failed
    if [ "$all_success" = false ]; then
        return 1
    fi
    
    return 0
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
        --output text ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || echo "")
    
    if [ -n "$stacks" ]; then
        for stack in $stacks; do
            print_message "$YELLOW" "  Deleting stack: $stack"
            aws cloudformation delete-stack --stack-name "$stack" ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        done
        
        # Wait for stacks to delete
        for stack in $stacks; do
            print_message "$YELLOW" "  Waiting for $stack to be deleted..."
            aws cloudformation wait stack-delete-complete --stack-name "$stack" ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        done
        print_message "$GREEN" "CloudFormation stacks deleted"
    else
        print_message "$YELLOW" "No CloudFormation stacks found for Lab${lab_num}"
    fi
    
    # Delete S3 buckets
    print_message "$YELLOW" "Deleting S3 buckets for Lab${lab_num}..."
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'lab${lab_num}')].Name" \
        --output text ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            print_message "$YELLOW" "  Emptying and deleting bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
            aws s3api delete-bucket --bucket "$bucket" ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        done
        print_message "$GREEN" "S3 buckets deleted"
    else
        print_message "$YELLOW" "No S3 buckets found for Lab${lab_num}"
    fi
    
    # Delete CloudWatch Log Groups
    print_message "$YELLOW" "Deleting CloudWatch Log Groups for Lab${lab_num}..."
    local log_groups=$(aws logs describe-log-groups \
        --query "logGroups[?contains(logGroupName, 'lab${lab_num}')].logGroupName" \
        --output text ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || echo "")
    
    if [ -n "$log_groups" ]; then
        for log_group in $log_groups; do
            print_message "$YELLOW" "  Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
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
LAB1_STACK_NAME="serverless-saas-lab1"
PROFILE=""
PARALLEL=false
INTERACTIVE=false
STOP_ON_ERROR=true

# Parse arguments
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
        --lab1-stack-name)
            LAB1_STACK_NAME=$2
            shift 2
            ;;
        --profile)
            PROFILE=$2
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --continue-on-error)
            STOP_ON_ERROR=false
            shift
            ;;
        --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --all                       Cleanup all labs (default if no options provided)"
                echo "  --lab <number>              Cleanup specific lab (can be used multiple times)"
                echo "  --lab1-stack-name <name>    Stack name for Lab1 (default: serverless-saas-lab1)"
                echo "  --profile <profile>         AWS profile to use (optional, uses default if not provided)"
                echo "  --parallel                  Enable parallel cleanup of independent labs (experimental)"
                echo "  -i, --interactive           Prompt for confirmation before each cleanup"
                echo "  --continue-on-error         Continue cleaning next lab even if current fails"
                echo "  --help                      Show this help message"
                echo ""
                echo "Cleanup Order:"
                echo "  Labs are cleaned in reverse order (Lab7 → Lab1) to respect dependencies"
                echo "  With --parallel: Independent labs clean concurrently while respecting dependencies"
                echo ""
                echo "Resources Cleaned:"
                echo "  - CloudFormation stacks (including nested stacks)"
                echo "  - S3 buckets (including versioned buckets)"
                echo "  - CloudWatch log groups"
                echo "  - Cognito user pools and identity pools"
                echo "  - CodeCommit repositories"
                echo "  - CodePipeline pipelines"
                echo "  - API Gateway resources"
                echo "  - Lambda functions and layers"
                echo "  - DynamoDB tables"
                echo "  - IAM roles and policies created by labs"
                echo "  - CloudFront distributions"
                echo ""
                echo "Examples:"
                echo "  $0                                      # Cleanup all labs"
                echo "  $0 --all                                # Cleanup all labs"
                echo "  $0 --all --profile serverless-saas-demo # Cleanup all labs with specific profile"
                echo "  $0 --all --parallel                     # Cleanup with parallel mode"
                echo "  $0 --all -i                             # Interactive mode with confirmations"
                echo "  $0 --lab 5                              # Cleanup only Lab5"
                echo "  $0 --lab 5 --lab 6                     # Cleanup Lab5 and Lab6"
                echo "  $0 --lab 1 --lab1-stack-name my-stack  # Cleanup Lab1 with custom stack name"
                echo "  $0 --lab 2 --profile my-profile        # Cleanup Lab2 with specific profile"
                echo "  $0 --all --continue-on-error            # Continue on failures"
                exit 0
                ;;
            *)
                print_message "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

# Determine which labs to cleanup
# If no specific labs were requested and --all wasn't explicitly set, default to all labs
if [ ${#LABS_TO_CLEANUP[@]} -eq 0 ] && [ "$CLEANUP_ALL" = false ]; then
    CLEANUP_ALL=true
fi

if [ "$CLEANUP_ALL" = true ]; then
    LABS_TO_CLEANUP=(7 6 5 4 3 2 1)  # Reverse order to cleanup dependencies first
    print_message "$GREEN" "Cleaning up all labs in reverse order..."
else
    # Sort labs in reverse order
    IFS=$'\n' LABS_TO_CLEANUP=($(sort -rn <<<"${LABS_TO_CLEANUP[*]}"))
    unset IFS
    print_message "$GREEN" "Cleaning up selected labs: ${LABS_TO_CLEANUP[*]}"
fi

# Display configuration
echo ""
print_message "$YELLOW" "Configuration:"
print_message "$YELLOW" "  Lab Stack Names:"
print_message "$YELLOW" "    Lab1: serverless-saas-lab1"
print_message "$YELLOW" "    Lab2: serverless-saas-lab2"
print_message "$YELLOW" "    Lab3: serverless-saas-shared-lab3, serverless-saas-tenant-lab3"
print_message "$YELLOW" "    Lab4: serverless-saas-shared-lab4, serverless-saas-tenant-lab4"
print_message "$YELLOW" "    Lab5: serverless-saas-shared-lab5, serverless-saas-pipeline-lab5"
print_message "$YELLOW" "    Lab6: serverless-saas-shared-lab6, serverless-saas-pipeline-lab6"
print_message "$YELLOW" "    Lab7: serverless-saas-lab7"
if [ -n "$PROFILE" ]; then
    print_message "$YELLOW" "  AWS Profile: $PROFILE"
else
    print_message "$YELLOW" "  AWS Profile: (using default)"
fi
if [ "$PARALLEL" = true ]; then
    print_message "$YELLOW" "  Parallel Mode: Enabled (independent labs will clean concurrently)"
fi
if [ "$INTERACTIVE" = true ]; then
    print_message "$YELLOW" "  Interactive Mode: Enabled (will prompt for confirmations)"
fi
print_message "$YELLOW" "  Stop on Error: $STOP_ON_ERROR"

echo ""

# Step 1: Identify which labs exist
print_message "$YELLOW" "========================================"
print_message "$YELLOW" "Step 1: Identifying Deployed Labs"
print_message "$YELLOW" "========================================"

EXISTING_LABS=()
NON_EXISTING_LABS=()

for lab in "${LABS_TO_CLEANUP[@]}"; do
    if check_lab_exists "$lab"; then
        EXISTING_LABS+=("$lab")
    else
        NON_EXISTING_LABS+=("$lab")
    fi
done

# Print results
if [ ${#NON_EXISTING_LABS[@]} -gt 0 ]; then
    print_message "$YELLOW" "Labs not deployed (will skip):"
    for lab in "${NON_EXISTING_LABS[@]}"; do
        print_message "$YELLOW" "  - Lab${lab}"
    done
else
    print_message "$GREEN" "All labs are deployed"
fi

echo ""

if [ ${#EXISTING_LABS[@]} -gt 0 ]; then
    print_message "$GREEN" "Labs to cleanup:"
    for lab in "${EXISTING_LABS[@]}"; do
        print_message "$GREEN" "  - Lab${lab}"
    done
else
    print_message "$YELLOW" "No labs found to cleanup"
    # Don't exit - continue to orphaned log cleanup
fi

echo ""

# Update LABS_TO_CLEANUP to only include existing labs
LABS_TO_CLEANUP=("${EXISTING_LABS[@]}")

# Confirmation prompt for cleanup all (only if there are labs to cleanup)
if [ ${#EXISTING_LABS[@]} -gt 0 ] && [ "$CLEANUP_ALL" = true ] && [ "$INTERACTIVE" = false ]; then
    print_message "$RED" "WARNING: This will delete ALL resources from the following labs: ${EXISTING_LABS[*]}"
    print_message "$RED" "This action cannot be undone."
    read -p "Are you sure you want to continue? (yes/no) " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        exit 0
    fi
fi

# Record start time
START_TIME=$(date +%s)

# Track cleanup results
SUCCESSFUL_CLEANUPS=()
FAILED_CLEANUPS=()

# Step 2: Cleanup labs based on mode
print_message "$YELLOW" "========================================"
print_message "$YELLOW" "Step 2: Cleaning Up Labs"
print_message "$YELLOW" "========================================"
echo ""

# Check if there are any labs to cleanup
if [ ${#LABS_TO_CLEANUP[@]} -eq 0 ]; then
    print_message "$YELLOW" "No labs to cleanup, skipping to orphaned resource cleanup..."
    echo ""
else
    # Cleanup labs based on mode
    if [ "$CLEANUP_ALL" = true ] && [ "$PARALLEL" = true ]; then
    # Parallel mode: Cleanup independent labs concurrently
    print_message "$YELLOW" "Parallel Cleanup Mode"
    echo ""
    
    # Separate labs into parallel and sequential groups
    PARALLEL_LABS=()
    SEQUENTIAL_LABS=()
    
    for lab in "${LABS_TO_CLEANUP[@]}"; do
        if [[ "$lab" == "7" ]] || [[ "$lab" == "6" ]] || [[ "$lab" == "5" ]]; then
            PARALLEL_LABS+=("$lab")
        else
            SEQUENTIAL_LABS+=("$lab")
        fi
    done
    
    # Lab7-5 can be cleaned in parallel (independent)
    if [ ${#PARALLEL_LABS[@]} -gt 0 ]; then
        if ! cleanup_labs_parallel "${PARALLEL_LABS[@]}"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping cleanup due to parallel cleanup failure"
                SEQUENTIAL_LABS=()
            fi
        fi
    fi
    
    # Lab4-2-1 clean sequentially (Lab4-2 depend on each other, Lab1 is independent but cleaned last)
    for lab in "${SEQUENTIAL_LABS[@]}"; do
        if cleanup_lab "$lab"; then
            SUCCESSFUL_CLEANUPS+=("$lab")
        else
            FAILED_CLEANUPS+=("$lab")
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping cleanup due to Lab${lab} failure"
                break
            fi
        fi
    done
else
    # Sequential mode: Cleanup all labs one by one
    for lab in "${LABS_TO_CLEANUP[@]}"; do
        if cleanup_lab "$lab"; then
            SUCCESSFUL_CLEANUPS+=("$lab")
        else
            FAILED_CLEANUPS+=("$lab")
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping cleanup due to Lab${lab} failure"
                break
            fi
        fi
    done
    fi
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Step 3: Cleanup Orphaned CloudWatch Log Groups
print_message "$YELLOW" "========================================"
print_message "$YELLOW" "Step 3: Cleaning Up Orphaned CloudWatch Log Groups"
print_message "$YELLOW" "========================================"
echo ""

print_message "$YELLOW" "Checking for orphaned CloudWatch log groups..."

# Delete /aws/apigateway/welcome log group
print_message "$YELLOW" "Checking for /aws/apigateway/welcome log group..."
if aws logs describe-log-groups \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --log-group-name-prefix "/aws/apigateway/welcome" \
    --query "logGroups[?logGroupName=='/aws/apigateway/welcome'].logGroupName" \
    --output text 2>/dev/null | grep -q "/aws/apigateway/welcome"; then
    
    print_message "$YELLOW" "  Deleting /aws/apigateway/welcome log group..."
    if aws logs delete-log-group \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --log-group-name "/aws/apigateway/welcome" 2>/dev/null; then
        print_message "$GREEN" "  ✓ Deleted /aws/apigateway/welcome"
    else
        print_message "$RED" "  ✗ Failed to delete /aws/apigateway/welcome"
    fi
else
    print_message "$GREEN" "  ✓ /aws/apigateway/welcome not found (already deleted or never created)"
fi

# Delete /aws/lambda-insights log group
print_message "$YELLOW" "Checking for /aws/lambda-insights log group..."
if aws logs describe-log-groups \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --log-group-name-prefix "/aws/lambda-insights" \
    --query "logGroups[?logGroupName=='/aws/lambda-insights'].logGroupName" \
    --output text 2>/dev/null | grep -q "/aws/lambda-insights"; then
    
    print_message "$YELLOW" "  Deleting /aws/lambda-insights log group..."
    if aws logs delete-log-group \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --log-group-name "/aws/lambda-insights" 2>/dev/null; then
        print_message "$GREEN" "  ✓ Deleted /aws/lambda-insights"
    else
        print_message "$RED" "  ✗ Failed to delete /aws/lambda-insights"
    fi
else
    print_message "$GREEN" "  ✓ /aws/lambda-insights not found (already deleted or never created)"
fi

# Delete orphaned API Gateway execution logs
print_message "$YELLOW" "Checking for orphaned API Gateway execution logs..."
ORPHANED_APIGW_LOGS=$(aws logs describe-log-groups \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --query "logGroups[?starts_with(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_APIGW_LOGS" ]; then
    ORPHANED_COUNT=$(echo "$ORPHANED_APIGW_LOGS" | wc -w | tr -d ' ')
    print_message "$YELLOW" "  Found $ORPHANED_COUNT orphaned API Gateway execution log group(s)"
    
    for log_group in $ORPHANED_APIGW_LOGS; do
        print_message "$YELLOW" "  Deleting: $log_group"
        if aws logs delete-log-group \
            ${PROFILE:+--profile "$PROFILE"} \
            --region us-east-1 \
            --log-group-name "$log_group" 2>/dev/null; then
            print_message "$GREEN" "    ✓ Deleted $log_group"
        else
            print_message "$RED" "    ✗ Failed to delete $log_group"
        fi
    done
else
    print_message "$GREEN" "  ✓ No orphaned API Gateway execution logs found"
fi

echo ""
print_message "$GREEN" "Orphaned CloudWatch log groups cleanup complete"
echo ""

# Step 4: Verify complete cleanup
echo ""
verify_complete_cleanup
VERIFICATION_RESULT=$?

# Print summary
echo ""
print_message "$YELLOW" "========================================"
print_message "$YELLOW" "Cleanup Summary"
print_message "$YELLOW" "========================================"

if [ ${#SUCCESSFUL_CLEANUPS[@]} -gt 0 ]; then
    print_message "$GREEN" "Successfully cleaned labs: ${SUCCESSFUL_CLEANUPS[*]}"
fi

if [ ${#FAILED_CLEANUPS[@]} -gt 0 ]; then
    print_message "$RED" "Failed to clean labs: ${FAILED_CLEANUPS[*]}"
fi

print_message "$YELLOW" "Duration: ${DURATION} seconds"
print_message "$YELLOW" "Log file: $LOG_FILE"
print_message "$YELLOW" "========================================"

# Exit with error if any labs failed
if [ ${#FAILED_CLEANUPS[@]} -gt 0 ]; then
    print_message "$RED" "Some labs failed to cleanup. Check log file for details."
    exit 1
fi

print_message "$GREEN" "All Lab Cleanup Complete!"
