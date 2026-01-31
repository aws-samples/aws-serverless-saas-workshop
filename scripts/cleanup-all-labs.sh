#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$(dirname "$SCRIPT_DIR")"

# Create log file
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-all-labs-$(date +%Y%m%d-%H%M%S).log"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "========================================"
print_message "$BLUE" "AWS Serverless SaaS Workshop"
print_message "$BLUE" "Cleanup All Labs Script"
print_message "$BLUE" "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Function to check if a lab exists (has deployed resources)
check_lab_exists() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    # Check if lab directory exists
    if [ ! -d "$lab_dir" ]; then
        return 1
    fi
    
    # Check if lab has any CloudFormation stacks
    # For each lab, check ALL possible stack patterns (base stacks + dynamic tenant stacks)
    local stacks=""
    case $lab_num in
        1)
            # Lab1: serverless-saas-lab1
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "${LAB1_STACK_NAME:-serverless-saas-lab1}" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        2)
            # Lab2: serverless-saas-lab2
            stacks=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-lab2" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            ;;
        3)
            # Lab3: serverless-saas-shared-lab3, serverless-saas-tenant-lab3
            # Lab3 exists if EITHER shared OR tenant stack exists
            local shared_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab3" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            local tenant_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-tenant-lab3" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Lab3 exists if either shared OR tenant stack exists
            if [[ -n "$shared_stack" && "$shared_stack" != "None" ]] || [[ -n "$tenant_stack" && "$tenant_stack" != "None" ]]; then
                stacks="exists"
            fi
            ;;
        4)
            # Lab4: serverless-saas-shared-lab4, serverless-saas-tenant-lab4
            # Lab4 exists if EITHER shared OR tenant stack exists
            local shared_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab4" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            local tenant_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-tenant-lab4" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Lab4 exists if either shared OR tenant stack exists
            if [[ -n "$shared_stack" && "$shared_stack" != "None" ]] || [[ -n "$tenant_stack" && "$tenant_stack" != "None" ]]; then
                stacks="exists"
            fi
            ;;
        5)
            # Lab5: serverless-saas-shared-lab5, serverless-saas-pipeline-lab5, stack-<tenantId>-lab5
            # Lab5 exists if ANY of these stacks exist
            local shared_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab5" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            local pipeline_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-pipeline-lab5" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Check for dynamic tenant stacks: stack-<tenantId>-lab5
            local tenant_stacks=$(aws cloudformation list-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
                --region us-east-1 \
                --query "StackSummaries[?contains(StackName, '-lab5') && starts_with(StackName, 'stack-')].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Lab5 exists if shared OR pipeline OR any tenant stack exists
            if [[ -n "$shared_stack" && "$shared_stack" != "None" ]] || \
               [[ -n "$pipeline_stack" && "$pipeline_stack" != "None" ]] || \
               [[ -n "$tenant_stacks" ]]; then
                stacks="exists"
            fi
            ;;
        6)
            # Lab6: serverless-saas-shared-lab6, serverless-saas-pipeline-lab6, stack-lab6-pooled, stack-.*-lab6
            # Lab6 exists if ANY of these stacks exist
            local shared_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-shared-lab6" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            local pipeline_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-pipeline-lab6" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Check for pooled stack
            local pooled_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "stack-lab6-pooled" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Check for dynamic tenant stacks: stack-.*-lab6
            local tenant_stacks=$(aws cloudformation list-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
                --region us-east-1 \
                --query "StackSummaries[?contains(StackName, '-lab6') && starts_with(StackName, 'stack-')].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Lab6 exists if shared OR pipeline OR pooled OR any tenant stack exists
            if [[ -n "$shared_stack" && "$shared_stack" != "None" ]] || \
               [[ -n "$pipeline_stack" && "$pipeline_stack" != "None" ]] || \
               [[ -n "$pooled_stack" && "$pooled_stack" != "None" ]] || \
               [[ -n "$tenant_stacks" ]]; then
                stacks="exists"
            fi
            ;;
        7)
            # Lab7: serverless-saas-lab7, stack-pooled-lab7
            # Lab7 exists if EITHER base OR pooled stack exists
            local base_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "serverless-saas-lab7" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            local pooled_stack=$(aws cloudformation describe-stacks \
                ${PROFILE:+--profile "$PROFILE"} \
                --stack-name "stack-pooled-lab7" \
                --region us-east-1 \
                --query "Stacks[0].StackName" \
                --output text 2>/dev/null || echo "")
            
            # Lab7 exists if either base OR pooled stack exists
            if [[ -n "$base_stack" && "$base_stack" != "None" ]] || [[ -n "$pooled_stack" && "$pooled_stack" != "None" ]]; then
                stacks="exists"
            fi
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
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "Final Verification - Checking for Remaining Resources"
    print_message "$BLUE" "========================================"
    
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
    
    # Check for remaining IAM Roles (lab-specific)
    print_message "$YELLOW" "Checking for remaining lab-specific IAM Roles..."
    local remaining_roles=$(aws iam list-roles \
        ${PROFILE:+--profile "$PROFILE"} \
        --query "Roles[?contains(RoleName, 'serverless-saas-lab') || contains(RoleName, 'stack-lab')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_roles" ]; then
        print_message "$RED" "  ⚠️  Found remaining lab-specific IAM Roles:"
        for role in $remaining_roles; do
            print_message "$RED" "    - $role"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$GREEN" "  ✓ No remaining lab-specific IAM Roles"
    fi
    
    # Check for remaining account-level IAM Roles created by workshop
    print_message "$YELLOW" "Checking for remaining account-level IAM Roles..."
    local account_level_roles=("APIGatewayCloudWatchLogsRole")
    local found_account_roles=false
    
    for role_name in "${account_level_roles[@]}"; do
        if aws iam get-role \
            ${PROFILE:+--profile "$PROFILE"} \
            --role-name "$role_name" &>/dev/null; then
            if [ "$found_account_roles" = false ]; then
                print_message "$RED" "  ⚠️  Found remaining account-level IAM Roles:"
                found_account_roles=true
            fi
            print_message "$RED" "    - $role_name"
            remaining_resources=$((remaining_resources + 1))
        fi
    done
    
    if [ "$found_account_roles" = false ]; then
        print_message "$GREEN" "  ✓ No remaining account-level IAM Roles"
    fi
    
    # Check API Gateway account settings for orphaned role ARN references
    print_message "$YELLOW" "Checking API Gateway account settings..."
    local apigw_role_arn=$(aws apigateway get-account \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --query 'cloudwatchRoleArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$apigw_role_arn" && "$apigw_role_arn" != "None" ]]; then
        # Extract role name from ARN
        local role_name=$(echo "$apigw_role_arn" | awk -F'/' '{print $NF}')
        
        # Check if the role still exists in IAM
        if ! aws iam get-role \
            ${PROFILE:+--profile "$PROFILE"} \
            --role-name "$role_name" &>/dev/null; then
            print_message "$RED" "  ⚠️  API Gateway references deleted role: $apigw_role_arn"
            print_message "$YELLOW" "     This is an orphaned reference - the role no longer exists in IAM"
            print_message "$YELLOW" "     Run Step 4.5 again to reset API Gateway account settings"
            remaining_resources=$((remaining_resources + 1))
        else
            print_message "$YELLOW" "  ⚠️  API Gateway references role: $apigw_role_arn"
            print_message "$YELLOW" "     This is expected if the role still exists in IAM"
        fi
    else
        print_message "$GREEN" "  ✓ API Gateway account settings properly reset (no role ARN configured)"
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

# Function to fix pipeline stacks with missing CDK execution role
fix_pipeline_stack_cdk_role() {
    local stack_name=$1
    
    print_message "$YELLOW" "Checking if CDK execution role fix is needed for $stack_name..."
    
    # Check if stack exists
    local stack_status=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$stack_status" == "NOT_FOUND" ]; then
        print_message "$GREEN" "  ✓ Stack $stack_name does not exist, no fix needed"
        return 0
    fi
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity \
        ${PROFILE:+--profile "$PROFILE"} \
        --query Account \
        --output text)
    
    # CDK execution role name
    local cdk_role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-us-east-1"
    
    # Check if role exists
    local role_exists=$(aws iam get-role \
        --role-name "$cdk_role_name" \
        ${PROFILE:+--profile "$PROFILE"} \
        2>/dev/null || echo "")
    
    if [ -n "$role_exists" ]; then
        print_message "$GREEN" "  ✓ CDK execution role exists, no fix needed"
        return 0
    fi
    
    print_message "$YELLOW" "  Creating temporary CDK execution role..."
    
    # Create the role
    aws iam create-role \
        --role-name "$cdk_role_name" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "cloudformation.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_message "$RED" "  ✗ Failed to create CDK execution role"
        return 1
    fi
    
    print_message "$GREEN" "  ✓ CDK execution role created"
    
    # Attach AdministratorAccess policy
    print_message "$YELLOW" "  Attaching AdministratorAccess policy..."
    aws iam attach-role-policy \
        --role-name "$cdk_role_name" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_message "$RED" "  ✗ Failed to attach policy"
        return 1
    fi
    
    print_message "$GREEN" "  ✓ Policy attached"
    
    # Wait for role to propagate
    print_message "$YELLOW" "  Waiting 10 seconds for role to propagate..."
    sleep 10
    
    print_message "$GREEN" "  ✓ CDK execution role fix completed"
    return 0
}

