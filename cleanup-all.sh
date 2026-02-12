#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# =============================================================================
# AWS Serverless SaaS Workshop - Cleanup All Labs Script
# =============================================================================
# This script cleans up all resources deployed by the orchestration template.
# 
# CRITICAL SECURITY: This script follows secure deletion order to prevent
# CloudFront Origin Hijacking vulnerability:
#   1. Delete CloudFormation stacks FIRST (CloudFormation handles CloudFront before S3)
#   2. Wait for stack deletion to complete (15-30 minutes for CloudFront propagation)
#   3. Delete orphaned resources (S3 buckets, CloudWatch logs, CDKToolkit)
#
# USAGE:
#   ./cleanup-all.sh --profile <aws-profile>
#   ./cleanup-all.sh --profile <aws-profile> --stack-name <custom-stack-name>
#
# CRITICAL: Execute this script directly (./cleanup-all.sh), NEVER with bash command
# =============================================================================

set -e

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# SCRIPT DIRECTORY DETECTION
# =============================================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$SCRIPT_DIR"
ORCHESTRATION_DIR="$SCRIPT_DIR/scripts"

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================
DEFAULT_STACK_NAME="serverless-saas-lab"
DEFAULT_REGION="us-east-1"

# =============================================================================
# VARIABLES
# =============================================================================
STACK_NAME=""
PROFILE=""
REGION="$DEFAULT_REGION"
AUTO_CONFIRM=false
INTERACTIVE=false

# Tracking arrays
DELETED_STACKS=()
FAILED_STACKS=()
DELETED_BUCKETS=()
DELETED_LOG_GROUPS=()
ERRORS=()

# Deduplication flag: CDK bucket is targeted by multiple functions
CDK_BUCKET_DELETED=false
# =============================================================================
# LOGGING SETUP
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$ORCHESTRATION_DIR/logs/$TIMESTAMP"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-all.log"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Log message to file and console
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "INFO")
            print_message "$GREEN" "$message"
            ;;
        "WARN")
            print_message "$YELLOW" "$message"
            ;;
        "ERROR")
            print_message "$RED" "$message"
            ERRORS+=("$message")
            ;;
        "DEBUG")
            print_message "$CYAN" "$message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Log error with context
log_error() {
    local error_type=$1
    local resource=$2
    local message=$3
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] ERROR [$error_type] $resource: $message" >> "$LOG_FILE"
    print_message "$RED" "ERROR [$error_type] $resource: $message"
    ERRORS+=("[$error_type] $resource: $message")
}

# Check if a lab directory exists
lab_exists() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    if [[ -d "$lab_dir" ]]; then
        return 0  # Lab exists
    else
        log_message "WARNING" "Lab $lab_num directory not found: $lab_dir"
        return 1  # Lab doesn't exist
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
show_help() {
    cat << EOF
AWS Serverless SaaS Workshop - Cleanup All Labs Script

USAGE:
    ./cleanup-all.sh --profile <aws-profile> [OPTIONS]

REQUIRED:
    --profile <profile>         AWS CLI profile name (REQUIRED)

OPTIONS:
    --stack-name <name>         Main orchestration stack name (default: $DEFAULT_STACK_NAME)
    --region <region>           AWS region (default: $DEFAULT_REGION)
    -y, --yes                   Auto-confirm all prompts (non-interactive mode)
    -i, --interactive           Prompt for confirmation at each step
    --help                      Show this help message

CLEANUP ORDER (Security-Critical):
    1. Delete main orchestration stack (CloudFormation handles nested stacks)
       - CloudFormation automatically deletes CloudFront distributions BEFORE S3 buckets
       - This prevents CloudFront Origin Hijacking vulnerability
    2. Wait for stack deletion to complete (15-30 minutes for CloudFront propagation)
    3. Delete dynamic tenant stacks (created by pipelines, not part of nested hierarchy)
       - stack-*-lab5 (Lab5 tenant stacks)
       - stack-*-lab6 (Lab6 tenant stacks)
       - stack-pooled-lab7 (Lab7 pooled stack)
    4. Delete orphaned resources
       - CloudWatch log groups
       - S3 buckets (SAM bootstrap, CDK assets)
       - CDKToolkit stack

EXAMPLES:
    # Basic cleanup with required profile
    ./cleanup-all.sh --profile serverless-saas-demo

    # Cleanup with custom stack name
    ./cleanup-all.sh --profile serverless-saas-demo --stack-name my-workshop

    # Non-interactive cleanup (auto-confirm)
    ./cleanup-all.sh --profile serverless-saas-demo -y

CRITICAL:
    - Execute this script directly: ./cleanup-all.sh
    - NEVER run with bash command: bash cleanup-all.sh (WILL FAIL)
    - The --profile parameter is REQUIRED

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                if [[ -z "$2" || "$2" == --* ]]; then
                    print_message "$RED" "ERROR: --profile requires a value"
                    exit 1
                fi
                PROFILE="$2"
                shift 2
                ;;
            --stack-name)
                if [[ -z "$2" || "$2" == --* ]]; then
                    print_message "$RED" "ERROR: --stack-name requires a value"
                    exit 1
                fi
                STACK_NAME="$2"
                shift 2
                ;;
            --region)
                if [[ -z "$2" || "$2" == --* ]]; then
                    print_message "$RED" "ERROR: --region requires a value"
                    exit 1
                fi
                REGION="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                print_message "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROFILE" ]]; then
        print_message "$RED" "ERROR: --profile is required"
        echo ""
        echo "Usage: ./cleanup-all.sh --profile <aws-profile>"
        echo "Use --help for more information"
        exit 1
    fi

    # Set default stack name if not provided
    if [[ -z "$STACK_NAME" ]]; then
        STACK_NAME="$DEFAULT_STACK_NAME"
    fi
}

# =============================================================================
# STACK VERIFICATION FUNCTIONS
# =============================================================================

# Check if a stack exists
stack_exists() {
    local stack_name=$1
    local status=$(aws cloudformation describe-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$stack_name" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$status" != "NOT_FOUND" && "$status" != "DELETE_COMPLETE" ]]; then
        return 0  # Stack exists
    else
        return 1  # Stack doesn't exist
    fi
}

# Get stack status
get_stack_status() {
    local stack_name=$1
    aws cloudformation describe-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$stack_name" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "NOT_FOUND"
}

# Check if stack belongs to a specific lab (for isolation verification)
stack_belongs_to_lab() {
    local stack_name=$1
    local lab_pattern=$2
    
    if [[ "$stack_name" == *"$lab_pattern"* ]]; then
        return 0  # Matches
    else
        return 1  # Doesn't match
    fi
}

# Verify stack matches target patterns before deletion (lab isolation)
verify_stack_for_deletion() {
    local stack_name=$1
    
    # Define valid patterns for orchestration cleanup
    local valid_patterns=(
        "serverless-saas-lab"
        "serverless-saas-shared-lab"
        "serverless-saas-tenant-lab"
        "serverless-saas-pipeline-lab"
        "stack-.*-lab5"
        "stack-lab5-"
        "stack-.*-lab6"
        "stack-lab6-"
        "stack-.*-lab7"
        "stack-lab7-"
        "stack-pooled-lab7"
        "$STACK_NAME"
    )
    
    for pattern in "${valid_patterns[@]}"; do
        if [[ "$stack_name" =~ $pattern ]]; then
            return 0  # Valid for deletion
        fi
    done
    
    log_message "WARN" "Stack '$stack_name' does not match expected patterns - skipping for safety"
    return 1  # Not valid for deletion
}

# =============================================================================
# MAIN STACK DELETION (Task 5.2)
# =============================================================================

# Delete the main orchestration stack with automatic retry
# On first failure, runs orphaned resource cleanup to remove blockers (e.g. non-empty S3 buckets),
# then retries the stack deletion.
delete_main_stack_with_retry() {
    local max_attempts=2
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if delete_main_stack; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_message "WARN" "========================================"
            log_message "WARN" "Main stack deletion failed — cleaning up blockers before retry"
            log_message "WARN" "========================================"
            echo ""

            # Empty any S3 buckets that blocked nested stack deletion
            delete_orphaned_s3_buckets

            # Reset tracking arrays so the retry starts clean
            FAILED_STACKS=()
            ERRORS=()

            log_message "INFO" ""
            log_message "INFO" "========================================"
            log_message "INFO" "Retry Attempt $((attempt + 1)) of $max_attempts"
            log_message "INFO" "========================================"
            echo ""
        fi

        ((attempt++))
    done

    log_message "ERROR" "Main stack deletion failed after $max_attempts attempts"
    return 1
}

