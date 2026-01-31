#!/bin/bash

# Cleanup Verification Module
# 
# This module provides functions for verifying that all AWS resources
# have been properly deleted after cleanup operations. It queries AWS
# for remaining resources by lab identifier and reports any orphaned resources.
#
# Key Features:
# - Query remaining CloudFormation stacks by lab identifier
# - Query remaining S3 buckets by lab identifier
# - Query remaining CloudWatch log groups by lab identifier
# - Query remaining Cognito user pools by lab identifier
# - Exit with error if any resources remain after cleanup
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/cleanup-verification.sh"
#   query_remaining_stacks "lab6" "$PROFILE_ARG"
#   verify_complete_cleanup "lab6" "$PROFILE_ARG"

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

##############################################################################
# query_remaining_stacks
#
# Queries AWS CloudFormation for stacks containing the lab identifier.
#
# This function searches for stacks whose names contain the lab identifier
# (case-insensitive). It returns stacks in any state except DELETE_COMPLETE.
# CDKToolkit stacks are filtered out if they should be preserved.
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#   $3 - Skip CDKToolkit filtering (optional, default: false)
#
# Returns:
#   0 - Query successful (may or may not have found stacks)
#   1 - Query failed
#
# Output:
#   Prints stack names (one per line) to stdout
#   Prints count and details to stderr
#
# Example:
#   remaining_stacks=$(query_remaining_stacks "lab6" "$PROFILE_ARG")
#   if [[ -n "$remaining_stacks" ]]; then
#       echo "Found orphaned stacks: $remaining_stacks"
#   fi
##############################################################################
query_remaining_stacks() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    local skip_cdktoolkit_filter="${3:-false}"
    
    if [[ -z "$lab_id" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Querying remaining CloudFormation stacks for: ${lab_id}${NC}" >&2
    
    # Query all stacks (excluding DELETE_COMPLETE)
    local stacks_output
    stacks_output=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE \
                               CREATE_IN_PROGRESS UPDATE_IN_PROGRESS DELETE_IN_PROGRESS \
                               CREATE_FAILED UPDATE_FAILED DELETE_FAILED ROLLBACK_FAILED \
                               UPDATE_ROLLBACK_COMPLETE UPDATE_ROLLBACK_FAILED \
        --query "StackSummaries[?contains(StackName, '${lab_id}')].StackName" \
        --output text \
        $profile_arg 2>&1)
    
    local query_exit_code=$?
    
    if [ $query_exit_code -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query CloudFormation stacks${NC}" >&2
        echo -e "${RED}  ${stacks_output}${NC}" >&2
        return 1
    fi
    
    # Convert tab-separated output to newline-separated
    local remaining_stacks=$(echo "$stacks_output" | tr '\t' '\n' | grep -v '^$')
    
    # Filter CDKToolkit stacks if needed
    if [[ "$skip_cdktoolkit_filter" != "true" ]] && [[ -n "$remaining_stacks" ]]; then
        remaining_stacks=$(filter_cdktoolkit_stacks "$remaining_stacks" "$lab_id" "$profile_arg")
    fi
    
    if [[ -z "$remaining_stacks" ]]; then
        echo -e "${GREEN}✓ No remaining CloudFormation stacks found${NC}" >&2
    else
        local stack_count=$(echo "$remaining_stacks" | wc -l | tr -d ' ')
        echo -e "${YELLOW}⚠ Found ${stack_count} remaining stack(s):${NC}" >&2
        echo "$remaining_stacks" | while read -r stack; do
            echo -e "${YELLOW}  - ${stack}${NC}" >&2
        done
    fi
    
    # Output stack names to stdout for capture
    echo "$remaining_stacks"
    return 0
}

##############################################################################
# query_remaining_buckets
#
# Queries AWS S3 for buckets containing the lab identifier.
#
# This function searches for S3 buckets whose names contain the lab identifier
# (case-insensitive).
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Query successful (may or may not have found buckets)
#   1 - Query failed
#
# Output:
#   Prints bucket names (one per line) to stdout
#   Prints count and details to stderr
#
# Example:
#   remaining_buckets=$(query_remaining_buckets "lab6" "$PROFILE_ARG")
#   if [[ -n "$remaining_buckets" ]]; then
#       echo "Found orphaned buckets: $remaining_buckets"
#   fi
##############################################################################
query_remaining_buckets() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$lab_id" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Querying remaining S3 buckets for: ${lab_id}${NC}" >&2
    
    # Query all buckets
    local buckets_output
    buckets_output=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${lab_id}')].Name" \
        --output text \
        $profile_arg 2>&1)
    
    local query_exit_code=$?
    
    if [ $query_exit_code -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query S3 buckets${NC}" >&2
        echo -e "${RED}  ${buckets_output}${NC}" >&2
        return 1
    fi
    
    # Convert tab-separated output to newline-separated
    local remaining_buckets=$(echo "$buckets_output" | tr '\t' '\n' | grep -v '^$')
    
    if [[ -z "$remaining_buckets" ]]; then
        echo -e "${GREEN}✓ No remaining S3 buckets found${NC}" >&2
    else
        local bucket_count=$(echo "$remaining_buckets" | wc -l | tr -d ' ')
        echo -e "${YELLOW}⚠ Found ${bucket_count} remaining bucket(s):${NC}" >&2
        echo "$remaining_buckets" | while read -r bucket; do
            echo -e "${YELLOW}  - ${bucket}${NC}" >&2
        done
    fi
    
    # Output bucket names to stdout for capture
    echo "$remaining_buckets"
    return 0
}

##############################################################################
# query_remaining_log_groups
#
# Queries AWS CloudWatch Logs for log groups containing the lab identifier.
#
# This function searches for CloudWatch log groups whose names contain the
# lab identifier (case-insensitive).
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Query successful (may or may not have found log groups)
#   1 - Query failed
#
# Output:
#   Prints log group names (one per line) to stdout
#   Prints count and details to stderr
#
# Example:
#   remaining_logs=$(query_remaining_log_groups "lab6" "$PROFILE_ARG")
#   if [[ -n "$remaining_logs" ]]; then
#       echo "Found orphaned log groups: $remaining_logs"
#   fi
##############################################################################
query_remaining_log_groups() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$lab_id" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Querying remaining CloudWatch log groups for: ${lab_id}${NC}" >&2
    
    # Query log groups with pagination support
    local log_groups=""
    local next_token=""
    
    while true; do
        local query_cmd="aws logs describe-log-groups --region \"$AWS_REGION\" $profile_arg"
        
        if [[ -n "$next_token" ]]; then
            query_cmd="$query_cmd --next-token \"$next_token\""
        fi
        
        local logs_output
        logs_output=$(eval "$query_cmd" 2>&1)
        local query_exit_code=$?
        
        if [ $query_exit_code -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to query CloudWatch log groups${NC}" >&2
            echo -e "${RED}  ${logs_output}${NC}" >&2
            return 1
        fi
        
        # Extract log group names containing lab_id
        local page_log_groups=$(echo "$logs_output" | \
            jq -r ".logGroups[]? | select(.logGroupName | contains(\"${lab_id}\")) | .logGroupName" 2>/dev/null)
        
        if [[ -n "$page_log_groups" ]]; then
            if [[ -z "$log_groups" ]]; then
                log_groups="$page_log_groups"
            else
                log_groups="${log_groups}"$'\n'"${page_log_groups}"
            fi
        fi
        
        # Check for next token
        next_token=$(echo "$logs_output" | jq -r '.nextToken // empty' 2>/dev/null)
        
        if [[ -z "$next_token" ]]; then
            break
        fi
    done
    
    if [[ -z "$log_groups" ]]; then
        echo -e "${GREEN}✓ No remaining CloudWatch log groups found${NC}" >&2
    else
        local log_count=$(echo "$log_groups" | wc -l | tr -d ' ')
        echo -e "${YELLOW}⚠ Found ${log_count} remaining log group(s):${NC}" >&2
        echo "$log_groups" | while read -r log_group; do
            echo -e "${YELLOW}  - ${log_group}${NC}" >&2
        done
    fi
    
    # Output log group names to stdout for capture
    echo "$log_groups"
    return 0
}

##############################################################################
# query_remaining_cognito_pools
#
# Queries AWS Cognito for user pools containing the lab identifier.
#
# This function searches for Cognito user pools whose names contain the
# lab identifier (case-insensitive).
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Query successful (may or may not have found pools)
#   1 - Query failed
#
# Output:
#   Prints pool IDs and names (one per line) to stdout
#   Prints count and details to stderr
#
# Example:
#   remaining_pools=$(query_remaining_cognito_pools "lab6" "$PROFILE_ARG")
#   if [[ -n "$remaining_pools" ]]; then
#       echo "Found orphaned Cognito pools: $remaining_pools"
#   fi
##############################################################################
query_remaining_cognito_pools() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$lab_id" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Querying remaining Cognito user pools for: ${lab_id}${NC}" >&2
    
    # Query user pools with pagination support
    local user_pools=""
    local next_token=""
    
    while true; do
        local query_cmd="aws cognito-idp list-user-pools --region \"$AWS_REGION\" --max-results 60 $profile_arg"
        
        if [[ -n "$next_token" ]]; then
            query_cmd="$query_cmd --next-token \"$next_token\""
        fi
        
        local pools_output
        pools_output=$(eval "$query_cmd" 2>&1)
        local query_exit_code=$?
        
        if [ $query_exit_code -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to query Cognito user pools${NC}" >&2
            echo -e "${RED}  ${pools_output}${NC}" >&2
            return 1
        fi
        
        # Extract pool IDs and names containing lab_id
        local page_pools=$(echo "$pools_output" | \
            jq -r ".UserPools[]? | select(.Name | contains(\"${lab_id}\")) | \"\(.Id) (\(.Name))\"" 2>/dev/null)
        
        if [[ -n "$page_pools" ]]; then
            if [[ -z "$user_pools" ]]; then
                user_pools="$page_pools"
            else
                user_pools="${user_pools}"$'\n'"${page_pools}"
            fi
        fi
        
        # Check for next token
        next_token=$(echo "$pools_output" | jq -r '.NextToken // empty' 2>/dev/null)
        
        if [[ -z "$next_token" ]]; then
            break
        fi
    done
    
    if [[ -z "$user_pools" ]]; then
        echo -e "${GREEN}✓ No remaining Cognito user pools found${NC}" >&2
    else
        local pool_count=$(echo "$user_pools" | wc -l | tr -d ' ')
        echo -e "${YELLOW}⚠ Found ${pool_count} remaining user pool(s):${NC}" >&2
        echo "$user_pools" | while read -r pool; do
            echo -e "${YELLOW}  - ${pool}${NC}" >&2
        done
    fi
    
    # Output pool info to stdout for capture
    echo "$user_pools"
    return 0
}

##############################################################################
# verify_complete_cleanup
#
# Verifies that all AWS resources for a lab have been deleted.
#
# This function queries all resource types (stacks, S3 buckets, log groups,
# Cognito pools) and exits with error if any resources remain. It provides
# a comprehensive verification that cleanup was successful.
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - All resources deleted (cleanup verified)
#   3 - Orphaned resources detected (cleanup incomplete)
#   1 - Query failed
#
# Example:
#   if verify_complete_cleanup "lab6" "$PROFILE_ARG"; then
#       echo "Cleanup verified - all resources deleted"
#   else
#       exit_code=$?
#       if [ $exit_code -eq 3 ]; then
#           echo "Orphaned resources detected"
#       fi
#   fi
##############################################################################
verify_complete_cleanup() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$lab_id" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}           POST-CLEANUP VERIFICATION: ${lab_id}              ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local has_orphaned_resources=false
    local orphaned_resources=()
    
    # Query remaining stacks
    local remaining_stacks
    remaining_stacks=$(query_remaining_stacks "$lab_id" "$profile_arg")
    local stacks_query_result=$?
    
    if [ $stacks_query_result -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query CloudFormation stacks${NC}" >&2
        return 1
    fi
    
    if [[ -n "$remaining_stacks" ]]; then
        has_orphaned_resources=true
        while IFS= read -r stack; do
            orphaned_resources+=("STACK: $stack")
        done <<< "$remaining_stacks"
    fi
    
    echo ""
    
    # Query remaining S3 buckets
    local remaining_buckets
    remaining_buckets=$(query_remaining_buckets "$lab_id" "$profile_arg")
    local buckets_query_result=$?
    
    if [ $buckets_query_result -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query S3 buckets${NC}" >&2
        return 1
    fi
    
    if [[ -n "$remaining_buckets" ]]; then
        has_orphaned_resources=true
        while IFS= read -r bucket; do
            orphaned_resources+=("S3_BUCKET: $bucket")
        done <<< "$remaining_buckets"
    fi
    
    echo ""
    
    # Query remaining log groups
    local remaining_log_groups
    remaining_log_groups=$(query_remaining_log_groups "$lab_id" "$profile_arg")
    local logs_query_result=$?
    
    if [ $logs_query_result -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query CloudWatch log groups${NC}" >&2
        return 1
    fi
    
    if [[ -n "$remaining_log_groups" ]]; then
        has_orphaned_resources=true
        while IFS= read -r log_group; do
            orphaned_resources+=("LOG_GROUP: $log_group")
        done <<< "$remaining_log_groups"
    fi
    
    echo ""
    
    # Query remaining Cognito pools
    local remaining_cognito_pools
    remaining_cognito_pools=$(query_remaining_cognito_pools "$lab_id" "$profile_arg")
    local cognito_query_result=$?
    
    if [ $cognito_query_result -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query Cognito user pools${NC}" >&2
        return 1
    fi
    
    if [[ -n "$remaining_cognito_pools" ]]; then
        has_orphaned_resources=true
        while IFS= read -r pool; do
            orphaned_resources+=("COGNITO_POOL: $pool")
        done <<< "$remaining_cognito_pools"
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    
    # Report results
    if [ "$has_orphaned_resources" = true ]; then
        echo -e "${RED}✗ VERIFICATION FAILED: Orphaned resources detected${NC}" >&2
        echo -e "${RED}  Total orphaned resources: ${#orphaned_resources[@]}${NC}" >&2
        echo ""
        echo -e "${YELLOW}Orphaned resources:${NC}" >&2
        for resource in "${orphaned_resources[@]}"; do
            echo -e "${YELLOW}  - ${resource}${NC}" >&2
        done
        echo ""
        echo -e "${YELLOW}Manual cleanup required. See cleanup instructions above.${NC}" >&2
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        return 3
    else
        echo -e "${GREEN}✓ VERIFICATION PASSED: All resources deleted${NC}"
        echo -e "${GREEN}  No orphaned resources found for ${lab_id}${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        return 0
    fi
}

##############################################################################
# is_cdktoolkit_stack
#
# Checks if a stack name is a CDKToolkit stack.
#
# CDKToolkit stacks are used by AWS CDK for bootstrapping and are shared
# across multiple labs (Lab5 and Lab6). They should not be deleted if
# other labs are still using them.
#
# Arguments:
#   $1 - Stack name to check
#
# Returns:
#   0 - Stack is a CDKToolkit stack
#   1 - Stack is not a CDKToolkit stack
#
# Example:
#   if is_cdktoolkit_stack "CDKToolkit"; then
#       echo "This is a CDKToolkit stack"
#   fi
##############################################################################
is_cdktoolkit_stack() {
    local stack_name="$1"
    
    if [[ -z "$stack_name" ]]; then
        return 1
    fi
    
    # Check if stack name starts with "CDKToolkit"
    if [[ "$stack_name" == CDKToolkit* ]]; then
        return 0
    fi
    
    return 1
}

##############################################################################
# should_preserve_cdktoolkit
#
# Checks if CDKToolkit stack should be preserved during cleanup.
#
# CDKToolkit is shared between Lab5 and Lab6. It should only be deleted
# when both labs have been cleaned up. This function checks if the other
# lab's pipeline stack still exists.
#
# Arguments:
#   $1 - Current lab identifier (e.g., "lab5", "lab6")
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - CDKToolkit should be preserved (other lab exists)
#   1 - CDKToolkit can be deleted (other lab doesn't exist)
#
# Output:
#   Prints warning message to stderr if CDKToolkit should be preserved
#
# Example:
#   if should_preserve_cdktoolkit "lab6" "$PROFILE_ARG"; then
#       echo "Skipping CDKToolkit deletion"
#   fi
##############################################################################
should_preserve_cdktoolkit() {
    local current_lab="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$current_lab" ]]; then
        echo -e "${RED}ERROR: Lab identifier is required${NC}" >&2
        return 1
    fi
    
    # Determine which lab to check for
    local other_lab=""
    if [[ "$current_lab" == "lab5" ]]; then
        other_lab="lab6"
    elif [[ "$current_lab" == "lab6" ]]; then
        other_lab="lab5"
    else
        # CDKToolkit is only shared between Lab5 and Lab6
        # For other labs, it can be deleted
        return 1
    fi
    
    # Check if the other lab's pipeline stack exists
    local pipeline_stack_name="serverless-saas-pipeline-${other_lab}"
    
    echo -e "${BLUE}Checking if ${other_lab} pipeline stack exists...${NC}" >&2
    
    local stack_status
    stack_status=$(aws cloudformation describe-stacks \
        --region "$AWS_REGION" \
        --stack-name "$pipeline_stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        $profile_arg 2>/dev/null)
    
    local query_exit_code=$?
    
    if [ $query_exit_code -eq 0 ] && [[ -n "$stack_status" ]] && [[ "$stack_status" != "DELETE_COMPLETE" ]]; then
        # Other lab's pipeline stack exists
        echo -e "${YELLOW}⚠ WARNING: ${other_lab} pipeline stack exists (${stack_status})${NC}" >&2
        echo -e "${YELLOW}  CDKToolkit stack is shared between Lab5 and Lab6${NC}" >&2
        echo -e "${YELLOW}  Skipping CDKToolkit deletion to avoid breaking ${other_lab}${NC}" >&2
        echo -e "${YELLOW}  CDKToolkit can be safely deleted after both labs are cleaned up${NC}" >&2
        return 0
    fi
    
    # Other lab's pipeline stack doesn't exist or is deleted
    echo -e "${GREEN}✓ ${other_lab} pipeline stack not found - CDKToolkit can be deleted${NC}" >&2
    return 1
}

##############################################################################
# filter_cdktoolkit_stacks
#
# Filters out CDKToolkit stacks from a list of stack names if they should
# be preserved.
#
# This function takes a newline-separated list of stack names and removes
# any CDKToolkit stacks that should be preserved based on the current lab.
#
# Arguments:
#   $1 - Newline-separated list of stack names
#   $2 - Current lab identifier (e.g., "lab5", "lab6")
#   $3 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Success
#
# Output:
#   Prints filtered stack names (one per line) to stdout
#   Prints warnings to stderr for skipped CDKToolkit stacks
#
# Example:
#   filtered_stacks=$(filter_cdktoolkit_stacks "$all_stacks" "lab6" "$PROFILE_ARG")
##############################################################################
filter_cdktoolkit_stacks() {
    local stack_list="$1"
    local current_lab="$2"
    local profile_arg="${3:-}"
    
    if [[ -z "$stack_list" ]]; then
        return 0
    fi
    
    local filtered_stacks=""
    local cdktoolkit_skipped=false
    
    while IFS= read -r stack_name; do
        if [[ -z "$stack_name" ]]; then
            continue
        fi
        
        # Check if this is a CDKToolkit stack
        if is_cdktoolkit_stack "$stack_name"; then
            # Check if it should be preserved
            if should_preserve_cdktoolkit "$current_lab" "$profile_arg"; then
                cdktoolkit_skipped=true
                echo -e "${YELLOW}  Skipping CDKToolkit stack: ${stack_name}${NC}" >&2
                continue
            fi
        fi
        
        # Add to filtered list
        if [[ -z "$filtered_stacks" ]]; then
            filtered_stacks="$stack_name"
        else
            filtered_stacks="${filtered_stacks}"$'\n'"${stack_name}"
        fi
    done <<< "$stack_list"
    
    if [ "$cdktoolkit_skipped" = true ]; then
        echo "" >&2
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${BLUE}           CDKToolkit SHARED RESOURCE NOTICE                ${NC}" >&2
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${YELLOW}CDKToolkit stack is shared between Lab5 and Lab6.${NC}" >&2
        echo -e "${YELLOW}It has been excluded from cleanup to prevent breaking the other lab.${NC}" >&2
        echo "" >&2
        echo -e "${YELLOW}To delete CDKToolkit:${NC}" >&2
        echo -e "${YELLOW}1. Clean up both Lab5 and Lab6${NC}" >&2
        echo -e "${YELLOW}2. Run cleanup again - CDKToolkit will be deleted when both labs are gone${NC}" >&2
        echo "" >&2
        echo -e "${YELLOW}Or manually delete after confirming both labs are cleaned:${NC}" >&2
        echo -e "${YELLOW}  aws cloudformation delete-stack --stack-name CDKToolkit --region $AWS_REGION $profile_arg${NC}" >&2
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
    fi
    
    # Output filtered stack names to stdout
    echo "$filtered_stacks"
    return 0
}

##############################################################################
# generate_cleanup_commands
#
# Generates AWS CLI commands for manually cleaning up orphaned resources.
#
# This function provides specific AWS CLI commands that can be copy-pasted
# to manually clean up any resources that remain after automated cleanup.
#
# Arguments:
#   $1 - Lab identifier (e.g., "lab6", "lab1")
#   $2 - AWS CLI profile argument (optional)
#
# Output:
#   Prints AWS CLI commands to stdout
#
# Example:
#   generate_cleanup_commands "lab6" "$PROFILE_ARG"
##############################################################################
generate_cleanup_commands() {
    local lab_id="$1"
    local profile_arg="${2:-}"
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}        MANUAL CLEANUP COMMANDS FOR ${lab_id}                ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Get remaining resources
    local remaining_stacks=$(query_remaining_stacks "$lab_id" "$profile_arg" 2>/dev/null)
    local remaining_buckets=$(query_remaining_buckets "$lab_id" "$profile_arg" 2>/dev/null)
    local remaining_log_groups=$(query_remaining_log_groups "$lab_id" "$profile_arg" 2>/dev/null)
    local remaining_cognito_pools=$(query_remaining_cognito_pools "$lab_id" "$profile_arg" 2>/dev/null)
    
    # Generate stack deletion commands
    if [[ -n "$remaining_stacks" ]]; then
        echo -e "${BLUE}Delete CloudFormation stacks:${NC}"
        echo "$remaining_stacks" | while read -r stack; do
            echo "aws cloudformation delete-stack --stack-name \"$stack\" --region \"$AWS_REGION\" $profile_arg"
        done
        echo ""
    fi
    
    # Generate S3 bucket deletion commands
    if [[ -n "$remaining_buckets" ]]; then
        echo -e "${BLUE}Delete S3 buckets:${NC}"
        echo "$remaining_buckets" | while read -r bucket; do
            echo "# Empty and delete bucket: $bucket"
            echo "aws s3 rm s3://$bucket --recursive $profile_arg"
            echo "aws s3api delete-bucket --bucket \"$bucket\" --region \"$AWS_REGION\" $profile_arg"
            echo ""
        done
    fi
    
    # Generate log group deletion commands
    if [[ -n "$remaining_log_groups" ]]; then
        echo -e "${BLUE}Delete CloudWatch log groups:${NC}"
        echo "$remaining_log_groups" | while read -r log_group; do
            echo "aws logs delete-log-group --log-group-name \"$log_group\" --region \"$AWS_REGION\" $profile_arg"
        done
        echo ""
    fi
    
    # Generate Cognito pool deletion commands
    if [[ -n "$remaining_cognito_pools" ]]; then
        echo -e "${BLUE}Delete Cognito user pools:${NC}"
        echo "$remaining_cognito_pools" | while read -r pool_info; do
            local pool_id=$(echo "$pool_info" | awk '{print $1}')
            echo "aws cognito-idp delete-user-pool --user-pool-id \"$pool_id\" --region \"$AWS_REGION\" $profile_arg"
        done
        echo ""
    fi
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}
