#!/bin/bash

# CloudFront Safety Verification Module
#
# This module provides functions for safely deleting S3 buckets by ensuring
# CloudFront distributions are fully deleted first. This prevents the CloudFront
# Origin Hijacking vulnerability where an attacker could create a bucket with
# the same name and serve malicious content through an orphaned CloudFront distribution.
#
# Key Features:
# - Checks CloudFront distribution status before S3 deletion
# - Polls CloudFront status during shared stack deletion
# - Verifies no CloudFront distributions reference S3 buckets
# - Implements extended timeout handling for CloudFront (45 minutes)
# - Provides detailed logging of CloudFront deletion progress
#
# Security: This module implements the secure deletion order:
# 1. Delete CloudFormation stack (deletes CloudFront distributions)
# 2. Wait for CloudFront to be fully deleted (15-30 minutes)
# 3. Delete S3 buckets (now safe - no CloudFront references)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/cloudfront-safety.sh"
#   check_cloudfront_distributions_status "$PROFILE_ARG"
#   wait_for_cloudfront_deletion "my-stack" "$PROFILE_ARG"
#   verify_no_cloudfront_references "my-bucket" "$PROFILE_ARG"

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

# CloudFront-specific timeout (45 minutes)
CLOUDFRONT_TIMEOUT_MINUTES=45

##############################################################################
# get_cloudfront_distributions
#
# Retrieves all CloudFront distributions in the account.
#
# This function queries CloudFront to get a list of all distributions,
# including their IDs, statuses, and domain names.
#
# Arguments:
#   $1 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Query successful
#   1 - Query failed
#
# Output:
#   Prints distribution information (ID, Status, DomainName) to stdout
#   One distribution per line in format: "ID STATUS DOMAIN"
#
# Example:
#   distributions=$(get_cloudfront_distributions "$PROFILE_ARG")
#   if [[ -n "$distributions" ]]; then
#       echo "Found distributions: $distributions"
#   fi
##############################################################################
get_cloudfront_distributions() {
    local profile_arg="${1:-}"
    
    echo -e "${BLUE}Querying CloudFront distributions...${NC}" >&2
    
    # Query CloudFront distributions
    local distributions_output
    distributions_output=$(aws cloudfront list-distributions \
        --query 'DistributionList.Items[*].[Id,Status,DomainName]' \
        --output text \
        $profile_arg 2>&1)
    
    local query_exit_code=$?
    
    if [ $query_exit_code -ne 0 ]; then
        echo -e "${RED}ERROR: Failed to query CloudFront distributions${NC}" >&2
        echo -e "${RED}  ${distributions_output}${NC}" >&2
        return 1
    fi
    
    # Output distributions to stdout for capture
    echo "$distributions_output"
    return 0
}