# Delete the main orchestration stack
# CloudFormation automatically handles nested stack deletion in correct order
# (CloudFront distributions are deleted before S3 buckets)
delete_main_stack() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 1: Deleting Main Orchestration Stack"
    log_message "INFO" "========================================"
    echo ""
    
    # Check if main stack exists
    if ! stack_exists "$STACK_NAME"; then
        log_message "WARN" "Main orchestration stack '$STACK_NAME' not found"
        log_message "INFO" "Proceeding to cleanup dynamic tenant stacks and orphaned resources..."
        return 0
    fi
    
    local stack_status=$(get_stack_status "$STACK_NAME")
    log_message "INFO" "Found main stack: $STACK_NAME (Status: $stack_status)"
    
    # Handle DELETE_FAILED state
    if [[ "$stack_status" == "DELETE_FAILED" ]]; then
        log_message "WARN" "Stack is in DELETE_FAILED state - attempting to retry deletion"
    fi
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true && "$INTERACTIVE" == true ]]; then
        read -p "Delete main orchestration stack '$STACK_NAME'? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Skipping main stack deletion"
            return 0
        fi
    fi
    
    log_message "INFO" "Initiating deletion of main orchestration stack..."
    log_message "INFO" "CloudFormation will automatically delete all nested stacks"
    log_message "INFO" "This includes CloudFront distributions (deleted BEFORE S3 buckets for security)"
    echo ""
    
    # Delete the stack
    if aws cloudformation delete-stack \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$STACK_NAME" 2>/dev/null; then
        
        log_message "INFO" "✓ Stack deletion initiated: $STACK_NAME"
        DELETED_STACKS+=("$STACK_NAME")
        
        # Wait for deletion to complete
        log_message "INFO" "Waiting for stack deletion to complete..."
        log_message "INFO" "(This may take 15-30 minutes due to CloudFront distribution propagation)"
        echo ""
        
        # Use a timeout for the wait command
        local wait_start=$(date +%s)
        local max_wait=2700  # 45 minutes max wait
        
        while true; do
            local current_status=$(get_stack_status "$STACK_NAME")
            local elapsed=$(($(date +%s) - wait_start))
            
            if [[ "$current_status" == "NOT_FOUND" || "$current_status" == "DELETE_COMPLETE" ]]; then
                log_message "INFO" "✓ Main orchestration stack deleted successfully"
                return 0
            elif [[ "$current_status" == "DELETE_FAILED" ]]; then
                log_error "STACK_DELETE_FAILED" "$STACK_NAME" "Stack deletion failed"
                FAILED_STACKS+=("$STACK_NAME")
                return 1
            elif [[ $elapsed -gt $max_wait ]]; then
                log_error "TIMEOUT" "$STACK_NAME" "Stack deletion timed out after $max_wait seconds"
                FAILED_STACKS+=("$STACK_NAME")
                return 1
            fi
            
            # Progress update every 60 seconds
            if [[ $((elapsed % 60)) -eq 0 && $elapsed -gt 0 ]]; then
                log_message "DEBUG" "  Still waiting... (${elapsed}s elapsed, status: $current_status)"
            fi
            
            sleep 10
        done
    else
        log_error "STACK_DELETE_FAILED" "$STACK_NAME" "Failed to initiate stack deletion"
        FAILED_STACKS+=("$STACK_NAME")
        return 1
    fi
}

# =============================================================================
# DYNAMIC TENANT STACK CLEANUP (Task 5.3)
# =============================================================================

# Find and delete dynamic tenant stacks created by pipelines
# These are NOT part of the nested stack hierarchy and need separate cleanup
# Patterns:
#   - stack-*-lab5 (Lab5 tenant stacks)
#   - stack-*-lab6 (Lab6 tenant stacks)  
#   - stack-pooled-lab7 (Lab7 pooled stack)
#   - stack-lab6-pooled (Lab6 pooled stack)
delete_dynamic_tenant_stacks() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 2: Deleting Dynamic Tenant Stacks"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Searching for dynamic tenant stacks..."
    
    # Find all stacks matching tenant patterns
    local tenant_stacks=$(aws cloudformation list-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE DELETE_FAILED \
        --query "StackSummaries[?starts_with(StackName, 'stack-')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$tenant_stacks" ]]; then
        log_message "INFO" "✓ No dynamic tenant stacks found"
        return 0
    fi
    
    # Filter to only lab-specific tenant stacks
    local lab5_stacks=""
    local lab6_stacks=""
    local lab7_stacks=""
    
    for stack in $tenant_stacks; do
        # Lab5 tenant stacks: stack-*-lab5 or stack-lab5-*
        if [[ "$stack" =~ ^stack-.*-lab5$ || "$stack" =~ ^stack-lab5- ]]; then
            lab5_stacks+="$stack "
        fi
        # Lab6 tenant stacks: stack-*-lab6 or stack-lab6-*
        if [[ "$stack" =~ ^stack-.*-lab6$ || "$stack" =~ ^stack-lab6- ]]; then
            lab6_stacks+="$stack "
        fi
        # Lab7 pooled stack: stack-pooled-lab7 or stack-*-lab7 or stack-lab7-*
        if [[ "$stack" =~ ^stack-.*-lab7$ || "$stack" =~ ^stack-lab7- || "$stack" == "stack-pooled-lab7" ]]; then
            lab7_stacks+="$stack "
        fi
    done
    
    # Display found stacks
    local found_any=false
    
    if [[ -n "$lab5_stacks" ]]; then
        found_any=true
        log_message "INFO" "Found Lab5 tenant stacks:"
        for stack in $lab5_stacks; do
            log_message "INFO" "  - $stack"
        done
    fi
    
    if [[ -n "$lab6_stacks" ]]; then
        found_any=true
        log_message "INFO" "Found Lab6 tenant stacks:"
        for stack in $lab6_stacks; do
            log_message "INFO" "  - $stack"
        done
    fi
    
    if [[ -n "$lab7_stacks" ]]; then
        found_any=true
        log_message "INFO" "Found Lab7 tenant stacks:"
        for stack in $lab7_stacks; do
            log_message "INFO" "  - $stack"
        done
    fi
    
    if [[ "$found_any" == false ]]; then
        log_message "INFO" "✓ No dynamic tenant stacks found matching lab patterns"
        return 0
    fi
    
    echo ""
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true && "$INTERACTIVE" == true ]]; then
        read -p "Delete all dynamic tenant stacks? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Skipping dynamic tenant stack deletion"
            return 0
        fi
    fi
    
    # Delete stacks in parallel
    log_message "INFO" "Deleting dynamic tenant stacks in parallel..."
    
    local all_tenant_stacks="$lab5_stacks $lab6_stacks $lab7_stacks"
    local pids=()
    
    for stack in $all_tenant_stacks; do
        if [[ -n "$stack" ]]; then
            # Verify stack matches expected patterns (lab isolation)
            if verify_stack_for_deletion "$stack"; then
                (
                    if aws cloudformation delete-stack \
                        --profile "$PROFILE" \
                        --region "$REGION" \
                        --stack-name "$stack" 2>/dev/null; then
                        echo "INITIATED:$stack"
                    else
                        echo "FAILED:$stack"
                    fi
                ) &
                pids+=($!)
            fi
        fi
    done
    
    # Wait for all deletion initiations
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Wait for stack deletions to complete
    log_message "INFO" "Waiting for tenant stack deletions to complete..."
    
    for stack in $all_tenant_stacks; do
        if [[ -n "$stack" ]]; then
            if aws cloudformation wait stack-delete-complete \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$stack" 2>/dev/null; then
                log_message "INFO" "  ✓ Deleted: $stack"
                DELETED_STACKS+=("$stack")
            else
                local status=$(get_stack_status "$stack")
                if [[ "$status" == "NOT_FOUND" || "$status" == "DELETE_COMPLETE" ]]; then
                    log_message "INFO" "  ✓ Deleted: $stack"
                    DELETED_STACKS+=("$stack")
                else
                    log_error "STACK_DELETE_FAILED" "$stack" "Failed to delete (status: $status)"
                    FAILED_STACKS+=("$stack")
                fi
            fi
        fi
    done
    
    echo ""
    log_message "INFO" "✓ Dynamic tenant stack cleanup complete"
}

# =============================================================================
# CDK PIPELINE STACK CLEANUP
# =============================================================================

