#!/bin/bash

# Stack Deletion Verification Module
# 
# This module provides helper functions for reliably deleting CloudFormation stacks
# with proper verification, status polling, and error handling.
#
# Key Features:
# - Verifies stack deletion actually starts (DELETE_IN_PROGRESS)
# - Polls stack status every 30 seconds until deletion completes
# - Handles timeouts appropriately (30 min standard, 45 min CloudFront)
# - Verifies stack no longer exists before proceeding
# - Provides detailed logging of deletion progress
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/stack-deletion.sh"
#   delete_stack_verified "my-stack-name" "$PROFILE_ARG"
#   wait_for_stack_deletion "my-stack-name" 45 "$PROFILE_ARG"
#   verify_stack_deleted "my-stack-name" "$PROFILE_ARG"

# Color codes for output (if not already defined)
if [[ -z "$RED" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Default AWS region (if not already set)
: ${AWS_REGION:="us-east-1"}

# Global variables for error tracking
# Note: Using declare without -g for bash 3.2 compatibility (macOS default)
LAST_COMMAND=""
LAST_ERROR_OUTPUT=""
LAST_ERROR_CODE=0

# Operation tracking for exit summary
# Note: Using declare -a without -g for bash 3.2 compatibility
declare -a OPERATIONS_LOG=()

##############################################################################
# log_command
#
# Logs the full AWS CLI command before execution.
#
# This function logs commands to both stdout and the operations log for
# later summary reporting. It helps with debugging by showing exactly what
# commands were executed.
#
# Arguments:
#   $@ - Full command with all arguments
#
# Example:
#   log_command aws cloudformation delete-stack --stack-name my-stack
##############################################################################
log_command() {
    local command="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    LAST_COMMAND="$command"
    echo -e "${BLUE}[${timestamp}] Executing: ${command}${NC}"
    
    # Add to operations log
    OPERATIONS_LOG+=("${timestamp} | COMMAND | ${command}")
}

##############################################################################
# log_error
#
# Logs error details with context information.
#
# This function captures error output, error codes, and provides context
# about what operation failed. It also fetches CloudFormation stack events
# if the error is related to stack operations.
#
# Arguments:
#   $1 - Operation description (e.g., "delete_stack", "wait_for_deletion")
#   $2 - Error message or output
#   $3 - Stack name (optional, for CloudFormation-specific errors)
#   $4 - AWS CLI profile argument (optional)
#
# Example:
#   log_error "delete_stack" "$error_output" "my-stack" "$PROFILE_ARG"
##############################################################################
log_error() {
    local operation="$1"
    local error_message="$2"
    local stack_name="${3:-}"
    local profile_arg="${4:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    LAST_ERROR_OUTPUT="$error_message"
    
    echo -e "${RED}[${timestamp}] ERROR in ${operation}${NC}" >&2
    echo -e "${RED}  Command: ${LAST_COMMAND}${NC}" >&2
    echo -e "${RED}  Error: ${error_message}${NC}" >&2
    
    # Add to operations log
    OPERATIONS_LOG+=("${timestamp} | ERROR | ${operation} | ${error_message}")
    
    # If stack name provided, fetch and log stack events
    if [[ -n "$stack_name" ]]; then
        log_stack_events "$stack_name" "$profile_arg"
    fi
}

##############################################################################
# log_stack_events
#
# Logs CloudFormation stack events, particularly focusing on failures.
#
# This function fetches recent stack events and displays them in a table
# format. It's particularly useful for diagnosing why a stack operation failed.
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - AWS CLI profile argument (optional)
#
# Example:
#   log_stack_events "my-stack" "$PROFILE_ARG"
##############################################################################
log_stack_events() {
    local stack_name="$1"
    local profile_arg="${2:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${YELLOW}[${timestamp}] Fetching CloudFormation stack events for: ${stack_name}${NC}" >&2
    
    # Fetch recent stack events (last 20 events)
    local events_output
    events_output=$(aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --max-items 20 \
        --query 'StackEvents[].[Timestamp,LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]' \
        --output table \
        $profile_arg 2>&1)
    
    local events_exit_code=$?
    
    if [ $events_exit_code -eq 0 ]; then
        echo -e "${YELLOW}Recent stack events:${NC}" >&2
        echo "$events_output" >&2
        
        # Add to operations log
        OPERATIONS_LOG+=("${timestamp} | STACK_EVENTS | ${stack_name} | Retrieved ${events_exit_code}")
    else
        echo -e "${RED}Failed to fetch stack events: ${events_output}${NC}" >&2
        OPERATIONS_LOG+=("${timestamp} | STACK_EVENTS | ${stack_name} | Failed to retrieve")
    fi
    
    # Also try to get just the failed events
    local failed_events
    failed_events=$(aws cloudformation describe-stack-events \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --max-items 10 \
        --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[Timestamp,LogicalResourceId,ResourceStatusReason]' \
        --output table \
        $profile_arg 2>/dev/null)
    
    if [[ -n "$failed_events" ]] && [[ "$failed_events" != *"None"* ]]; then
        echo -e "${RED}Failed resources:${NC}" >&2
        echo "$failed_events" >&2
    fi
}

##############################################################################
# log_operation_result
#
# Logs the result of an operation (success or failure).
#
# This function provides consistent logging for operation outcomes and
# adds entries to the operations log for summary reporting.
#
# Arguments:
#   $1 - Operation name
#   $2 - Result status ("SUCCESS" or "FAILURE")
#   $3 - Additional details (optional)
#
# Example:
#   log_operation_result "delete_stack" "SUCCESS" "Stack deleted in 15m 30s"
##############################################################################
log_operation_result() {
    local operation="$1"
    local status="$2"
    local details="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "${GREEN}[${timestamp}] ${operation}: SUCCESS${NC}"
        if [[ -n "$details" ]]; then
            echo -e "${GREEN}  ${details}${NC}"
        fi
    else
        echo -e "${RED}[${timestamp}] ${operation}: FAILURE${NC}" >&2
        if [[ -n "$details" ]]; then
            echo -e "${RED}  ${details}${NC}" >&2
        fi
    fi
    
    # Add to operations log
    OPERATIONS_LOG+=("${timestamp} | RESULT | ${operation} | ${status} | ${details}")
}

##############################################################################
# log_exit_summary
#
# Logs a summary of all operations performed during script execution.
#
# This function should be called before script exit to provide a complete
# overview of what was attempted, what succeeded, and what failed.
#
# Arguments:
#   $1 - Exit code (0 for success, non-zero for failure)
#
# Example:
#   log_exit_summary 0
#   exit 0
##############################################################################
log_exit_summary() {
    local exit_code="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    OPERATION SUMMARY                       ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${#OPERATIONS_LOG[@]} -eq 0 ]; then
        echo -e "${YELLOW}No operations recorded${NC}"
    else
        # Count successes and failures
        local success_count=0
        local failure_count=0
        local command_count=0
        
        for entry in "${OPERATIONS_LOG[@]}"; do
            if [[ "$entry" == *"| RESULT | "* ]]; then
                if [[ "$entry" == *"| SUCCESS |"* ]]; then
                    success_count=$((success_count + 1))
                else
                    failure_count=$((failure_count + 1))
                fi
            elif [[ "$entry" == *"| COMMAND |"* ]]; then
                command_count=$((command_count + 1))
            fi
        done
        
        echo -e "${BLUE}Total Commands Executed: ${command_count}${NC}"
        echo -e "${GREEN}Successful Operations: ${success_count}${NC}"
        echo -e "${RED}Failed Operations: ${failure_count}${NC}"
        echo ""
        
        # Display recent operations (last 10)
        echo -e "${BLUE}Recent Operations:${NC}"
        local start_index=$((${#OPERATIONS_LOG[@]} - 10))
        if [ $start_index -lt 0 ]; then
            start_index=0
        fi
        
        for ((i=start_index; i<${#OPERATIONS_LOG[@]}; i++)); do
            local entry="${OPERATIONS_LOG[$i]}"
            if [[ "$entry" == *"| ERROR |"* ]]; then
                echo -e "${RED}  ${entry}${NC}"
            elif [[ "$entry" == *"| SUCCESS |"* ]]; then
                echo -e "${GREEN}  ${entry}${NC}"
            else
                echo -e "${YELLOW}  ${entry}${NC}"
            fi
        done
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}Script completed successfully (exit code: 0)${NC}"
    elif [ $exit_code -eq 2 ]; then
        echo -e "${YELLOW}Script timed out (exit code: 2)${NC}"
    elif [ $exit_code -eq 3 ]; then
        echo -e "${RED}Orphaned resources detected (exit code: 3)${NC}"
    else
        echo -e "${RED}Script failed (exit code: ${exit_code})${NC}"
    fi
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

##############################################################################
# delete_stack_verified
#
# Initiates CloudFormation stack deletion and verifies it started successfully.
# 
# This function:
# 1. Initiates stack deletion via AWS CLI
# 2. Waits 5 seconds for AWS to process the deletion request
# 3. Verifies the stack entered DELETE_IN_PROGRESS state
# 4. Retries once if the stack didn't enter deletion state
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - AWS CLI profile argument (e.g., "--profile myprofile" or empty string)
#
# Returns:
#   0 - Stack deletion initiated successfully (DELETE_IN_PROGRESS confirmed)
#   1 - Stack deletion failed to start after retry
#
# Example:
#   if delete_stack_verified "my-stack" "$PROFILE_ARG"; then
#       echo "Stack deletion started"
#   else
#       echo "Failed to start stack deletion"
#       exit 1
#   fi
##############################################################################
delete_stack_verified() {
    local stack_name="$1"
    local profile_arg="$2"
    local max_retries=1
    local retry_count=0
    
    if [[ -z "$stack_name" ]]; then
        log_error "delete_stack_verified" "Stack name is required"
        return 1
    fi
    
    echo -e "${YELLOW}  Initiating deletion of stack: $stack_name${NC}"
    
    # Log the command before execution
    log_command aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION" $profile_arg
    
    # Initiate stack deletion and capture output
    local delete_output
    delete_output=$(aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        $profile_arg 2>&1)
    local delete_exit_code=$?
    
    if [ $delete_exit_code -ne 0 ]; then
        log_error "delete_stack_verified" "$delete_output" "$stack_name" "$profile_arg"
        log_operation_result "delete_stack_verified:$stack_name" "FAILURE" "Failed to initiate deletion"
        return 1
    fi
    
    # Wait for AWS to process the deletion request
    echo -e "${YELLOW}  Waiting 5 seconds for deletion to start...${NC}"
    sleep 5
    
    # Verify deletion started (with retry)
    while [ $retry_count -le $max_retries ]; do
        # Log the status check command
        log_command aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" --query 'Stacks[0].StackStatus' $profile_arg
        
        # Query stack status
        local stack_status
        local status_output
        status_output=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            $profile_arg 2>&1)
        local status_exit_code=$?
        
        if [ $status_exit_code -ne 0 ]; then
            # Stack doesn't exist (which is good - it was deleted)
            stack_status="DOES_NOT_EXIST"
        else
            stack_status="$status_output"
        fi
        
        # Check if deletion started
        if [[ "$stack_status" == "DELETE_IN_PROGRESS" ]]; then
            echo -e "${GREEN}✓ Stack deletion started successfully (DELETE_IN_PROGRESS)${NC}"
            log_operation_result "delete_stack_verified:$stack_name" "SUCCESS" "DELETE_IN_PROGRESS confirmed"
            return 0
        elif [[ "$stack_status" == "DOES_NOT_EXIST" ]]; then
            echo -e "${GREEN}✓ Stack already deleted${NC}"
            log_operation_result "delete_stack_verified:$stack_name" "SUCCESS" "Stack already deleted"
            return 0
        fi
        
        # If not in deletion state and we have retries left
        if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW}⚠ Stack status is $stack_status, retrying in 5 seconds...${NC}"
            retry_count=$((retry_count + 1))
            sleep 5
        else
            log_error "delete_stack_verified" "Stack failed to enter DELETE_IN_PROGRESS state. Current status: $stack_status" "$stack_name" "$profile_arg"
            log_operation_result "delete_stack_verified:$stack_name" "FAILURE" "Status: $stack_status"
            return 1
        fi
    done
    
    return 1
}

##############################################################################
# log_manual_cleanup_instructions
#
# Provides manual cleanup instructions when automated cleanup times out.
#
# This function generates specific AWS CLI commands that can be used to
# manually clean up orphaned resources when stack deletion times out.
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - AWS CLI profile argument (optional)
#
# Example:
#   log_manual_cleanup_instructions "my-stack" "$PROFILE_ARG"
##############################################################################
log_manual_cleanup_instructions() {
    local stack_name="$1"
    local profile_arg="${2:-}"
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}           MANUAL CLEANUP INSTRUCTIONS                      ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}The stack deletion timed out but may still be in progress.${NC}"
    echo -e "${YELLOW}You can monitor the stack status and manually clean up if needed.${NC}"
    echo ""
    echo -e "${BLUE}1. Check current stack status:${NC}"
    echo -e "   aws cloudformation describe-stacks \\"
    echo -e "     --stack-name \"$stack_name\" \\"
    echo -e "     --region \"$AWS_REGION\" \\"
    echo -e "     --query 'Stacks[0].StackStatus' \\"
    echo -e "     --output text $profile_arg"
    echo ""
    echo -e "${BLUE}2. View stack events to see what's happening:${NC}"
    echo -e "   aws cloudformation describe-stack-events \\"
    echo -e "     --stack-name \"$stack_name\" \\"
    echo -e "     --region \"$AWS_REGION\" \\"
    echo -e "     --max-items 20 $profile_arg"
    echo ""
    echo -e "${BLUE}3. If stack is stuck, try deleting again:${NC}"
    echo -e "   aws cloudformation delete-stack \\"
    echo -e "     --stack-name \"$stack_name\" \\"
    echo -e "     --region \"$AWS_REGION\" $profile_arg"
    echo ""
    echo -e "${BLUE}4. List resources still in the stack:${NC}"
    echo -e "   aws cloudformation list-stack-resources \\"
    echo -e "     --stack-name \"$stack_name\" \\"
    echo -e "     --region \"$AWS_REGION\" $profile_arg"
    echo ""
    echo -e "${BLUE}5. If CloudFront distribution is blocking deletion:${NC}"
    echo -e "   # List CloudFront distributions"
    echo -e "   aws cloudfront list-distributions \\"
    echo -e "     --query 'DistributionList.Items[*].[Id,Status,DomainName]' \\"
    echo -e "     --output table $profile_arg"
    echo ""
    echo -e "   # Disable a distribution (required before deletion)"
    echo -e "   aws cloudfront get-distribution-config \\"
    echo -e "     --id <DISTRIBUTION_ID> $profile_arg > dist-config.json"
    echo -e "   # Edit dist-config.json: set Enabled to false"
    echo -e "   aws cloudfront update-distribution \\"
    echo -e "     --id <DISTRIBUTION_ID> \\"
    echo -e "     --if-match <ETAG_FROM_GET> \\"
    echo -e "     --distribution-config file://dist-config.json $profile_arg"
    echo ""
    echo -e "${BLUE}6. Check AWS Console for visual stack status:${NC}"
    echo -e "   https://console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

##############################################################################
# wait_for_stack_deletion
#
# Waits for CloudFormation stack deletion to complete with status polling.
#
# This function:
# 1. Polls stack status every 30 seconds
# 2. Logs status changes and elapsed time
# 3. Detects timeout conditions
# 4. Handles DELETE_FAILED status
# 5. Verifies stack no longer exists
# 6. Provides manual cleanup instructions on timeout
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - Timeout in minutes (required, e.g., 30 for standard, 45 for CloudFront)
#   $3 - AWS CLI profile argument (e.g., "--profile myprofile" or empty string)
#
# Returns:
#   0 - Stack deleted successfully (no longer exists)
#   1 - Stack deletion failed (DELETE_FAILED status)
#   2 - Timeout waiting for deletion
#
# Example:
#   if wait_for_stack_deletion "my-stack" 30 "$PROFILE_ARG"; then
#       echo "Stack deleted"
#   else
#       exit_code=$?
#       if [ $exit_code -eq 2 ]; then
#           echo "Timeout"
#       else
#           echo "Deletion failed"
#       fi
#   fi
##############################################################################
wait_for_stack_deletion() {
    local stack_name="$1"
    local timeout_minutes="$2"
    local profile_arg="$3"
    local poll_interval_seconds=30
    
    if [[ -z "$stack_name" ]]; then
        log_error "wait_for_stack_deletion" "Stack name is required"
        return 1
    fi
    
    if [[ -z "$timeout_minutes" ]]; then
        log_error "wait_for_stack_deletion" "Timeout in minutes is required"
        return 1
    fi
    
    local timeout_seconds=$((timeout_minutes * 60))
    local start_time=$(date +%s)
    local last_status=""
    
    echo -e "${YELLOW}⏳ Waiting for stack deletion to complete (timeout: ${timeout_minutes} minutes)${NC}"
    echo -e "${YELLOW}⏳ Polling every ${poll_interval_seconds} seconds...${NC}"
    echo ""
    
    log_operation_result "wait_for_stack_deletion:$stack_name" "STARTED" "Timeout: ${timeout_minutes}m"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            local timeout_msg="Elapsed: ${elapsed_minutes}m ${elapsed_seconds}s, Timeout: ${timeout_minutes}m"
            log_error "wait_for_stack_deletion" "Timeout waiting for stack deletion. $timeout_msg" "$stack_name" "$profile_arg"
            log_operation_result "wait_for_stack_deletion:$stack_name" "TIMEOUT" "$timeout_msg"
            echo -e "${RED}  Stack may still be deleting - check AWS Console${NC}" >&2
            echo -e "${RED}  Console URL: https://console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks${NC}" >&2
            
            # Provide manual cleanup instructions
            log_manual_cleanup_instructions "$stack_name" "$profile_arg"
            
            return 2
        fi
        
        # Log the status check command (only on first poll and status changes to reduce noise)
        if [[ -z "$last_status" ]]; then
            log_command aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" $profile_arg
        fi
        
        # Query stack status
        local stack_status
        local status_output
        status_output=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            $profile_arg 2>&1)
        local status_exit_code=$?
        
        if [ $status_exit_code -ne 0 ]; then
            # Stack doesn't exist (deletion complete)
            stack_status="DOES_NOT_EXIST"
        else
            stack_status="$status_output"
        fi
        
        # Check if stack is deleted
        if [[ "$stack_status" == "DOES_NOT_EXIST" ]]; then
            echo -e "${GREEN}✓ Stack deleted successfully${NC}"
            echo -e "${GREEN}  Total time: ${elapsed_minutes}m ${elapsed_seconds}s${NC}"
            log_operation_result "wait_for_stack_deletion:$stack_name" "SUCCESS" "Deleted in ${elapsed_minutes}m ${elapsed_seconds}s"
            return 0
        fi
        
        # Check for deletion failure
        if [[ "$stack_status" == "DELETE_FAILED" ]]; then
            log_error "wait_for_stack_deletion" "Stack deletion failed with status DELETE_FAILED" "$stack_name" "$profile_arg"
            log_operation_result "wait_for_stack_deletion:$stack_name" "FAILURE" "DELETE_FAILED after ${elapsed_minutes}m ${elapsed_seconds}s"
            return 1
        fi
        
        # Log status change
        if [[ "$stack_status" != "$last_status" ]]; then
            echo -e "${YELLOW}  Stack status: $stack_status (${elapsed_minutes}m ${elapsed_seconds}s elapsed)${NC}"
            last_status="$stack_status"
        else
            # Log progress every 30 seconds even if status hasn't changed
            echo -e "${YELLOW}  Still deleting... (${elapsed_minutes}m ${elapsed_seconds}s elapsed)${NC}"
        fi
        
        # Wait before next poll
        sleep $poll_interval_seconds
    done
}

##############################################################################
# verify_stack_deleted
#
# Verifies that a CloudFormation stack no longer exists.
#
# This function queries AWS to confirm the stack is completely gone.
# Use this as a final verification step before proceeding to dependent operations.
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - AWS CLI profile argument (e.g., "--profile myprofile" or empty string)
#
# Returns:
#   0 - Stack does not exist (deleted successfully)
#   1 - Stack still exists
#
# Example:
#   if verify_stack_deleted "my-stack" "$PROFILE_ARG"; then
#       echo "Confirmed: stack is deleted"
#   else
#       echo "Error: stack still exists"
#       exit 1
#   fi
##############################################################################
verify_stack_deleted() {
    local stack_name="$1"
    local profile_arg="$2"
    
    if [[ -z "$stack_name" ]]; then
        log_error "verify_stack_deleted" "Stack name is required"
        return 1
    fi
    
    echo -e "${YELLOW}  Verifying stack no longer exists: $stack_name${NC}"
    
    # Log the verification command
    log_command aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" $profile_arg
    
    # Query stack status
    local stack_status
    local status_output
    status_output=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        $profile_arg 2>&1)
    local status_exit_code=$?
    
    if [ $status_exit_code -ne 0 ]; then
        # Stack doesn't exist (which is what we want)
        stack_status="DOES_NOT_EXIST"
    else
        stack_status="$status_output"
    fi
    
    if [[ "$stack_status" == "DOES_NOT_EXIST" ]]; then
        echo -e "${GREEN}✓ Confirmed: Stack no longer exists${NC}"
        log_operation_result "verify_stack_deleted:$stack_name" "SUCCESS" "Stack confirmed deleted"
        return 0
    else
        log_error "verify_stack_deleted" "Stack still exists with status: $stack_status" "$stack_name" "$profile_arg"
        log_operation_result "verify_stack_deleted:$stack_name" "FAILURE" "Stack still exists: $stack_status"
        return 1
    fi
}

##############################################################################
# get_nested_stacks
#
# Retrieves the list of nested stacks for a given parent stack.
#
# This function queries CloudFormation to find all nested stacks (resources
# of type AWS::CloudFormation::Stack) within a parent stack.
#
# Arguments:
#   $1 - Parent stack name (required)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Successfully retrieved nested stacks (may be empty list)
#   1 - Failed to query nested stacks
#
# Output:
#   Prints nested stack names (physical resource IDs) one per line to stdout
#
# Example:
#   nested_stacks=$(get_nested_stacks "my-parent-stack" "$PROFILE_ARG")
#   if [ $? -eq 0 ]; then
#       for nested in $nested_stacks; do
#           echo "Found nested stack: $nested"
#       done
#   fi
##############################################################################
get_nested_stacks() {
    local parent_stack="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$parent_stack" ]]; then
        log_error "get_nested_stacks" "Parent stack name is required"
        return 1
    fi
    
    # Log the command
    log_command aws cloudformation list-stack-resources --stack-name "$parent_stack" --region "$AWS_REGION" $profile_arg
    
    # Query for nested stacks (resources of type AWS::CloudFormation::Stack)
    local nested_output
    nested_output=$(aws cloudformation list-stack-resources \
        --stack-name "$parent_stack" \
        --region "$AWS_REGION" \
        --query 'StackResourceSummaries[?ResourceType==`AWS::CloudFormation::Stack`].PhysicalResourceId' \
        --output text \
        $profile_arg 2>&1)
    local query_exit_code=$?
    
    if [ $query_exit_code -ne 0 ]; then
        # Stack might not exist or might be in a state where resources can't be listed
        if [[ "$nested_output" == *"does not exist"* ]]; then
            # Stack doesn't exist - this is okay, return empty list
            return 0
        else
            log_error "get_nested_stacks" "Failed to query nested stacks: $nested_output" "$parent_stack" "$profile_arg"
            return 1
        fi
    fi
    
    # Output the nested stack names (one per line)
    if [[ -n "$nested_output" ]] && [[ "$nested_output" != "None" ]]; then
        echo "$nested_output"
    fi
    
    return 0
}

##############################################################################
# wait_for_nested_stacks_deletion
#
# Monitors nested stack deletion progress during parent stack deletion.
#
# This function:
# 1. Identifies all nested stacks in the parent
# 2. Waits for all nested stacks to enter DELETE_IN_PROGRESS state
# 3. Monitors their deletion progress
# 4. Logs any nested stack failures
# 5. Verifies all nested stacks are deleted when parent completes
#
# Arguments:
#   $1 - Parent stack name (required)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - All nested stacks deleted successfully
#   1 - One or more nested stacks failed to delete
#
# Example:
#   if wait_for_nested_stacks_deletion "my-parent-stack" "$PROFILE_ARG"; then
#       echo "All nested stacks deleted"
#   else
#       echo "Some nested stacks failed"
#   fi
##############################################################################
wait_for_nested_stacks_deletion() {
    local parent_stack="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$parent_stack" ]]; then
        log_error "wait_for_nested_stacks_deletion" "Parent stack name is required"
        return 1
    fi
    
    echo -e "${YELLOW}  Checking for nested stacks in: $parent_stack${NC}"
    
    # Get list of nested stacks
    local nested_stacks
    nested_stacks=$(get_nested_stacks "$parent_stack" "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        log_error "wait_for_nested_stacks_deletion" "Failed to retrieve nested stacks" "$parent_stack" "$profile_arg"
        return 1
    fi
    
    # If no nested stacks, nothing to monitor
    if [[ -z "$nested_stacks" ]]; then
        echo -e "${GREEN}  No nested stacks found${NC}"
        return 0
    fi
    
    # Convert to array for easier processing
    local nested_array=()
    while IFS= read -r stack; do
        if [[ -n "$stack" ]]; then
            nested_array+=("$stack")
        fi
    done <<< "$nested_stacks"
    
    local nested_count=${#nested_array[@]}
    echo -e "${YELLOW}  Found ${nested_count} nested stack(s)${NC}"
    
    # Log each nested stack
    for nested in "${nested_array[@]}"; do
        echo -e "${YELLOW}    - $nested${NC}"
    done
    
    # Wait for all nested stacks to enter DELETE_IN_PROGRESS
    echo -e "${YELLOW}  Waiting for nested stacks to start deleting...${NC}"
    sleep 5
    
    local all_deleting=false
    local check_count=0
    local max_checks=12  # 60 seconds total (5 second intervals)
    
    while [ $check_count -lt $max_checks ] && [ "$all_deleting" = false ]; do
        all_deleting=true
        
        for nested in "${nested_array[@]}"; do
            local nested_status
            nested_status=$(aws cloudformation describe-stacks \
                --stack-name "$nested" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].StackStatus' \
                --output text \
                $profile_arg 2>/dev/null || echo "DOES_NOT_EXIST")
            
            if [[ "$nested_status" != "DELETE_IN_PROGRESS" ]] && [[ "$nested_status" != "DOES_NOT_EXIST" ]]; then
                all_deleting=false
                echo -e "${YELLOW}    Nested stack $nested status: $nested_status${NC}"
            fi
        done
        
        if [ "$all_deleting" = false ]; then
            check_count=$((check_count + 1))
            sleep 5
        fi
    done
    
    if [ "$all_deleting" = true ]; then
        echo -e "${GREEN}  ✓ All nested stacks are deleting${NC}"
    else
        echo -e "${YELLOW}  ⚠ Some nested stacks not yet in DELETE_IN_PROGRESS state${NC}"
    fi
    
    # Monitor nested stack deletion progress
    log_operation_result "wait_for_nested_stacks_deletion:$parent_stack" "MONITORING" "${nested_count} nested stacks"
    
    return 0
}

##############################################################################
# verify_nested_stacks_deleted
#
# Verifies that all nested stacks are deleted after parent deletion.
#
# This function checks if any nested stacks remain after the parent stack
# deletion completes. If orphaned nested stacks are found, it attempts to
# delete them individually.
#
# Arguments:
#   $1 - Parent stack name (required)
#   $2 - List of nested stack names (space-separated, required)
#   $3 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - All nested stacks verified deleted
#   1 - Some nested stacks remain (after cleanup attempt)
#
# Example:
#   nested_stacks=$(get_nested_stacks "parent" "$PROFILE_ARG")
#   # ... delete parent ...
#   verify_nested_stacks_deleted "parent" "$nested_stacks" "$PROFILE_ARG"
##############################################################################
verify_nested_stacks_deleted() {
    local parent_stack="$1"
    local nested_stacks="$2"
    local profile_arg="${3:-}"
    
    if [[ -z "$parent_stack" ]]; then
        log_error "verify_nested_stacks_deleted" "Parent stack name is required"
        return 1
    fi
    
    if [[ -z "$nested_stacks" ]]; then
        # No nested stacks to verify
        return 0
    fi
    
    echo -e "${YELLOW}  Verifying nested stacks are deleted...${NC}"
    
    # Convert to array
    local nested_array=()
    while IFS= read -r stack; do
        if [[ -n "$stack" ]]; then
            nested_array+=("$stack")
        fi
    done <<< "$nested_stacks"
    
    # Check each nested stack
    local orphaned_stacks=()
    local failed_stacks=()
    
    for nested in "${nested_array[@]}"; do
        local nested_status
        nested_status=$(aws cloudformation describe-stacks \
            --stack-name "$nested" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            $profile_arg 2>/dev/null || echo "DOES_NOT_EXIST")
        
        if [[ "$nested_status" == "DOES_NOT_EXIST" ]]; then
            echo -e "${GREEN}    ✓ Nested stack deleted: $nested${NC}"
        elif [[ "$nested_status" == "DELETE_FAILED" ]]; then
            echo -e "${RED}    ✗ Nested stack deletion failed: $nested${NC}"
            failed_stacks+=("$nested")
            log_error "verify_nested_stacks_deleted" "Nested stack deletion failed: $nested (status: $nested_status)" "$nested" "$profile_arg"
        else
            echo -e "${YELLOW}    ⚠ Nested stack still exists: $nested (status: $nested_status)${NC}"
            orphaned_stacks+=("$nested")
        fi
    done
    
    # If we have orphaned or failed stacks, attempt individual deletion
    if [ ${#orphaned_stacks[@]} -gt 0 ] || [ ${#failed_stacks[@]} -gt 0 ]; then
        echo -e "${YELLOW}  Attempting to delete orphaned nested stacks individually...${NC}"
        
        local all_stacks=("${orphaned_stacks[@]}" "${failed_stacks[@]}")
        local cleanup_failed=false
        
        for nested in "${all_stacks[@]}"; do
            echo -e "${YELLOW}    Deleting nested stack: $nested${NC}"
            
            # Attempt deletion
            if delete_stack_verified "$nested" "$profile_arg"; then
                # Wait for deletion (shorter timeout for nested stacks)
                if wait_for_stack_deletion "$nested" 15 "$profile_arg"; then
                    echo -e "${GREEN}    ✓ Successfully deleted nested stack: $nested${NC}"
                else
                    echo -e "${RED}    ✗ Failed to delete nested stack: $nested${NC}"
                    cleanup_failed=true
                fi
            else
                echo -e "${RED}    ✗ Failed to initiate deletion of nested stack: $nested${NC}"
                cleanup_failed=true
            fi
        done
        
        if [ "$cleanup_failed" = true ]; then
            log_operation_result "verify_nested_stacks_deleted:$parent_stack" "FAILURE" "Some nested stacks could not be deleted"
            return 1
        else
            log_operation_result "verify_nested_stacks_deleted:$parent_stack" "SUCCESS" "All orphaned nested stacks cleaned up"
            return 0
        fi
    fi
    
    echo -e "${GREEN}  ✓ All nested stacks verified deleted${NC}"
    log_operation_result "verify_nested_stacks_deleted:$parent_stack" "SUCCESS" "All nested stacks deleted"
    return 0
}

##############################################################################
# delete_stack_with_verification
#
# High-level function that combines all verification steps.
#
# This is a convenience function that:
# 1. Identifies nested stacks (if any)
# 2. Initiates deletion and verifies it started
# 3. Monitors nested stack deletion progress
# 4. Waits for deletion to complete with polling
# 5. Verifies stack and nested stacks no longer exist
#
# Arguments:
#   $1 - Stack name (required)
#   $2 - Timeout in minutes (required)
#   $3 - AWS CLI profile argument (e.g., "--profile myprofile" or empty string)
#
# Returns:
#   0 - Stack deleted successfully with full verification
#   1 - Deletion failed
#   2 - Timeout
#
# Example:
#   if delete_stack_with_verification "my-stack" 30 "$PROFILE_ARG"; then
#       echo "Stack fully deleted and verified"
#   else
#       echo "Stack deletion failed"
#       exit 1
#   fi
##############################################################################
delete_stack_with_verification() {
    local stack_name="$1"
    local timeout_minutes="$2"
    local profile_arg="$3"
    
    log_operation_result "delete_stack_with_verification:$stack_name" "STARTED" "Timeout: ${timeout_minutes}m"
    
    # Step 0: Identify nested stacks before deletion
    local nested_stacks
    nested_stacks=$(get_nested_stacks "$stack_name" "$profile_arg")
    local has_nested_stacks=false
    if [[ -n "$nested_stacks" ]]; then
        has_nested_stacks=true
    fi
    
    # Step 1: Initiate deletion and verify it started
    if ! delete_stack_verified "$stack_name" "$profile_arg"; then
        log_operation_result "delete_stack_with_verification:$stack_name" "FAILURE" "Failed at initiation step"
        return 1
    fi
    
    # Step 2: Monitor nested stack deletion if applicable
    if [ "$has_nested_stacks" = true ]; then
        if ! wait_for_nested_stacks_deletion "$stack_name" "$profile_arg"; then
            echo -e "${YELLOW}  ⚠ Warning: Nested stack monitoring encountered issues${NC}"
            # Don't fail here - continue with parent deletion
        fi
    fi
    
    # Step 3: Wait for deletion to complete
    local wait_result
    wait_for_stack_deletion "$stack_name" "$timeout_minutes" "$profile_arg"
    wait_result=$?
    
    if [ $wait_result -ne 0 ]; then
        if [ $wait_result -eq 2 ]; then
            log_operation_result "delete_stack_with_verification:$stack_name" "TIMEOUT" "Failed at wait step"
        else
            log_operation_result "delete_stack_with_verification:$stack_name" "FAILURE" "Failed at wait step"
        fi
        return $wait_result
    fi
    
    # Step 4: Final verification of parent stack
    if ! verify_stack_deleted "$stack_name" "$profile_arg"; then
        log_operation_result "delete_stack_with_verification:$stack_name" "FAILURE" "Failed at verification step"
        return 1
    fi
    
    # Step 5: Verify nested stacks are also deleted
    if [ "$has_nested_stacks" = true ]; then
        if ! verify_nested_stacks_deleted "$stack_name" "$nested_stacks" "$profile_arg"; then
            log_operation_result "delete_stack_with_verification:$stack_name" "FAILURE" "Nested stacks verification failed"
            return 1
        fi
    fi
    
    log_operation_result "delete_stack_with_verification:$stack_name" "SUCCESS" "All steps completed"
    return 0
}