# Function to cleanup CDK execution role after pipeline stack deletion
cleanup_cdk_execution_role() {
    # Get account ID
    local account_id=$(aws sts get-caller-identity \
        ${PROFILE:+--profile "$PROFILE"} \
        --query Account \
        --output text)
    
    # CDK execution role name
    local cdk_role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-us-east-1"
    
    # Check if role exists
    local role_exists=$(aws iam get-role \
        --role-name "$cdk_role_name" \
        ${PROFILE:+--profile "$PROFILE"} \
        2>/dev/null || echo "")
    
    if [ -z "$role_exists" ]; then
        return 0
    fi
    
    print_message "$YELLOW" "Cleaning up temporary CDK execution role..."
    
    # Detach AdministratorAccess policy
    aws iam detach-role-policy \
        --role-name "$cdk_role_name" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 2>/dev/null || true
    
    # Delete the role
    aws iam delete-role \
        --role-name "$cdk_role_name" \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 2>/dev/null || true
    
    print_message "$GREEN" "  ✓ CDK execution role cleaned up"
}

# Function to cleanup a lab
cleanup_lab() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    print_message "$BLUE" "========================================="
    print_message "$BLUE" "Cleaning up Lab${lab_num}"
    print_message "$BLUE" "========================================="
    
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
        
        # For Lab5 and Lab6, fix CDK execution role if needed before cleanup
        if [ "$lab_num" -eq 5 ] || [ "$lab_num" -eq 6 ]; then
            fix_pipeline_stack_cdk_role "serverless-saas-pipeline-lab${lab_num}"
        fi
        
        # Run cleanup script
        if eval "$cleanup_cmd"; then
            print_message "$GREEN" "Lab${lab_num} cleanup completed!"
            
            # For Lab5 and Lab6, cleanup CDK execution role after successful cleanup
            if [ "$lab_num" -eq 5 ] || [ "$lab_num" -eq 6 ]; then
                cleanup_cdk_execution_role
            fi
            
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
PARALLEL=true
INTERACTIVE=false
STOP_ON_ERROR=true
AUTO_CONFIRM=false  # New flag for non-interactive confirmation

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
        --sequential)
            PARALLEL=false
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
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
                echo "  --parallel                  Enable parallel cleanup (DEFAULT)"
                echo "  --sequential                Disable parallel cleanup (clean labs one by one)"
                echo "  -i, --interactive           Prompt for confirmation before each cleanup"
                echo "  -y, --yes                   Auto-confirm all prompts (non-interactive mode)"
                echo "  --continue-on-error         Continue cleaning next lab even if current fails"
                echo "  --help                      Show this help message"
                echo ""
                echo "Cleanup Order:"
                echo "  Parallel cleanup is ENABLED BY DEFAULT for faster cleanup."
                echo "  Use --sequential to disable parallel mode and clean labs one by one."
                echo "  Labs are cleaned in reverse order (Lab7 → Lab1) to respect dependencies"
                echo "  With parallel mode: All 7 labs clean concurrently (estimated 5-10 minutes)"
                echo "  With sequential mode: Labs clean one by one (estimated 20-30 minutes)"
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
                echo "  $0                                      # Cleanup all labs (parallel by default)"
                echo "  $0 --all                                # Cleanup all labs (parallel by default)"
                echo "  $0 --all --profile serverless-saas-demo # Cleanup all labs with specific profile"
                echo "  $0 --all --sequential                   # Cleanup all labs one by one"
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
    print_message "$GREEN" "Cleaning up all labs..."
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
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 1: Identifying Deployed Labs"
print_message "$BLUE" "========================================"

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
if [ ${#EXISTING_LABS[@]} -gt 0 ] && [ "$CLEANUP_ALL" = true ] && [ "$INTERACTIVE" = false ] && [ "$AUTO_CONFIRM" = false ]; then
    print_message "$RED" "WARNING: This will delete ALL resources from the following labs: ${EXISTING_LABS[*]}"
    print_message "$RED" "This action cannot be undone."
    read -p "Are you sure you want to continue? (yes/no) " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        exit 0
    fi
elif [ "$AUTO_CONFIRM" = true ]; then
    print_message "$YELLOW" "Auto-confirm enabled, skipping confirmation prompt"
fi

# Record start time
START_TIME=$(date +%s)

# Track cleanup results
SUCCESSFUL_CLEANUPS=()
FAILED_CLEANUPS=()

# Step 1.5: Identify all lab-related stacks (including orphaned ones)
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 1.5: Identifying All Lab-Related Stacks"
print_message "$BLUE" "========================================"
echo ""

# Query all stacks matching lab patterns
ALL_LAB_STACKS=$(aws cloudformation list-stacks \
    ${PROFILE:+--profile "$PROFILE"} \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
    --region us-east-1 \
    --query 'StackSummaries[?contains(StackName, `lab1`) || contains(StackName, `lab2`) || contains(StackName, `lab3`) || contains(StackName, `lab4`) || contains(StackName, `lab5`) || contains(StackName, `lab6`) || contains(StackName, `lab7`)].StackName' \
    --output text 2>/dev/null || echo "")

# Group stacks by lab and store in variables
DISCOVERED_LAB1=""
DISCOVERED_LAB2=""
DISCOVERED_LAB3=""
DISCOVERED_LAB4=""
DISCOVERED_LAB5=""
DISCOVERED_LAB6=""
DISCOVERED_LAB7=""

for stack in $ALL_LAB_STACKS; do
    if [[ "$stack" == *"lab1"* ]]; then
        DISCOVERED_LAB1+="$stack "
    fi
    if [[ "$stack" == *"lab2"* ]]; then
        DISCOVERED_LAB2+="$stack "
    fi
    if [[ "$stack" == *"lab3"* ]]; then
        DISCOVERED_LAB3+="$stack "
    fi
    if [[ "$stack" == *"lab4"* ]]; then
        DISCOVERED_LAB4+="$stack "
    fi
    if [[ "$stack" == *"lab5"* ]]; then
        DISCOVERED_LAB5+="$stack "
    fi
    if [[ "$stack" == *"lab6"* ]]; then
        DISCOVERED_LAB6+="$stack "
    fi
    if [[ "$stack" == *"lab7"* ]]; then
        DISCOVERED_LAB7+="$stack "
    fi
done

# Display discovered stacks
if [ -n "$ALL_LAB_STACKS" ]; then
    print_message "$GREEN" "Discovered Lab Stacks:"
    
    # Lab1
    if [ -n "$DISCOVERED_LAB1" ]; then
        print_message "$GREEN" "  Lab1:"
        for stack in $DISCOVERED_LAB1; do
            if [[ "$stack" == "serverless-saas-lab1" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab2
    if [ -n "$DISCOVERED_LAB2" ]; then
        print_message "$GREEN" "  Lab2:"
        for stack in $DISCOVERED_LAB2; do
            if [[ "$stack" == "serverless-saas-lab2" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab3
    if [ -n "$DISCOVERED_LAB3" ]; then
        print_message "$GREEN" "  Lab3:"
        for stack in $DISCOVERED_LAB3; do
            if [[ "$stack" == "serverless-saas-shared-lab3" || "$stack" == "serverless-saas-tenant-lab3" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab4
    if [ -n "$DISCOVERED_LAB4" ]; then
        print_message "$GREEN" "  Lab4:"
        for stack in $DISCOVERED_LAB4; do
            if [[ "$stack" == "serverless-saas-shared-lab4" || "$stack" == "serverless-saas-tenant-lab4" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab5
    if [ -n "$DISCOVERED_LAB5" ]; then
        print_message "$GREEN" "  Lab5:"
        for stack in $DISCOVERED_LAB5; do
            if [[ "$stack" == "serverless-saas-shared-lab5" || "$stack" == "serverless-saas-pipeline-lab5" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab6
    if [ -n "$DISCOVERED_LAB6" ]; then
        print_message "$GREEN" "  Lab6:"
        for stack in $DISCOVERED_LAB6; do
            if [[ "$stack" == "serverless-saas-shared-lab6" || "$stack" == "serverless-saas-pipeline-lab6" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
    
    # Lab7
    if [ -n "$DISCOVERED_LAB7" ]; then
        print_message "$GREEN" "  Lab7:"
        for stack in $DISCOVERED_LAB7; do
            if [[ "$stack" == "serverless-saas-lab7" ]]; then
                print_message "$GREEN" "    - $stack"
            else
                print_message "$YELLOW" "    - $stack (orphaned - not in expected list)"
            fi
        done
    fi
else
    print_message "$YELLOW" "No lab-related stacks found"
fi

echo ""

# Step 2: Cleanup labs based on mode
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 2: Cleaning Up Labs"
print_message "$BLUE" "========================================"
echo ""

# Check if there are any labs to cleanup
if [ ${#LABS_TO_CLEANUP[@]} -eq 0 ]; then
    print_message "$YELLOW" "No labs to cleanup, skipping to orphaned resource cleanup..."
    echo ""
else
    # Cleanup labs based on mode
    if [ "$CLEANUP_ALL" = true ] && [ "$PARALLEL" = true ]; then
        # Parallel mode: Cleanup all 7 labs concurrently
        print_message "$YELLOW" "Parallel Cleanup Mode - All 7 labs cleaning concurrently"
        echo ""
        
        # Cleanup all labs in parallel
        if ! cleanup_labs_parallel "${LABS_TO_CLEANUP[@]}"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping cleanup due to parallel cleanup failure"
            fi
        fi
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
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 3: Cleaning Up Orphaned CloudWatch Log Groups"
print_message "$BLUE" "========================================"
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

# Delete /aws-glue/crawlers log group (created by Lab7)
print_message "$YELLOW" "Checking for /aws-glue/crawlers log group..."
if aws logs describe-log-groups \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --log-group-name-prefix "/aws-glue/crawlers" \
    --query "logGroups[?logGroupName=='/aws-glue/crawlers'].logGroupName" \
    --output text 2>/dev/null | grep -q "/aws-glue/crawlers"; then
    
    print_message "$YELLOW" "  Deleting /aws-glue/crawlers log group..."
    if aws logs delete-log-group \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --log-group-name "/aws-glue/crawlers" 2>/dev/null; then
        print_message "$GREEN" "  ✓ Deleted /aws-glue/crawlers"
    else
        print_message "$RED" "  ✗ Failed to delete /aws-glue/crawlers"
    fi
else
    print_message "$GREEN" "  ✓ /aws-glue/crawlers not found (already deleted or never created)"
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

# Step 3.5: Clean up orphaned resources (stacks, S3 buckets, logs)
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 3.5: Cleaning Up Orphaned Resources"
print_message "$BLUE" "========================================"
echo ""

# Helper function to check if a stack is a nested stack
is_nested_stack() {
    local stack_name="$1"
    local parent_id=$(aws cloudformation describe-stacks \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --stack-name "$stack_name" \
        --query 'Stacks[0].ParentId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$parent_id" && "$parent_id" != "None" ]]; then
        return 0  # Is a nested stack
    else
        return 1  # Not a nested stack
    fi
}

# Helper function to check if a stack name matches expected patterns
is_expected_stack() {
    local stack_name="$1"
    local lab_num="$2"
    
    case "$lab_num" in
        1)
            [[ "$stack_name" == "serverless-saas-lab1" ]]
            ;;
        2)
            [[ "$stack_name" == "serverless-saas-lab2" ]]
            ;;
        3)
            [[ "$stack_name" == "serverless-saas-shared-lab3" || "$stack_name" == "serverless-saas-tenant-lab3" || "$stack_name" =~ ^stack-lab3- || "$stack_name" =~ -lab3$ ]]
            ;;
        4)
            [[ "$stack_name" == "serverless-saas-shared-lab4" || "$stack_name" == "serverless-saas-tenant-lab4" || "$stack_name" =~ ^stack-lab4- || "$stack_name" =~ -lab4$ ]]
            ;;
        5)
            [[ "$stack_name" == "serverless-saas-shared-lab5" || "$stack_name" == "serverless-saas-pipeline-lab5" || "$stack_name" =~ ^stack-lab5- || "$stack_name" =~ -lab5$ ]]
            ;;
        6)
            [[ "$stack_name" == "serverless-saas-shared-lab6" || "$stack_name" == "serverless-saas-pipeline-lab6" || "$stack_name" =~ ^stack-lab6- || "$stack_name" =~ -lab6$ ]]
            ;;
        7)
            [[ "$stack_name" == "serverless-saas-lab7" || "$stack_name" =~ ^stack-.*-lab7$ || "$stack_name" =~ -lab7$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Re-query all lab-related stacks AFTER individual lab cleanups to get current state
print_message "$YELLOW" "Re-querying lab-related stacks after individual cleanups..."
CURRENT_LAB_STACKS=$(aws cloudformation list-stacks \
    ${PROFILE:+--profile "$PROFILE"} \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
    --region us-east-1 \
    --query 'StackSummaries[?contains(StackName, `lab1`) || contains(StackName, `lab2`) || contains(StackName, `lab3`) || contains(StackName, `lab4`) || contains(StackName, `lab5`) || contains(StackName, `lab6`) || contains(StackName, `lab7`)].StackName' \
    --output text 2>/dev/null || echo "")

# Find orphaned S3 buckets
ORPHANED_BUCKETS=$(aws s3api list-buckets \
    ${PROFILE:+--profile "$PROFILE"} \
    --query 'Buckets[?contains(Name, `lab1`) || contains(Name, `lab2`) || contains(Name, `lab3`) || contains(Name, `lab4`) || contains(Name, `lab5`) || contains(Name, `lab6`) || contains(Name, `lab7`)].Name' \
    --output text 2>/dev/null || echo "")

# Find orphaned CloudWatch log groups (not already cleaned in Step 3)
ORPHANED_LOGS=$(aws logs describe-log-groups \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --query 'logGroups[?contains(logGroupName, `lab1`) || contains(logGroupName, `lab2`) || contains(logGroupName, `lab3`) || contains(logGroupName, `lab4`) || contains(logGroupName, `lab5`) || contains(logGroupName, `lab6`) || contains(logGroupName, `lab7`)].logGroupName' \
    --output text 2>/dev/null || echo "")

# Find orphaned stacks (stacks that still exist and are not expected)
ORPHANED_STACKS=""

for stack in $CURRENT_LAB_STACKS; do
    # Skip nested stacks (they are managed by parent stacks)
    if is_nested_stack "$stack"; then
        continue
    fi
    
    # Determine which lab this stack belongs to
    lab_num=""
    if [[ "$stack" == *"lab1"* ]]; then
        lab_num="1"
    elif [[ "$stack" == *"lab2"* ]]; then
        lab_num="2"
    elif [[ "$stack" == *"lab3"* ]]; then
        lab_num="3"
    elif [[ "$stack" == *"lab4"* ]]; then
        lab_num="4"
    elif [[ "$stack" == *"lab5"* ]]; then
        lab_num="5"
    elif [[ "$stack" == *"lab6"* ]]; then
        lab_num="6"
    elif [[ "$stack" == *"lab7"* ]]; then
        lab_num="7"
    fi
    
    # Check if this stack is expected for its lab
    if [[ -n "$lab_num" ]]; then
        if ! is_expected_stack "$stack" "$lab_num"; then
            # Stack name doesn't match expected patterns - it's orphaned
            ORPHANED_STACKS+="$stack "
        else
            # Stack name matches expected pattern - check if lab was supposed to be cleaned
            lab_was_cleaned=false
            for cleaned_lab in "${SUCCESSFUL_CLEANUPS[@]}"; do
                if [[ "$cleaned_lab" == "$lab_num" ]]; then
                    lab_was_cleaned=true
                    break
                fi
            done
            
            # If lab was cleaned but stack still exists, it's orphaned
            if [[ "$lab_was_cleaned" == true ]]; then
                ORPHANED_STACKS+="$stack "
            fi
        fi
    else
        # Stack doesn't match any lab pattern - it's orphaned
        ORPHANED_STACKS+="$stack "
    fi
done

# Display orphaned resources
if [[ -n "$ORPHANED_STACKS" || -n "$ORPHANED_BUCKETS" || -n "$ORPHANED_LOGS" ]]; then
    print_message "$YELLOW" "Orphaned Resources Found:"
    
    if [[ -n "$ORPHANED_STACKS" ]]; then
        print_message "$YELLOW" "  CloudFormation Stacks:"
        for stack in $ORPHANED_STACKS; do
            print_message "$YELLOW" "    - $stack"
        done
    fi
    
    if [[ -n "$ORPHANED_BUCKETS" ]]; then
        print_message "$YELLOW" "  S3 Buckets:"
        for bucket in $ORPHANED_BUCKETS; do
            print_message "$YELLOW" "    - $bucket"
        done
    fi
    
    if [[ -n "$ORPHANED_LOGS" ]]; then
        print_message "$YELLOW" "  CloudWatch Log Groups:"
        for log in $ORPHANED_LOGS; do
            print_message "$YELLOW" "    - $log"
        done
    fi
    
    echo ""
    print_message "$RED" "WARNING: Orphaned resources detected that were not cleaned up by lab-specific cleanup scripts."
    print_message "$RED" "These resources may have been created outside the normal deployment process."
    echo ""
    
    if [ "$INTERACTIVE" = true ]; then
        read -p "Delete orphaned resources? (yes/no): " confirm
    else
        confirm="yes"  # Auto-confirm in non-interactive mode
    fi
    
    if [[ "$confirm" == "yes" ]]; then
        # Delete orphaned stacks first (CloudFormation will delete associated resources)
        if [[ -n "$ORPHANED_STACKS" ]]; then
            print_message "$YELLOW" "  Deleting orphaned CloudFormation stacks..."
            for stack in $ORPHANED_STACKS; do
                print_message "$YELLOW" "    Deleting stack: $stack"
                if aws cloudformation delete-stack \
                    ${PROFILE:+--profile "$PROFILE"} \
                    --region us-east-1 \
                    --stack-name "$stack" 2>/dev/null; then
                    print_message "$GREEN" "      ✓ Initiated deletion of $stack"
                else
                    print_message "$RED" "      ✗ Failed to delete $stack"
                fi
            done
            
            # Wait for stack deletions to complete
            print_message "$YELLOW" "    Waiting for stack deletions to complete..."
            for stack in $ORPHANED_STACKS; do
                aws cloudformation wait stack-delete-complete \
                    ${PROFILE:+--profile "$PROFILE"} \
                    --region us-east-1 \
                    --stack-name "$stack" 2>/dev/null || true
            done
            print_message "$GREEN" "    ✓ Orphaned stacks deleted"
        fi
        
        # Delete orphaned S3 buckets
        if [[ -n "$ORPHANED_BUCKETS" ]]; then
            print_message "$YELLOW" "  Deleting orphaned S3 buckets..."
            for bucket in $ORPHANED_BUCKETS; do
                print_message "$YELLOW" "    Emptying and deleting bucket: $bucket"
                # Empty bucket first
                if aws s3 rm "s3://$bucket" --recursive ${PROFILE:+--profile "$PROFILE"} 2>/dev/null; then
                    # Delete bucket
                    if aws s3api delete-bucket \
                        ${PROFILE:+--profile "$PROFILE"} \
                        --bucket "$bucket" 2>/dev/null; then
                        print_message "$GREEN" "      ✓ Deleted $bucket"
                    else
                        print_message "$RED" "      ✗ Failed to delete $bucket"
                    fi
                else
                    print_message "$RED" "      ✗ Failed to empty $bucket"
                fi
            done
        fi
        
        # Delete orphaned log groups
        if [[ -n "$ORPHANED_LOGS" ]]; then
            print_message "$YELLOW" "  Deleting orphaned CloudWatch log groups..."
            for log in $ORPHANED_LOGS; do
                print_message "$YELLOW" "    Deleting log group: $log"
                if aws logs delete-log-group \
                    ${PROFILE:+--profile "$PROFILE"} \
                    --region us-east-1 \
                    --log-group-name "$log" 2>/dev/null; then
                    print_message "$GREEN" "      ✓ Deleted $log"
                else
                    print_message "$RED" "      ✗ Failed to delete $log"
                fi
            done
        fi
        
        print_message "$GREEN" "  ✓ Orphaned resources cleanup complete"
    else
        print_message "$YELLOW" "  ⚠️  Skipped orphaned resource cleanup"
    fi
else
    print_message "$GREEN" "  ✓ No orphaned resources found"
fi

echo ""

# Step 3.7: Clean up CDKToolkit Stack
# The CDKToolkit stack must be deleted BEFORE IAM roles to avoid dependency issues
# CDK bootstrap creates IAM roles that are referenced by the CDKToolkit stack
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 3.7: Cleaning Up CDKToolkit Stack"
print_message "$BLUE" "========================================"
echo ""

print_message "$YELLOW" "Checking for CDKToolkit stack..."

# Check if CDKToolkit stack exists
if aws cloudformation describe-stacks \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --stack-name "CDKToolkit" \
    --query "Stacks[0].StackName" \
    --output text 2>/dev/null | grep -q "CDKToolkit"; then
    
    print_message "$YELLOW" "  Found CDKToolkit stack - initiating deletion..."
    
    # Delete the CDKToolkit stack
    if aws cloudformation delete-stack \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --stack-name "CDKToolkit" 2>/dev/null; then
        print_message "$GREEN" "  ✓ Initiated deletion of CDKToolkit stack"
        
        # Wait for stack deletion to complete
        print_message "$YELLOW" "  Waiting for CDKToolkit stack deletion to complete..."
        print_message "$YELLOW" "  (This may take a few minutes as CloudFormation deletes all CDK bootstrap resources)"
        
        if aws cloudformation wait stack-delete-complete \
            ${PROFILE:+--profile "$PROFILE"} \
            --region us-east-1 \
            --stack-name "CDKToolkit" 2>/dev/null; then
            print_message "$GREEN" "  ✓ CDKToolkit stack deleted successfully"
        else
            print_message "$RED" "  ✗ Failed to wait for CDKToolkit stack deletion"
            print_message "$YELLOW" "  Note: Stack deletion may still be in progress"
        fi
    else
        print_message "$RED" "  ✗ Failed to initiate CDKToolkit stack deletion"
    fi
else
    print_message "$GREEN" "  ✓ CDKToolkit stack not found (already deleted or never created)"
fi

echo ""
print_message "$GREEN" "CDKToolkit stack cleanup complete"
echo ""

# Step 4: Clean up account-level IAM roles (AFTER all labs are cleaned)
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 4: Cleaning Up Account-Level IAM Roles"
print_message "$BLUE" "========================================"
echo ""

print_message "$YELLOW" "Checking for workshop-created account-level IAM roles..."

# Define account-level roles created by the workshop
# These roles are shared across labs and should only be deleted when ALL labs are cleaned up
ACCOUNT_LEVEL_ROLES=(
    "apigateway-cloudwatch-publish-role"
)

# Track if any roles were found
ROLES_FOUND=false

for role_name in "${ACCOUNT_LEVEL_ROLES[@]}"; do
    # Check if role exists
    if aws iam get-role \
        ${PROFILE:+--profile "$PROFILE"} \
        --role-name "$role_name" &>/dev/null; then
        
        ROLES_FOUND=true
        print_message "$YELLOW" "  Found account-level role: $role_name"
        
        # Detach managed policies
        print_message "$YELLOW" "    Detaching managed policies..."
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            ${PROFILE:+--profile "$PROFILE"} \
            --role-name "$role_name" \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            print_message "$YELLOW" "      Detaching policy: $policy_arn"
            aws iam detach-role-policy \
                ${PROFILE:+--profile "$PROFILE"} \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies
        print_message "$YELLOW" "    Deleting inline policies..."
        INLINE_POLICIES=$(aws iam list-role-policies \
            ${PROFILE:+--profile "$PROFILE"} \
            --role-name "$role_name" \
            --query "PolicyNames[]" \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            print_message "$YELLOW" "      Deleting inline policy: $policy_name"
            aws iam delete-role-policy \
                ${PROFILE:+--profile "$PROFILE"} \
                --role-name "$role_name" \
                --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete the role
        print_message "$YELLOW" "    Deleting role: $role_name"
        if aws iam delete-role \
            ${PROFILE:+--profile "$PROFILE"} \
            --role-name "$role_name" 2>/dev/null; then
            print_message "$GREEN" "      ✓ Role deleted: $role_name"
        else
            print_message "$RED" "      ✗ Failed to delete role: $role_name"
        fi
    fi
done

if [ "$ROLES_FOUND" = false ]; then
    print_message "$GREEN" "  ✓ No account-level roles found (already deleted or never created)"
fi

echo ""
print_message "$GREEN" "Account-level IAM roles cleanup complete"
echo ""

# IMPORTANT: Service-linked roles like AWSServiceRoleForAPIGateway are NOT deleted
# These are AWS-managed roles and should never be deleted by cleanup scripts

# Step 4.5: Reset API Gateway Account Settings
# After deleting the APIGatewayCloudWatchLogsRole, we need to reset the API Gateway
# account settings to remove the role ARN reference. Otherwise, the deleted role ARN
# will still appear in the AWS console even though the IAM role no longer exists.
echo ""
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 4.5: Resetting API Gateway Account Settings"
print_message "$BLUE" "========================================"
echo ""

# Check if API Gateway account settings have a CloudWatch Logs role configured
print_message "$YELLOW" "Checking API Gateway account settings..."
APIGW_ROLE_ARN=$(aws apigateway get-account \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --query 'cloudwatchRoleArn' \
    --output text 2>/dev/null || echo "")

if [[ -n "$APIGW_ROLE_ARN" && "$APIGW_ROLE_ARN" != "None" ]]; then
    print_message "$YELLOW" "  Found API Gateway CloudWatch Logs role ARN: $APIGW_ROLE_ARN"
    
    # Extract role name from ARN
    ROLE_NAME=$(echo "$APIGW_ROLE_ARN" | awk -F'/' '{print $NF}')
    
    # Check if the role still exists in IAM
    if ! aws iam get-role \
        ${PROFILE:+--profile "$PROFILE"} \
        --role-name "$ROLE_NAME" &>/dev/null; then
        
        print_message "$YELLOW" "  Role no longer exists in IAM - resetting API Gateway account settings"
        
        # Reset API Gateway account settings to remove the role ARN reference
        if aws apigateway update-account \
            ${PROFILE:+--profile "$PROFILE"} \
            --region us-east-1 \
            --patch-operations op=replace,path=/cloudwatchRoleArn,value='' 2>/dev/null; then
            print_message "$GREEN" "    ✓ API Gateway account settings reset successfully"
            print_message "$GREEN" "    ✓ Role ARN reference removed from API Gateway"
        else
            print_message "$RED" "    ✗ Failed to reset API Gateway account settings"
            print_message "$YELLOW" "    Note: This is cosmetic - the role is already deleted from IAM"
        fi
    else
        print_message "$GREEN" "  ✓ Role still exists in IAM - no action needed"
        print_message "$YELLOW" "    (Role ARN will be removed when the role is deleted)"
    fi
else
    print_message "$GREEN" "  ✓ No API Gateway CloudWatch Logs role configured"
fi

echo ""
print_message "$GREEN" "API Gateway account settings check complete"
echo ""

# Step 5: Verify complete cleanup
echo ""
verify_complete_cleanup
VERIFICATION_RESULT=$?

# Print summary
echo ""
print_message "$BLUE" "========================================"
print_message "$BLUE" "Cleanup Summary"
print_message "$BLUE" "========================================"

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