# Delete CDK pipeline stacks (serverless-saas-pipeline-lab5, lab6) and CodeCommit repo
# These are CDK-deployed stacks, not part of the nested CloudFormation hierarchy.
# Must be deleted BEFORE CDKToolkit since they reference the CDK execution role.
delete_pipeline_stacks() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 2b: Deleting CDK Pipeline Stacks"
    log_message "INFO" "========================================"
    echo ""

    local any_found=false

    for lab_num in 5 6; do
        local pipeline_stack="serverless-saas-pipeline-lab${lab_num}"

        if ! stack_exists "$pipeline_stack"; then
            log_message "INFO" "  Pipeline stack $pipeline_stack not found (skipping)"
            continue
        fi

        any_found=true
        local status=$(get_stack_status "$pipeline_stack")
        log_message "INFO" "  Found $pipeline_stack (Status: $status)"

        # Empty the pipeline artifacts bucket first (blocks stack deletion if not empty)
        local artifacts_bucket=$(aws s3 ls --profile "$PROFILE" --region "$REGION" 2>/dev/null \
            | grep "${pipeline_stack}.*artifacts" | awk '{print $3}')

        if [[ -n "$artifacts_bucket" ]]; then
            log_message "INFO" "  Emptying pipeline artifacts bucket: $artifacts_bucket"
            _delete_single_bucket "$artifacts_bucket"
        fi

        # Fix CDK role issues if stack is in DELETE_FAILED state
        if [[ "$status" == "DELETE_FAILED" ]]; then
            fix_pipeline_stack_cdk_role "$pipeline_stack"
            fix_delete_failed_pipeline_stack "$pipeline_stack"
        fi

        # Delete the pipeline stack
        log_message "INFO" "  Deleting stack: $pipeline_stack"
        if aws cloudformation delete-stack \
            --profile "$PROFILE" \
            --region "$REGION" \
            --stack-name "$pipeline_stack" 2>/dev/null; then

            log_message "INFO" "  Waiting for $pipeline_stack deletion..."
            if aws cloudformation wait stack-delete-complete \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$pipeline_stack" 2>/dev/null; then
                log_message "INFO" "  ✓ $pipeline_stack deleted successfully"
                DELETED_STACKS+=("$pipeline_stack")
            else
                local final_status=$(get_stack_status "$pipeline_stack")
                if [[ "$final_status" == "NOT_FOUND" || "$final_status" == "DELETE_COMPLETE" ]]; then
                    log_message "INFO" "  ✓ $pipeline_stack deleted successfully"
                    DELETED_STACKS+=("$pipeline_stack")
                else
                    log_message "WARN" "  ⚠ $pipeline_stack deletion may have failed (status: $final_status)"
                    FAILED_STACKS+=("$pipeline_stack")
                fi
            fi
        else
            log_message "WARN" "  ⚠ Failed to initiate deletion of $pipeline_stack"
            FAILED_STACKS+=("$pipeline_stack")
        fi
        echo ""
    done

    if [[ "$any_found" == false ]]; then
        log_message "INFO" "  ✓ No pipeline stacks found"
    fi

    # Delete CodeCommit repository (shared by both pipelines)
    log_message "INFO" "  Checking for CodeCommit repository: aws-serverless-saas-workshop"
    if aws codecommit get-repository \
        --repository-name aws-serverless-saas-workshop \
        --profile "$PROFILE" --region "$REGION" &>/dev/null; then

        log_message "INFO" "  Deleting CodeCommit repository: aws-serverless-saas-workshop"
        if aws codecommit delete-repository \
            --repository-name aws-serverless-saas-workshop \
            --profile "$PROFILE" --region "$REGION" >> "$LOG_FILE" 2>&1; then
            log_message "INFO" "  ✓ CodeCommit repository deleted"
        else
            log_message "WARN" "  ⚠ Failed to delete CodeCommit repository"
        fi
    else
        log_message "INFO" "  ✓ CodeCommit repository not found (already deleted or never created)"
    fi

    echo ""
    log_message "INFO" "✓ Pipeline stack cleanup complete"
}

# =============================================================================
# ORPHANED RESOURCE CLEANUP (Task 5.4)
# =============================================================================

# Delete orphaned Cognito user pools
delete_orphaned_cognito_pools() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 3a: Cleaning Up Orphaned Cognito User Pools"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Searching for orphaned Cognito user pools..."
    
    # Find all user pools — list-user-pools already returns Name, no need for describe-user-pool
    local pool_data=$(aws cognito-idp list-user-pools \
        --profile "$PROFILE" \
        --region "$REGION" \
        --max-results 60 \
        --query "UserPools[?contains(Name, 'lab') || contains(Name, 'serverless-saas') || contains(Name, 'workshop')].{Id:Id,Name:Name}" \
        --output json 2>/dev/null || echo "[]")
    
    local pool_count=$(echo "$pool_data" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    
    if [[ "$pool_count" == "0" ]]; then
        log_message "INFO" "✓ No lab-related Cognito user pools found"
        return 0
    fi
    
    # Display found pools
    log_message "INFO" "Found $pool_count lab-related Cognito user pools:"
    echo "$pool_data" | python3 -c "
import sys, json
pools = json.load(sys.stdin)
for p in pools:
    print(f\"  - {p['Name']} ({p['Id']})\")
" 2>/dev/null
    
    echo ""
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true && "$INTERACTIVE" == true ]]; then
        read -p "Delete all lab-related Cognito user pools? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Skipping Cognito user pool deletion"
            return 0
        fi
    fi
    
    # Delete pools (must delete users and domain first)
    log_message "INFO" "Deleting Cognito user pools..."
    
    echo "$pool_data" | python3 -c "
import sys, json
pools = json.load(sys.stdin)
for p in pools:
    print(f\"{p['Id']}:{p['Name']}\")
" 2>/dev/null | while IFS=: read -r pool_id pool_name; do
        # Step 1: Delete all users in the pool (prevents deletion failures)
        log_message "INFO" "  Cleaning up users in pool: $pool_name ($pool_id)"
        local users=$(aws cognito-idp list-users \
            --profile "$PROFILE" \
            --region "$REGION" \
            --user-pool-id "$pool_id" \
            --query 'Users[].Username' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$users" && "$users" != "None" ]]; then
            for username in $users; do
                aws cognito-idp admin-delete-user \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --user-pool-id "$pool_id" \
                    --username "$username" 2>/dev/null || true
            done
            log_message "INFO" "    ✓ Users deleted from pool"
        fi
        
        # Step 2: Delete the Cognito domain (blocks pool deletion if present)
        local domain=$(aws cognito-idp describe-user-pool \
            --profile "$PROFILE" \
            --region "$REGION" \
            --user-pool-id "$pool_id" \
            --query 'UserPool.Domain' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$domain" && "$domain" != "None" ]]; then
            log_message "INFO" "    Deleting Cognito domain: $domain"
            aws cognito-idp delete-user-pool-domain \
                --profile "$PROFILE" \
                --region "$REGION" \
                --domain "$domain" \
                --user-pool-id "$pool_id" 2>/dev/null || true
        fi
        
        # Step 3: Delete the user pool
        if aws cognito-idp delete-user-pool \
            --profile "$PROFILE" \
            --region "$REGION" \
            --user-pool-id "$pool_id" 2>/dev/null; then
            log_message "INFO" "  ✓ Deleted: $pool_name ($pool_id)"
        else
            log_error "COGNITO_DELETE_FAILED" "$pool_name" "Failed to delete user pool"
        fi
    done
    
    echo ""
    log_message "INFO" "✓ Cognito user pool cleanup complete"
}

# Delete orphaned DynamoDB tables
delete_orphaned_dynamodb_tables() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 3b: Cleaning Up Orphaned DynamoDB Tables"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Searching for orphaned DynamoDB tables..."
    
    # Find all tables
    local tables=$(aws dynamodb list-tables \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "TableNames[]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$tables" ]]; then
        log_message "INFO" "✓ No DynamoDB tables found"
        return 0
    fi
    
    # Filter to only lab-related tables
    local lab_tables=""
    
    for table in $tables; do
        # Check if table name contains lab references
        if [[ "$table" == *"lab"* || "$table" == *"serverless-saas"* || "$table" == *"workshop"* || "$table" == *"stack-"* ]]; then
            lab_tables+="$table "
        fi
    done
    
    if [[ -z "$lab_tables" ]]; then
        log_message "INFO" "✓ No lab-related DynamoDB tables found"
        return 0
    fi
    
    # Display found tables
    log_message "INFO" "Found lab-related DynamoDB tables:"
    for table in $lab_tables; do
        log_message "INFO" "  - $table"
    done
    
    echo ""
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true && "$INTERACTIVE" == true ]]; then
        read -p "Delete all lab-related DynamoDB tables? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Skipping DynamoDB table deletion"
            return 0
        fi
    fi
    
    # Delete tables
    log_message "INFO" "Deleting DynamoDB tables..."
    
    for table in $lab_tables; do
        if aws dynamodb delete-table \
            --profile "$PROFILE" \
            --region "$REGION" \
            --table-name "$table" 2>/dev/null; then
            log_message "INFO" "  ✓ Deleted: $table"
        else
            log_error "DYNAMODB_DELETE_FAILED" "$table" "Failed to delete table"
        fi
    done
    
    echo ""
    log_message "INFO" "✓ DynamoDB table cleanup complete"
}