##############################################################################
# check_cloudfront_distributions_status
#
# Checks the status of all CloudFront distributions before stack deletion.
#
# This function verifies that all CloudFront distributions are in a stable
# state (Deployed or InProgress) before initiating stack deletion. This
# ensures we can safely track their deletion progress.
#
# Arguments:
#   $1 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - All distributions are in valid state
#   1 - Query failed or distributions in invalid state
#
# Example:
#   if check_cloudfront_distributions_status "$PROFILE_ARG"; then
#       echo "CloudFront distributions are ready for deletion"
#   fi
##############################################################################
check_cloudfront_distributions_status() {
    local profile_arg="${1:-}"
    
    echo -e "${YELLOW}Checking CloudFront distribution status before deletion...${NC}"
    
    # Get all distributions
    local distributions
    distributions=$(get_cloudfront_distributions "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        return 1
    fi
    
    if [[ -z "$distributions" ]]; then
        echo -e "${GREEN}✓ No CloudFront distributions found${NC}"
        return 0
    fi
    
    # Check each distribution status
    local invalid_status_found=false
    local distribution_count=0
    
    while IFS=$'\t' read -r dist_id status domain; do
        if [[ -z "$dist_id" ]]; then
            continue
        fi
        
        distribution_count=$((distribution_count + 1))
        echo -e "${YELLOW}  Distribution: $dist_id${NC}"
        echo -e "${YELLOW}    Status: $status${NC}"
        echo -e "${YELLOW}    Domain: $domain${NC}"
        
        # Valid statuses for deletion: Deployed, InProgress
        if [[ "$status" != "Deployed" ]] && [[ "$status" != "InProgress" ]]; then
            echo -e "${RED}    ⚠ Invalid status for deletion: $status${NC}" >&2
            invalid_status_found=true
        fi
    done <<< "$distributions"
    
    echo -e "${BLUE}Total CloudFront distributions: $distribution_count${NC}"
    
    if [ "$invalid_status_found" = true ]; then
        echo -e "${RED}✗ Some distributions are not in valid state for deletion${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ All distributions are in valid state${NC}"
    return 0
}

##############################################################################
# get_distribution_origins
#
# Gets the origin configuration for a CloudFront distribution.
#
# This function retrieves the origin domain names for a distribution,
# which is used to check if the distribution references specific S3 buckets.
#
# Arguments:
#   $1 - Distribution ID (required)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Query successful
#   1 - Query failed
#
# Output:
#   Prints origin domain names to stdout (one per line)
#
# Example:
#   origins=$(get_distribution_origins "E1234567890ABC" "$PROFILE_ARG")
#   if echo "$origins" | grep -q "my-bucket.s3"; then
#       echo "Distribution references my-bucket"
#   fi
##############################################################################
get_distribution_origins() {
    local dist_id="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$dist_id" ]]; then
        echo -e "${RED}ERROR: Distribution ID is required${NC}" >&2
        return 1
    fi
    
    # Get distribution configuration
    local origins_output
    origins_output=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DistributionConfig.Origins.Items[*].DomainName' \
        --output text \
        $profile_arg 2>&1)
    
    local query_exit_code=$?
    
    if [ $query_exit_code -ne 0 ]; then
        # Distribution might not exist anymore (which is fine during deletion)
        if echo "$origins_output" | grep -q "NoSuchDistribution"; then
            return 0
        fi
        
        echo -e "${RED}ERROR: Failed to get distribution origins${NC}" >&2
        echo -e "${RED}  ${origins_output}${NC}" >&2
        return 1
    fi
    
    # Output origins to stdout
    echo "$origins_output" | tr '\t' '\n'
    return 0
}