# Delete orphaned IAM roles
delete_orphaned_iam_roles() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 3c: Cleaning Up Orphaned IAM Roles"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Searching for orphaned IAM roles..."
    
    # Find lab-related roles using server-side JMESPath filtering (avoids fetching ALL roles in the account)
    local lab_roles=$(aws iam list-roles \
        --profile "$PROFILE" \
        --query "Roles[?contains(RoleName, 'lab') || contains(RoleName, 'serverless-saas') || contains(RoleName, 'workshop') || starts_with(RoleName, 'stack-')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$lab_roles" ]]; then
        log_message "INFO" "✓ No lab-related IAM roles found"
        return 0
    fi
    
    # Display found roles
    log_message "INFO" "Found lab-related IAM roles:"
    for role in $lab_roles; do
        log_message "INFO" "  - $role"
    done
    
    echo ""
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true && "$INTERACTIVE" == true ]]; then
        read -p "Delete all lab-related IAM roles? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Skipping IAM role deletion"
            return 0
        fi
    fi
    
    # Delete roles
    log_message "INFO" "Deleting IAM roles..."
    
    for role in $lab_roles; do
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --profile "$PROFILE" \
            --role-name "$role" \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy \
                    --profile "$PROFILE" \
                    --role-name "$role" \
                    --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        done
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --profile "$PROFILE" \
            --role-name "$role" \
            --query "PolicyNames[]" \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $inline_policies; do
            if [[ -n "$policy_name" ]]; then
                aws iam delete-role-policy \
                    --profile "$PROFILE" \
                    --role-name "$role" \
                    --policy-name "$policy_name" 2>/dev/null || true
            fi
        done
        
        # Delete the role
        if aws iam delete-role \
            --profile "$PROFILE" \
            --role-name "$role" 2>/dev/null; then
            log_message "INFO" "  ✓ Deleted: $role"
        else
            log_error "IAM_ROLE_DELETE_FAILED" "$role" "Failed to delete IAM role"
        fi
    done
    
    echo ""
    log_message "INFO" "✓ IAM role cleanup complete"
}

# Delete orphaned CloudWatch log groups
delete_orphaned_log_groups() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 3: Cleaning Up Orphaned CloudWatch Log Groups"
    log_message "INFO" "========================================"
    echo ""
    
    # Find lab-related log groups
    # Patterns to match:
    #   - serverless-saas-lab*  : Most Lambda/API GW log groups (Lab1-Lab7 shared services)
    #   - stack-lab*            : Tenant stack log groups (Lab5/Lab6 tenant stacks)
    #   - stack-pooled*         : Pooled stack log groups
    #   - *-lab5-*              : Lab5 tenant Lambda functions (e.g., get-prod-lab5-{tenantId})
    #   - *-lab6-*              : Lab6 tenant Lambda functions
    #   - *-pooled-lab7         : Lab7 pooled Lambda functions (e.g., create-product-pooled-lab7)
    local log_groups=$(aws logs describe-log-groups \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "logGroups[?contains(logGroupName, 'serverless-saas-lab') || contains(logGroupName, 'stack-lab') || contains(logGroupName, 'stack-pooled') || contains(logGroupName, '-lab5-') || contains(logGroupName, '-lab6-') || contains(logGroupName, '-pooled-lab7')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    # Also check for common orphaned log groups
    local common_orphaned=(
        "/aws/apigateway/welcome"
        "/aws/lambda-insights"
        "/aws-glue/crawlers"
    )
    
    for log_group in "${common_orphaned[@]}"; do
        if aws logs describe-log-groups \
            --profile "$PROFILE" \
            --region "$REGION" \
            --log-group-name-prefix "$log_group" \
            --query "logGroups[?logGroupName=='$log_group'].logGroupName" \
            --output text 2>/dev/null | grep -q "$log_group"; then
            log_groups+=" $log_group"
        fi
    done
    
    # Find API Gateway execution logs
    local apigw_logs=$(aws logs describe-log-groups \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "logGroups[?starts_with(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    log_groups+=" $apigw_logs"
    
    # Remove duplicates and empty entries
    log_groups=$(echo "$log_groups" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    
    if [[ -z "$log_groups" || "$log_groups" == " " ]]; then
        log_message "INFO" "✓ No orphaned CloudWatch log groups found"
        return 0
    fi
    
    log_message "INFO" "Found orphaned log groups:"
    for log_group in $log_groups; do
        log_message "INFO" "  - $log_group"
    done
    echo ""
    
    # Delete log groups
    for log_group in $log_groups; do
        if [[ -n "$log_group" ]]; then
            log_message "DEBUG" "Deleting log group: $log_group"
            if aws logs delete-log-group \
                --profile "$PROFILE" \
                --region "$REGION" \
                --log-group-name "$log_group" 2>/dev/null; then
                log_message "INFO" "  ✓ Deleted: $log_group"
                DELETED_LOG_GROUPS+=("$log_group")
            else
                log_error "LOG_GROUP_DELETE_FAILED" "$log_group" "Failed to delete log group"
            fi
        fi
    done
    
    echo ""
    log_message "INFO" "✓ CloudWatch log group cleanup complete"
}

# Helper: Delete a single S3 bucket, handling versioned objects and delete markers.
# 'aws s3 rb --force' only removes current object versions. Buckets with versioning
# enabled (CloudFormation default) also contain old versions and delete markers that
# must be purged via the list-object-versions / delete-objects API before the bucket
# can be removed.
#
# Strategy:
#   1. Try 'aws s3 rb --force' first (fast path for non-versioned buckets).
#   2. If the bucket still exists, loop through list-object-versions and batch-delete
#      all remaining versions and delete markers.
#   3. Delete the now-empty bucket.
_delete_single_bucket() {
    local bucket="$1"

    # Quick existence check
    if ! aws s3api head-bucket --profile "$PROFILE" --bucket "$bucket" &>/dev/null; then
        log_message "INFO" "  ✓ Bucket already deleted: $bucket"
        DELETED_BUCKETS+=("$bucket")
        # Track CDK bucket deletion to avoid redundant work in later functions
        [[ "$bucket" == cdk-hnb659fds-* ]] && CDK_BUCKET_DELETED=true
        return 0
    fi

    # Fast path — works for non-versioned or empty buckets
    aws s3 rb "s3://$bucket" --force --profile "$PROFILE" >> "$LOG_FILE" 2>&1 || true

    # Re-check: if the bucket is gone we're done
    if ! aws s3api head-bucket --profile "$PROFILE" --bucket "$bucket" &>/dev/null; then
        log_message "INFO" "  ✓ Deleted: $bucket"
        DELETED_BUCKETS+=("$bucket")
        [[ "$bucket" == cdk-hnb659fds-* ]] && CDK_BUCKET_DELETED=true
        return 0
    fi

    # Slow path — purge versioned objects and delete markers in batches of 1000
    # The 'rb --force' above only removes current versions. For versioned buckets,
    # old versions and delete markers remain. We must list and batch-delete them.
    log_message "INFO" "  Bucket has versioned objects, purging (this may take a while)..."
    local round=0
    local max_rounds=500
    while [[ $round -lt $max_rounds ]]; do
        round=$((round + 1))

        # List up to 1000 versions + delete markers.
        # We use --no-paginate to get a single page (up to 1000 keys by default)
        # instead of --max-items which interacts poorly with the JSON structure.
        local raw_json
        raw_json=$(aws s3api list-object-versions \
            --bucket "$bucket" \
            --profile "$PROFILE" \
            --no-paginate \
            --output json 2>/dev/null || echo '{}')

        # Build the delete payload with python. The || true ensures set -e
        # doesn't kill us if python fails on unexpected input.
        local payload
        payload=$(echo "$raw_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('EMPTY')
    sys.exit(0)
objs = []
for v in data.get('Versions', []):
    objs.append({'Key': v['Key'], 'VersionId': v['VersionId']})
for m in data.get('DeleteMarkers', []):
    objs.append({'Key': m['Key'], 'VersionId': m['VersionId']})
if objs:
    # delete-objects accepts max 1000 keys per call
    print(json.dumps({'Objects': objs[:1000], 'Quiet': True}))
else:
    print('EMPTY')
" 2>/dev/null || echo 'EMPTY')

        if [[ "$payload" == "EMPTY" || -z "$payload" ]]; then
            break
        fi

        echo "$payload" > /tmp/_s3_version_delete.json
        aws s3api delete-objects \
            --bucket "$bucket" \
            --profile "$PROFILE" \
            --delete "file:///tmp/_s3_version_delete.json" >> "$LOG_FILE" 2>&1 || true
        echo "    Purged version batch $round (up to 1000 objects per batch)"
    done
    rm -f /tmp/_s3_version_delete.json

    if [[ $round -ge $max_rounds ]]; then
        log_message "WARN" "  Exceeded $max_rounds rounds purging $bucket — possible infinite loop"
    fi

    # Final bucket deletion
    if aws s3api delete-bucket --bucket "$bucket" --profile "$PROFILE" --region "$REGION" 2>/dev/null; then
        log_message "INFO" "  ✓ Deleted: $bucket"
        DELETED_BUCKETS+=("$bucket")
        [[ "$bucket" == cdk-hnb659fds-* ]] && CDK_BUCKET_DELETED=true
    else
        # One more existence check (concurrent deletion)
        if ! aws s3api head-bucket --profile "$PROFILE" --bucket "$bucket" &>/dev/null; then
            log_message "INFO" "  ✓ Bucket deleted (concurrent): $bucket"
            DELETED_BUCKETS+=("$bucket")
            [[ "$bucket" == cdk-hnb659fds-* ]] && CDK_BUCKET_DELETED=true
        else
            log_error "S3_BUCKET_DELETE_FAILED" "$bucket" "Failed after purging versions"
        fi
    fi
}

# Delete orphaned S3 buckets
# Uses _delete_single_bucket helper which handles both versioned and non-versioned buckets
delete_orphaned_s3_buckets() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 4: Cleaning Up Orphaned S3 Buckets"
    log_message "INFO" "========================================"
    echo ""
    
    # Find lab-related S3 buckets using comprehensive patterns
    # Pattern 1: Specific prefixes (serverless-saas-lab, serverless-saas-orchestration, sam-bootstrap-bucket-lab, cdk-hnb659fds)
    # Pattern 2: Lab number patterns (lab1, lab2, lab3, lab4, lab5, lab6, lab7) for any bucket with lab number
    local buckets
    buckets=$(aws s3api list-buckets \
        --profile "$PROFILE" \
        --query "Buckets[?contains(Name, 'serverless-saas-lab') || contains(Name, 'serverless-saas-orchestration') || contains(Name, 'sam-bootstrap-bucket-lab') || contains(Name, 'cdk-hnb659fds') || contains(Name, 'lab1') || contains(Name, 'lab2') || contains(Name, 'lab3') || contains(Name, 'lab4') || contains(Name, 'lab5') || contains(Name, 'lab6') || contains(Name, 'lab7')].Name" \
        --output text 2>&1)
    local list_result=$?
    
    if [[ $list_result -ne 0 ]]; then
        log_message "WARN" "Failed to list S3 buckets: $buckets"
        return 1
    fi
    
    if [[ -z "$buckets" || "$buckets" == "None" ]]; then
        log_message "INFO" "✓ No orphaned S3 buckets found"
        return 0
    fi
    
    log_message "INFO" "Found orphaned S3 buckets:"
    for bucket in $buckets; do
        log_message "INFO" "  - $bucket"
    done
    echo ""
    
    # Delete buckets using _delete_single_bucket helper
    # Handles both versioned and non-versioned buckets reliably
    for bucket in $buckets; do
        if [[ -n "$bucket" && "$bucket" != "None" ]]; then
            log_message "INFO" "Deleting bucket: $bucket"
            _delete_single_bucket "$bucket"
        fi
    done
    
    echo ""
    log_message "INFO" "✓ S3 bucket cleanup complete"
}

# Fix pipeline stacks with missing CDK execution role
# This function creates a temporary CDK execution role if it's missing,
# which allows CloudFormation to delete pipeline stacks that reference it
fix_pipeline_stack_cdk_role() {
    local stack_name=$1
    
    log_message "DEBUG" "Checking if CDK execution role fix is needed for $stack_name..."
    
    # Check if stack exists
    local stack_status=$(get_stack_status "$stack_name")
    
    if [[ "$stack_status" == "NOT_FOUND" ]]; then
        log_message "DEBUG" "  Stack $stack_name does not exist, no fix needed"
        return 0
    fi
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity \
        --profile "$PROFILE" \
        --query Account \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$account_id" ]]; then
        log_message "WARN" "Could not determine AWS account ID"
        return 1
    fi
    
    # CDK execution role name
    local cdk_role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-${REGION}"
    
    # Check if role exists
    if aws iam get-role \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" &>/dev/null; then
        log_message "DEBUG" "  CDK execution role exists, no fix needed"
        return 0
    fi
    
    log_message "INFO" "Creating temporary CDK execution role for stack deletion..."
    
    # Create the role
    if ! aws iam create-role \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "cloudformation.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' &>/dev/null; then
        log_message "WARN" "  Failed to create CDK execution role"
        return 1
    fi
    
    log_message "DEBUG" "  CDK execution role created"
    
    # Attach AdministratorAccess policy
    log_message "DEBUG" "  Attaching AdministratorAccess policy..."
    if ! aws iam attach-role-policy \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess &>/dev/null; then
        log_message "WARN" "  Failed to attach policy"
        return 1
    fi
    
    # Wait for role to propagate
    log_message "DEBUG" "  Waiting 10 seconds for role to propagate..."
    sleep 10
    
    log_message "INFO" "✓ CDK execution role fix completed"
    return 0
}

# Fix DELETE_FAILED pipeline stacks with stuck IAM policies
fix_delete_failed_pipeline_stack() {
    local stack_name=$1
    
    log_message "DEBUG" "Checking if stack $stack_name is in DELETE_FAILED state..."
    
    # Check stack status
    local stack_status=$(get_stack_status "$stack_name")
    
    if [[ "$stack_status" != "DELETE_FAILED" ]]; then
        log_message "DEBUG" "  Stack is not in DELETE_FAILED state (status: $stack_status)"
        return 0
    fi
    
    log_message "INFO" "Stack $stack_name is in DELETE_FAILED state, checking for stuck IAM policies..."
    
    # Get failed resources
    local failed_resources=$(aws cloudformation describe-stack-resources \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$stack_name" \
        --query 'StackResources[?ResourceStatus==`DELETE_FAILED` && ResourceType==`AWS::IAM::Policy`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$failed_resources" ]]; then
        log_message "DEBUG" "  No stuck IAM policies found"
        return 0
    fi
    
    log_message "INFO" "  Found stuck IAM policies, attempting manual cleanup..."
    
    # Try to delete each stuck policy
    for policy_name in $failed_resources; do
        log_message "DEBUG" "    Attempting to delete policy: $policy_name"
        
        # Try to delete the policy (it may already be gone)
        aws iam delete-policy \
            --profile "$PROFILE" \
            --policy-arn "$policy_name" 2>/dev/null || true
    done
    
    log_message "INFO" "  Retrying stack deletion..."
    
    # Retry stack deletion
    if aws cloudformation delete-stack \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$stack_name" 2>/dev/null; then
        
        log_message "INFO" "  Stack deletion retry initiated"
        
        # Wait for deletion
        log_message "DEBUG" "  Waiting for stack deletion to complete..."
        if aws cloudformation wait stack-delete-complete \
            --profile "$PROFILE" \
            --region "$REGION" \
            --stack-name "$stack_name" 2>/dev/null; then
            log_message "INFO" "  ✓ Stack deleted successfully"
            return 0
        else
            local status=$(get_stack_status "$stack_name")
            if [[ "$status" == "NOT_FOUND" || "$status" == "DELETE_COMPLETE" ]]; then
                log_message "INFO" "  ✓ Stack deleted successfully"
                return 0
            fi
            log_message "WARN" "  Stack deletion failed or timed out"
            return 1
        fi
    else
        log_message "WARN" "  Failed to retry stack deletion"
        return 1
    fi
}

# Delete CDKToolkit stack
delete_cdk_toolkit() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 5: Cleaning Up CDKToolkit Stack"
    log_message "INFO" "========================================"
    echo ""
    
    # Check if CDKToolkit stack exists
    if ! stack_exists "CDKToolkit"; then
        log_message "INFO" "✓ CDKToolkit stack not found (already deleted or never created)"
        return 0
    fi
    
    log_message "INFO" "Found CDKToolkit stack - initiating deletion..."

    # Pre-delete: Empty the CDK assets bucket BEFORE deleting the stack.
    # The CDKToolkit stack creates the bucket with DeletionPolicy: Retain,
    # so CloudFormation won't delete it. We empty it first so that
    # delete_cdk_assets_bucket (or a future cdk bootstrap) doesn't choke
    # on an orphaned bucket with versioned objects.
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null || echo "")
    if [[ -n "$account_id" ]]; then
        local cdk_bucket="cdk-hnb659fds-assets-${account_id}-${REGION}"
        if aws s3api head-bucket --bucket "$cdk_bucket" --profile "$PROFILE" &>/dev/null; then
            log_message "INFO" "  Emptying CDK assets bucket before stack deletion: $cdk_bucket"
            _delete_single_bucket "$cdk_bucket"
        fi
    fi
    
    # Delete the CDKToolkit stack
    if aws cloudformation delete-stack \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "CDKToolkit" 2>/dev/null; then
        
        log_message "INFO" "✓ CDKToolkit stack deletion initiated"
        
        # Wait for deletion
        log_message "INFO" "Waiting for CDKToolkit stack deletion to complete (this may take a few minutes)..."
        
        if aws cloudformation wait stack-delete-complete \
            --profile "$PROFILE" \
            --region "$REGION" \
            --stack-name "CDKToolkit" 2>/dev/null; then
            log_message "INFO" "✓ CDKToolkit stack deleted successfully"
            DELETED_STACKS+=("CDKToolkit")
        else
            local status=$(get_stack_status "CDKToolkit")
            if [[ "$status" == "NOT_FOUND" || "$status" == "DELETE_COMPLETE" ]]; then
                log_message "INFO" "✓ CDKToolkit stack deleted successfully"
                DELETED_STACKS+=("CDKToolkit")
            else
                log_error "STACK_DELETE_FAILED" "CDKToolkit" "Failed to delete (status: $status)"
                FAILED_STACKS+=("CDKToolkit")
            fi
        fi
    else
        log_error "STACK_DELETE_FAILED" "CDKToolkit" "Failed to initiate deletion"
        FAILED_STACKS+=("CDKToolkit")
    fi
    
    echo ""
}