##############################################################################
# verify_no_cloudfront_references
#
# Verifies that no CloudFront distributions reference a specific S3 bucket.
#
# This function checks all CloudFront distributions to ensure none of them
# have the specified S3 bucket as an origin. This is critical before deleting
# the bucket to prevent the CloudFront Origin Hijacking vulnerability.
#
# Arguments:
#   $1 - S3 bucket name (required)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - No distributions reference the bucket (safe to delete)
#   1 - Query failed or distributions still reference the bucket
#
# Example:
#   if verify_no_cloudfront_references "my-bucket" "$PROFILE_ARG"; then
#       echo "Safe to delete bucket"
#       aws s3 rb s3://my-bucket --force
#   fi
##############################################################################
verify_no_cloudfront_references() {
    local bucket_name="$1"
    local profile_arg="${2:-}"
    
    if [[ -z "$bucket_name" ]]; then
        echo -e "${RED}ERROR: Bucket name is required${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}Verifying no CloudFront distributions reference bucket: $bucket_name${NC}"
    
    # Get all distributions
    local distributions
    distributions=$(get_cloudfront_distributions "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        return 1
    fi
    
    if [[ -z "$distributions" ]]; then
        echo -e "${GREEN}✓ No CloudFront distributions found${NC}"
        return 0
    fi
    
    # Check each distribution for references to the bucket
    local references_found=false
    
    while IFS=$'\t' read -r dist_id status domain; do
        if [[ -z "$dist_id" ]]; then
            continue
        fi
        
        # Get origins for this distribution
        local origins
        origins=$(get_distribution_origins "$dist_id" "$profile_arg")
        
        # Check if any origin references the bucket
        if echo "$origins" | grep -q "$bucket_name"; then
            echo -e "${RED}✗ Distribution $dist_id references bucket $bucket_name${NC}" >&2
            echo -e "${RED}  Domain: $domain${NC}" >&2
            echo -e "${RED}  Status: $status${NC}" >&2
            references_found=true
        fi
    done <<< "$distributions"
    
    if [ "$references_found" = true ]; then
        echo -e "${RED}✗ CloudFront distributions still reference the bucket${NC}" >&2
        echo -e "${RED}  Cannot safely delete bucket - risk of origin hijacking${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ No CloudFront distributions reference the bucket${NC}"
    return 0
}

##############################################################################
# wait_for_cloudfront_deletion
#
# Waits for all CloudFront distributions to be deleted during stack deletion.
#
# This function polls CloudFront distribution status every 60 seconds during
# stack deletion to ensure all distributions are fully deleted before
# proceeding to S3 bucket deletion. This implements the secure deletion order
# to prevent CloudFront Origin Hijacking.
#
# The function tracks distributions that existed at the start and waits for
# them to be deleted. It uses a 45-minute timeout specific to CloudFront
# deletion operations.
#
# Arguments:
#   $1 - Stack name being deleted (for logging context)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - All CloudFront distributions deleted successfully
#   1 - Deletion failed
#   2 - Timeout waiting for deletion
#
# Example:
#   if wait_for_cloudfront_deletion "serverless-saas-shared-lab6" "$PROFILE_ARG"; then
#       echo "CloudFront distributions deleted, safe to delete S3 buckets"
#   fi
##############################################################################
wait_for_cloudfront_deletion() {
    local stack_name="$1"
    local profile_arg="${2:-}"
    local poll_interval_seconds=60
    local timeout_seconds=$((CLOUDFRONT_TIMEOUT_MINUTES * 60))
    
    if [[ -z "$stack_name" ]]; then
        echo -e "${RED}ERROR: Stack name is required${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}⏳ Monitoring CloudFront distribution deletion (timeout: ${CLOUDFRONT_TIMEOUT_MINUTES} minutes)${NC}"
    echo -e "${YELLOW}⏳ Polling every ${poll_interval_seconds} seconds...${NC}"
    echo ""
    
    # Get initial distribution count
    local initial_distributions
    initial_distributions=$(get_cloudfront_distributions "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        return 1
    fi
    
    if [[ -z "$initial_distributions" ]]; then
        echo -e "${GREEN}✓ No CloudFront distributions to wait for${NC}"
        return 0
    fi
    
    local initial_count=$(echo "$initial_distributions" | wc -l | tr -d ' ')
    echo -e "${BLUE}Initial CloudFront distributions: $initial_count${NC}"
    
    # Extract distribution IDs to track
    local tracked_dist_ids=()
    while IFS=$'\t' read -r dist_id status domain; do
        if [[ -n "$dist_id" ]]; then
            tracked_dist_ids+=("$dist_id")
        fi
    done <<< "$initial_distributions"
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_minutes=$((elapsed / 60))
        local elapsed_seconds=$((elapsed % 60))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            local timeout_msg="Elapsed: ${elapsed_minutes}m ${elapsed_seconds}s, Timeout: ${CLOUDFRONT_TIMEOUT_MINUTES}m"
            echo -e "${YELLOW}⚠ Timeout waiting for CloudFront deletion${NC}" >&2
            echo -e "${YELLOW}  $timeout_msg${NC}" >&2
            echo -e "${YELLOW}  CloudFront distributions may still be deleting${NC}" >&2
            echo -e "${YELLOW}  This is normal - CloudFront deletion can take 15-30 minutes${NC}" >&2
            echo -e "${YELLOW}  Continuing with cleanup - verify manually if needed${NC}" >&2
            return 2
        fi
        
        # Get current distributions
        local current_distributions
        current_distributions=$(get_cloudfront_distributions "$profile_arg")
        get_result=$?
        
        if [ $get_result -ne 0 ]; then
            echo -e "${RED}ERROR: Failed to query CloudFront distributions${NC}" >&2
            return 1
        fi
        
        # Check if all tracked distributions are gone
        local all_deleted=true
        local remaining_count=0
        
        for tracked_id in "${tracked_dist_ids[@]}"; do
            if echo "$current_distributions" | grep -q "$tracked_id"; then
                all_deleted=false
                remaining_count=$((remaining_count + 1))
            fi
        done
        
        if [ "$all_deleted" = true ]; then
            echo -e "${GREEN}✓ All CloudFront distributions deleted successfully${NC}"
            echo -e "${GREEN}  Total time: ${elapsed_minutes}m ${elapsed_seconds}s${NC}"
            return 0
        fi
        
        # Log progress
        echo -e "${YELLOW}  CloudFront distributions remaining: $remaining_count/${initial_count} (${elapsed_minutes}m ${elapsed_seconds}s elapsed)${NC}"
        
        # Show status of remaining distributions
        for tracked_id in "${tracked_dist_ids[@]}"; do
            local dist_info=$(echo "$current_distributions" | grep "$tracked_id")
            if [[ -n "$dist_info" ]]; then
                local status=$(echo "$dist_info" | awk '{print $2}')
                echo -e "${YELLOW}    - $tracked_id: $status${NC}"
            fi
        done
        
        # Wait before next poll
        sleep $poll_interval_seconds
    done
}

##############################################################################
# log_cloudfront_safety_warning
#
# Logs a warning about CloudFront Origin Hijacking vulnerability.
#
# This function provides educational information about the security risk
# of deleting S3 buckets before CloudFront distributions are fully deleted.
#
# Example:
#   log_cloudfront_safety_warning
##############################################################################
log_cloudfront_safety_warning() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}        CLOUDFRONT ORIGIN HIJACKING PREVENTION              ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠ SECURITY WARNING: CloudFront Origin Hijacking Risk${NC}"
    echo ""
    echo -e "${YELLOW}If S3 buckets are deleted BEFORE CloudFront distributions:${NC}"
    echo -e "${YELLOW}1. CloudFront still points to the deleted bucket name${NC}"
    echo -e "${YELLOW}2. An attacker can create a bucket with the same name${NC}"
    echo -e "${YELLOW}3. CloudFront serves the attacker's malicious content${NC}"
    echo -e "${YELLOW}4. This enables phishing, malware distribution, and data theft${NC}"
    echo ""
    echo -e "${GREEN}✓ SECURE DELETION ORDER (implemented in this script):${NC}"
    echo -e "${GREEN}1. Delete CloudFormation stack (deletes CloudFront distributions)${NC}"
    echo -e "${GREEN}2. Wait for CloudFront to be fully deleted (15-30 minutes)${NC}"
    echo -e "${GREEN}3. Delete S3 buckets (now safe - CloudFront is gone)${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

##############################################################################
# verify_cloudfront_safe_for_s3_deletion
#
# High-level function that verifies it's safe to delete S3 buckets.
#
# This is a convenience function that combines all CloudFront safety checks:
# 1. Verifies no CloudFront distributions exist
# 2. If distributions exist, verifies they don't reference the bucket
# 3. Logs security warnings if needed
#
# Arguments:
#   $1 - S3 bucket name (optional, if provided checks specific bucket)
#   $2 - AWS CLI profile argument (optional)
#
# Returns:
#   0 - Safe to delete S3 buckets
#   1 - Not safe to delete (CloudFront distributions still exist)
#
# Example:
#   if verify_cloudfront_safe_for_s3_deletion "my-bucket" "$PROFILE_ARG"; then
#       echo "Safe to delete S3 buckets"
#   else
#       echo "Wait for CloudFront deletion first"
#       exit 1
#   fi
##############################################################################
verify_cloudfront_safe_for_s3_deletion() {
    local bucket_name="${1:-}"
    local profile_arg="${2:-}"
    
    echo -e "${BLUE}Verifying CloudFront safety before S3 deletion...${NC}"
    
    # Get all distributions
    local distributions
    distributions=$(get_cloudfront_distributions "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        return 1
    fi
    
    if [[ -z "$distributions" ]]; then
        echo -e "${GREEN}✓ No CloudFront distributions found - safe to delete S3 buckets${NC}"
        return 0
    fi
    
    # If specific bucket provided, check if it's referenced
    if [[ -n "$bucket_name" ]]; then
        if ! verify_no_cloudfront_references "$bucket_name" "$profile_arg"; then
            log_cloudfront_safety_warning
            return 1
        fi
        return 0
    fi
    
    # No specific bucket - just warn that distributions exist
    local dist_count=$(echo "$distributions" | wc -l | tr -d ' ')
    echo -e "${YELLOW}⚠ Found $dist_count CloudFront distribution(s) still active${NC}" >&2
    echo -e "${YELLOW}  Waiting for CloudFront deletion before S3 cleanup${NC}" >&2
    log_cloudfront_safety_warning
    return 1
}