# Delete CDK assets bucket (separate from CDKToolkit stack)
delete_cdk_assets_bucket() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 5b: Cleaning Up CDK Assets Bucket"
    log_message "INFO" "========================================"
    echo ""
    
    # Skip if CDK bucket was already deleted by an earlier function
    if [[ "$CDK_BUCKET_DELETED" == "true" ]]; then
        log_message "INFO" "✓ CDK assets bucket already deleted (by earlier cleanup step)"
        return 0
    fi
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity \
        --profile "$PROFILE" \
        --query Account \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$account_id" ]]; then
        log_message "WARN" "Could not determine AWS account ID"
        return 0
    fi
    
    # CDK assets bucket name
    local cdk_assets_bucket="cdk-hnb659fds-assets-${account_id}-${REGION}"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$cdk_assets_bucket" --profile "$PROFILE" &>/dev/null; then
        log_message "INFO" "✓ CDK assets bucket not found (already deleted or never created)"
        return 0
    fi
    
    log_message "INFO" "Found CDK assets bucket: $cdk_assets_bucket"
    log_message "INFO" "Deleting bucket (with version purge if needed)..."
    
    _delete_single_bucket "$cdk_assets_bucket"
    
    echo ""
}

# Clean up CDK execution role (if exists)
cleanup_cdk_execution_role() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 7: Cleaning Up CDK Execution Role"
    log_message "INFO" "========================================"
    echo ""
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity \
        --profile "$PROFILE" \
        --query Account \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$account_id" ]]; then
        log_message "WARN" "Could not determine AWS account ID"
        return 0
    fi
    
    # CDK execution role name
    local cdk_role_name="cdk-hnb659fds-cfn-exec-role-${account_id}-${REGION}"
    
    # Check if role exists
    if ! aws iam get-role \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" &>/dev/null; then
        log_message "INFO" "✓ CDK execution role not found (already deleted or never created)"
        return 0
    fi
    
    log_message "INFO" "Found CDK execution role: $cdk_role_name"
    
    # Detach managed policies
    log_message "DEBUG" "Detaching managed policies..."
    local attached_policies=$(aws iam list-attached-role-policies \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" \
        --query "AttachedPolicies[].PolicyArn" \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in $attached_policies; do
        if [[ -n "$policy_arn" ]]; then
            aws iam detach-role-policy \
                --profile "$PROFILE" \
                --role-name "$cdk_role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        fi
    done
    
    # Delete inline policies
    log_message "DEBUG" "Deleting inline policies..."
    local inline_policies=$(aws iam list-role-policies \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" \
        --query "PolicyNames[]" \
        --output text 2>/dev/null || echo "")
    
    for policy_name in $inline_policies; do
        if [[ -n "$policy_name" ]]; then
            aws iam delete-role-policy \
                --profile "$PROFILE" \
                --role-name "$cdk_role_name" \
                --policy-name "$policy_name" 2>/dev/null || true
        fi
    done
    
    # Delete the role
    if aws iam delete-role \
        --profile "$PROFILE" \
        --role-name "$cdk_role_name" 2>/dev/null; then
        log_message "INFO" "✓ CDK execution role deleted: $cdk_role_name"
    else
        log_error "IAM_ROLE_DELETE_FAILED" "$cdk_role_name" "Failed to delete CDK execution role"
    fi
    
    echo ""
}

# Reset API Gateway account settings
reset_api_gateway_settings() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 9: Resetting API Gateway Account Settings"
    log_message "INFO" "========================================"
    echo ""
    
    # Check if API Gateway has a CloudWatch role configured
    local apigw_role_arn=$(aws apigateway get-account \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'cloudwatchRoleArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$apigw_role_arn" || "$apigw_role_arn" == "None" ]]; then
        log_message "INFO" "✓ No API Gateway CloudWatch role configured"
        return 0
    fi
    
    # Extract role name from ARN
    local role_name=$(echo "$apigw_role_arn" | awk -F'/' '{print $NF}')
    
    # Check if the role still exists
    if aws iam get-role \
        --profile "$PROFILE" \
        --role-name "$role_name" &>/dev/null; then
        log_message "INFO" "API Gateway role still exists in IAM - no reset needed"
        return 0
    fi
    
    log_message "INFO" "API Gateway references deleted role: $apigw_role_arn"
    log_message "INFO" "Resetting API Gateway account settings..."
    
    # Reset the CloudWatch role ARN
    if aws apigateway update-account \
        --profile "$PROFILE" \
        --region "$REGION" \
        --patch-operations op=replace,path=/cloudwatchRoleArn,value='' 2>/dev/null; then
        log_message "INFO" "✓ API Gateway account settings reset successfully"
    else
        log_error "APIGW_RESET_FAILED" "API Gateway" "Failed to reset account settings"
    fi
    
    echo ""
}

# Delete workshop credentials file (security cleanup)
delete_credentials_file() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 10: Deleting Workshop Credentials File"
    log_message "INFO" "========================================"
    echo ""
    
    local credentials_file="$ORCHESTRATION_DIR/workshop-credentials.txt"
    
    if [[ -f "$credentials_file" ]]; then
        log_message "INFO" "Found credentials file: $credentials_file"
        
        if rm -f "$credentials_file" 2>/dev/null; then
            log_message "INFO" "✓ Credentials file deleted successfully"
        else
            log_error "FILE_DELETE_FAILED" "workshop-credentials.txt" "Failed to delete credentials file"
        fi
    else
        log_message "INFO" "✓ No credentials file found (already deleted or never created)"
    fi
    
    echo ""
}

# Clean up generated frontend environment files
# These files are created by deployment scripts but not tracked in git
cleanup_frontend_environment_files() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 11: Cleaning Up Generated Frontend Environment Files"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Searching for generated environment files..."
    
    local files_deleted=0
    local files_failed=0
    
    # Define all lab client directories that may have generated environment files
    local client_dirs=(
        "$WORKSHOP_ROOT/Lab1/client"
        "$WORKSHOP_ROOT/Lab2/client/Admin"
        "$WORKSHOP_ROOT/Lab2/client/Landing"
        "$WORKSHOP_ROOT/Lab3/client/Admin"
        "$WORKSHOP_ROOT/Lab3/client/Landing"
        "$WORKSHOP_ROOT/Lab3/client/Application"
        "$WORKSHOP_ROOT/Lab4/client/Admin"
        "$WORKSHOP_ROOT/Lab4/client/Landing"
        "$WORKSHOP_ROOT/Lab4/client/Application"
        "$WORKSHOP_ROOT/Lab5/client/Admin"
        "$WORKSHOP_ROOT/Lab5/client/Landing"
        "$WORKSHOP_ROOT/Lab5/client/Application"
        "$WORKSHOP_ROOT/Lab6/client/Admin"
        "$WORKSHOP_ROOT/Lab6/client/Landing"
        "$WORKSHOP_ROOT/Lab6/client/Application"
    )
    
    # Files to delete in each client directory
    local files_to_delete=(
        "src/environments/environment.ts"
        "src/environments/environment.prod.ts"
        "src/aws-exports.ts"
    )
    
    for client_dir in "${client_dirs[@]}"; do
        if [[ -d "$client_dir" ]]; then
            for file in "${files_to_delete[@]}"; do
                local full_path="$client_dir/$file"
                if [[ -f "$full_path" ]]; then
                    if rm -f "$full_path" 2>/dev/null; then
                        log_message "DEBUG" "  ✓ Deleted: $full_path"
                        ((files_deleted++))
                    else
                        log_message "WARN" "  ✗ Failed to delete: $full_path"
                        ((files_failed++))
                    fi
                fi
            done
            
            # Also remove the environments directory if it's empty
            local env_dir="$client_dir/src/environments"
            if [[ -d "$env_dir" ]]; then
                # Check if directory is empty
                if [[ -z "$(ls -A "$env_dir" 2>/dev/null)" ]]; then
                    if rmdir "$env_dir" 2>/dev/null; then
                        log_message "DEBUG" "  ✓ Removed empty directory: $env_dir"
                    fi
                fi
            fi
        fi
    done
    
    if [[ $files_deleted -gt 0 ]]; then
        log_message "INFO" "✓ Deleted $files_deleted generated environment file(s)"
    else
        log_message "INFO" "✓ No generated environment files found (already cleaned or never created)"
    fi
    
    if [[ $files_failed -gt 0 ]]; then
        log_message "WARN" "⚠ Failed to delete $files_failed file(s)"
    fi
    
    echo ""
}

# Delete account-level IAM roles created by the workshop
# These roles are shared across labs and should only be deleted when ALL labs are cleaned up
delete_account_level_iam_roles() {
    log_message "INFO" "========================================"
    log_message "INFO" "Step 8: Cleaning Up Account-Level IAM Roles"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Checking for workshop-created account-level IAM roles..."
    
    # Define account-level roles created by the workshop
    # These roles are shared across labs and should only be deleted when ALL labs are cleaned up
    local account_level_roles=(
        "apigateway-cloudwatch-publish-role"
    )
    
    # Track if any roles were found
    local roles_found=false
    
    for role_name in "${account_level_roles[@]}"; do
        # Check if role exists
        if aws iam get-role \
            --profile "$PROFILE" \
            --role-name "$role_name" &>/dev/null; then
            
            roles_found=true
            log_message "INFO" "Found account-level role: $role_name"
            
            # Detach managed policies
            log_message "DEBUG" "  Detaching managed policies..."
            local attached_policies=$(aws iam list-attached-role-policies \
                --profile "$PROFILE" \
                --role-name "$role_name" \
                --query "AttachedPolicies[].PolicyArn" \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                if [[ -n "$policy_arn" ]]; then
                    log_message "DEBUG" "    Detaching policy: $policy_arn"
                    aws iam detach-role-policy \
                        --profile "$PROFILE" \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" 2>/dev/null || true
                fi
            done
            
            # Delete inline policies
            log_message "DEBUG" "  Deleting inline policies..."
            local inline_policies=$(aws iam list-role-policies \
                --profile "$PROFILE" \
                --role-name "$role_name" \
                --query "PolicyNames[]" \
                --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                if [[ -n "$policy_name" ]]; then
                    log_message "DEBUG" "    Deleting inline policy: $policy_name"
                    aws iam delete-role-policy \
                        --profile "$PROFILE" \
                        --role-name "$role_name" \
                        --policy-name "$policy_name" 2>/dev/null || true
                fi
            done
            
            # Delete the role
            log_message "INFO" "  Deleting role: $role_name"
            if aws iam delete-role \
                --profile "$PROFILE" \
                --role-name "$role_name" 2>/dev/null; then
                log_message "INFO" "  ✓ Role deleted: $role_name"
            else
                log_error "IAM_ROLE_DELETE_FAILED" "$role_name" "Failed to delete account-level IAM role"
            fi
        fi
    done
    
    if [[ "$roles_found" == false ]]; then
        log_message "INFO" "✓ No account-level roles found (already deleted or never created)"
    fi
    
    echo ""
    log_message "INFO" "Account-level IAM roles cleanup complete"
    echo ""
    
    # IMPORTANT: Service-linked roles like AWSServiceRoleForAPIGateway are NOT deleted
    # These are AWS-managed roles and should never be deleted by cleanup scripts
}

# =============================================================================
# ERROR HANDLING AND REPORTING (Task 5.5)
# =============================================================================

# Verify complete cleanup
verify_cleanup() {
    log_message "INFO" "========================================"
    log_message "INFO" "Final Verification - Checking for Remaining Resources"
    log_message "INFO" "========================================"
    echo ""
    
    local remaining_resources=0
    
    # Check for remaining CloudFormation stacks
    log_message "DEBUG" "Checking for remaining CloudFormation stacks..."
    local remaining_stacks=$(aws cloudformation list-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, 'serverless-saas-lab') || contains(StackName, 'serverless-saas-orchestration') || contains(StackName, 'stack-') || StackName=='$STACK_NAME' || contains(StackName, 'lab1') || contains(StackName, 'lab2') || contains(StackName, 'lab3') || contains(StackName, 'lab4') || contains(StackName, 'lab5') || contains(StackName, 'lab6') || contains(StackName, 'lab7')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_stacks" ]]; then
        log_message "WARN" "⚠️  Found remaining stacks:"
        for stack in $remaining_stacks; do
            log_message "WARN" "    - $stack"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining CloudFormation stacks"
    fi
    
    # Check for remaining S3 buckets (comprehensive patterns)
    log_message "DEBUG" "Checking for remaining S3 buckets..."
    local remaining_buckets=$(aws s3api list-buckets \
        --profile "$PROFILE" \
        --query "Buckets[?contains(Name, 'serverless-saas-lab') || contains(Name, 'serverless-saas-orchestration') || contains(Name, 'sam-bootstrap-bucket-lab') || contains(Name, 'cdk-hnb659fds') || contains(Name, 'lab1') || contains(Name, 'lab2') || contains(Name, 'lab3') || contains(Name, 'lab4') || contains(Name, 'lab5') || contains(Name, 'lab6') || contains(Name, 'lab7')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_buckets" ]]; then
        log_message "WARN" "⚠️  Found remaining S3 buckets:"
        for bucket in $remaining_buckets; do
            log_message "WARN" "    - $bucket"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining S3 buckets"
    fi
    
    # Check for remaining CloudWatch log groups
    log_message "DEBUG" "Checking for remaining CloudWatch log groups..."
    local remaining_logs=$(aws logs describe-log-groups \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "logGroups[?contains(logGroupName, 'serverless-saas-lab') || contains(logGroupName, 'serverless-saas-orchestration') || contains(logGroupName, 'stack-lab') || contains(logGroupName, 'stack-pooled')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_logs" ]]; then
        log_message "WARN" "⚠️  Found remaining CloudWatch log groups:"
        for log_group in $remaining_logs; do
            log_message "WARN" "    - $log_group"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining CloudWatch log groups"
    fi
    
    # Check for remaining DynamoDB tables
    log_message "DEBUG" "Checking for remaining DynamoDB tables..."
    local remaining_tables=$(aws dynamodb list-tables \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "TableNames[?contains(@, 'lab') || contains(@, 'serverless-saas')]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_tables" ]]; then
        log_message "WARN" "⚠️  Found remaining DynamoDB tables:"
        for table in $remaining_tables; do
            log_message "WARN" "    - $table"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining DynamoDB tables"
    fi
    
    # Check for remaining Cognito User Pools
    log_message "DEBUG" "Checking for remaining Cognito User Pools..."
    local remaining_pools=$(aws cognito-idp list-user-pools \
        --profile "$PROFILE" \
        --region "$REGION" \
        --max-results 60 \
        --query "UserPools[?contains(Name, 'lab') || contains(Name, 'serverless-saas')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_pools" ]]; then
        log_message "WARN" "⚠️  Found remaining Cognito User Pools:"
        for pool in $remaining_pools; do
            log_message "WARN" "    - $pool"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining Cognito User Pools"
    fi
    
    # Check for remaining lab-specific IAM Roles
    log_message "DEBUG" "Checking for remaining lab-specific IAM Roles..."
    local remaining_roles=$(aws iam list-roles \
        --profile "$PROFILE" \
        --query "Roles[?contains(RoleName, 'serverless-saas-lab') || contains(RoleName, 'stack-lab')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_roles" ]]; then
        log_message "WARN" "⚠️  Found remaining lab-specific IAM Roles:"
        for role in $remaining_roles; do
            log_message "WARN" "    - $role"
        done
        remaining_resources=$((remaining_resources + 1))
    else
        log_message "INFO" "✓ No remaining lab-specific IAM Roles"
    fi
    
    # Check for remaining account-level IAM Roles created by workshop
    log_message "DEBUG" "Checking for remaining account-level IAM Roles..."
    local account_level_roles=("apigateway-cloudwatch-publish-role")
    local found_account_roles=false
    
    for role_name in "${account_level_roles[@]}"; do
        if aws iam get-role \
            --profile "$PROFILE" \
            --role-name "$role_name" &>/dev/null; then
            if [[ "$found_account_roles" == false ]]; then
                log_message "WARN" "⚠️  Found remaining account-level IAM Roles:"
                found_account_roles=true
            fi
            log_message "WARN" "    - $role_name"
            remaining_resources=$((remaining_resources + 1))
        fi
    done
    
    if [[ "$found_account_roles" == false ]]; then
        log_message "INFO" "✓ No remaining account-level IAM Roles"
    fi
    
    # Check API Gateway account settings for orphaned role ARN references
    log_message "DEBUG" "Checking API Gateway account settings..."
    local apigw_role_arn=$(aws apigateway get-account \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'cloudwatchRoleArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$apigw_role_arn" && "$apigw_role_arn" != "None" ]]; then
        # Extract role name from ARN
        local role_name=$(echo "$apigw_role_arn" | awk -F'/' '{print $NF}')
        
        # Check if the role still exists in IAM
        if ! aws iam get-role \
            --profile "$PROFILE" \
            --role-name "$role_name" &>/dev/null; then
            log_message "WARN" "⚠️  API Gateway references deleted role: $apigw_role_arn"
            log_message "WARN" "     This is an orphaned reference - the role no longer exists in IAM"
            remaining_resources=$((remaining_resources + 1))
        else
            log_message "INFO" "✓ API Gateway role exists and is valid"
        fi
    else
        log_message "INFO" "✓ API Gateway account settings properly reset (no role ARN configured)"
    fi
    
    echo ""
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_message "INFO" "✓ All workshop resources have been completely cleaned up!"
        return 0
    else
        log_message "WARN" "⚠️  Some resources may still exist. Please review the list above."
        return 1
    fi
}

# Print cleanup summary
print_summary() {
    local duration=$1
    
    echo ""
    log_message "INFO" "========================================"
    log_message "INFO" "Cleanup Summary"
    log_message "INFO" "========================================"
    echo ""
    
    # Deleted stacks
    if [[ ${#DELETED_STACKS[@]} -gt 0 ]]; then
        log_message "INFO" "Deleted Stacks (${#DELETED_STACKS[@]}):"
        for stack in "${DELETED_STACKS[@]}"; do
            log_message "INFO" "  ✓ $stack"
        done
        echo ""
    fi
    
    # Failed stacks
    if [[ ${#FAILED_STACKS[@]} -gt 0 ]]; then
        log_message "ERROR" "Failed Stacks (${#FAILED_STACKS[@]}):"
        for stack in "${FAILED_STACKS[@]}"; do
            log_message "ERROR" "  ✗ $stack"
        done
        echo ""
    fi
    
    # Deleted buckets
    if [[ ${#DELETED_BUCKETS[@]} -gt 0 ]]; then
        log_message "INFO" "Deleted S3 Buckets (${#DELETED_BUCKETS[@]}):"
        for bucket in "${DELETED_BUCKETS[@]}"; do
            log_message "INFO" "  ✓ $bucket"
        done
        echo ""
    fi
    
    # Deleted log groups
    if [[ ${#DELETED_LOG_GROUPS[@]} -gt 0 ]]; then
        log_message "INFO" "Deleted CloudWatch Log Groups (${#DELETED_LOG_GROUPS[@]}):"
        for log_group in "${DELETED_LOG_GROUPS[@]}"; do
            log_message "INFO" "  ✓ $log_group"
        done
        echo ""
    fi
    
    # Errors
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        log_message "ERROR" "Errors Encountered (${#ERRORS[@]}):"
        for error in "${ERRORS[@]}"; do
            log_message "ERROR" "  - $error"
        done
        echo ""
    fi
    
    # Duration and log file
    log_message "INFO" "Duration: ${duration} seconds"
    log_message "INFO" "Log file: $LOG_FILE"
    echo ""
    
    # Final status
    if [[ ${#FAILED_STACKS[@]} -gt 0 || ${#ERRORS[@]} -gt 0 ]]; then
        log_message "WARN" "Cleanup completed with some errors. Check log file for details."
        return 1
    else
        log_message "INFO" "✓ Cleanup completed successfully!"
        return 0
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Redirect output to log file and console
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    # Print header
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "AWS Serverless SaaS Workshop"
    print_message "$BLUE" "Orchestration Cleanup Script"
    print_message "$BLUE" "========================================"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Display configuration
    log_message "INFO" "Configuration:"
    log_message "INFO" "  Stack Name: $STACK_NAME"
    log_message "INFO" "  AWS Profile: $PROFILE"
    log_message "INFO" "  Region: $REGION"
    log_message "INFO" "  Auto-confirm: $AUTO_CONFIRM"
    log_message "INFO" "  Interactive: $INTERACTIVE"
    echo ""
    
    # Confirmation prompt
    if [[ "$AUTO_CONFIRM" != true ]]; then
        print_message "$RED" "WARNING: This will delete ALL resources from the orchestration deployment."
        print_message "$RED" "This includes:"
        print_message "$RED" "  - Main orchestration stack and all nested stacks"
        print_message "$RED" "  - Dynamic tenant stacks (stack-*-lab5, stack-*-lab6, stack-pooled-lab7)"
        print_message "$RED" "  - CDK pipeline stacks (serverless-saas-pipeline-lab5, lab6)"
        print_message "$RED" "  - CodeCommit repository (aws-serverless-saas-workshop)"
        print_message "$RED" "  - Orphaned Cognito user pools"
        print_message "$RED" "  - Orphaned DynamoDB tables"
        print_message "$RED" "  - Orphaned IAM roles"
        print_message "$RED" "  - Orphaned CloudWatch log groups"
        print_message "$RED" "  - Orphaned S3 buckets"
        print_message "$RED" "  - CDKToolkit stack"
        print_message "$RED" "  - Generated frontend environment files"
        print_message "$RED" ""
        print_message "$RED" "This action cannot be undone."
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        echo ""
        if [[ "$confirm" != "yes" ]]; then
            log_message "WARN" "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Record start time
    local start_time=$(date +%s)
    
    # Execute cleanup steps
    # Step 1: Delete dynamic tenant stacks FIRST (they import exports from nested stacks)
    # These must be deleted before the main stack, otherwise CloudFormation refuses to
    # delete nested stacks whose exports are still referenced by tenant stacks
    # (e.g., stack-lab6-pooled references Serverless-SaaS-AuthorizerExecutionRoleArn-lab6)
    delete_dynamic_tenant_stacks
    
    # Step 1b: Delete CDK pipeline stacks and CodeCommit repo
    delete_pipeline_stacks
    
    # Step 2: Delete main orchestration stack (with automatic retry)
    delete_main_stack_with_retry
    
    # Step 3a: Delete orphaned Cognito user pools
    delete_orphaned_cognito_pools
    
    # Step 3b: Delete orphaned DynamoDB tables
    delete_orphaned_dynamodb_tables
    
    # Step 3c: Delete orphaned IAM roles
    delete_orphaned_iam_roles
    
    # Step 4: Delete orphaned CloudWatch log groups
    delete_orphaned_log_groups
    
    # Step 5: Delete orphaned S3 buckets (SAFE - CloudFront already deleted)
    delete_orphaned_s3_buckets
    
    # Step 6: Delete CDKToolkit stack
    delete_cdk_toolkit
    
    # Step 6b: Delete CDK assets bucket (separate from CDKToolkit stack)
    delete_cdk_assets_bucket
    
    # Step 7: Clean up CDK execution role
    cleanup_cdk_execution_role
    
    # Step 8: Delete account-level IAM roles (AFTER all labs are cleaned)
    delete_account_level_iam_roles
    
    # Step 9: Reset API Gateway account settings
    reset_api_gateway_settings
    
    # Step 10: Delete workshop credentials file (security cleanup)
    delete_credentials_file
    
    # Step 11: Clean up generated frontend environment files
    cleanup_frontend_environment_files
    
    # Verify cleanup
    verify_cleanup
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Print summary
    print_summary "$duration"
    
    # Exit with appropriate code
    if [[ ${#FAILED_STACKS[@]} -gt 0 || ${#ERRORS[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
