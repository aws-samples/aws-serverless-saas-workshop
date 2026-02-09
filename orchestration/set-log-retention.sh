#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# =============================================================================
# AWS Serverless SaaS Workshop - Set Log Group Retention and Tags Script
# =============================================================================
# This script sets retention policies and tags on CloudWatch Log Groups after
# CloudFormation deployment completes.
#
# APPROACH:
#   CloudFormation creates log groups (without retention/tags to avoid race condition)
#   This script runs post-deployment to add:
#   - 60-day retention policy
#   - Consistent tags for cost allocation and resource tracking
#
# FEATURES:
#   - Parallel execution for fast processing
#   - Configurable retention period (default: 60 days)
#   - Pattern matching for log group names
#   - Adds tags for Application, Lab, Environment, Owner, CostCenter
#   - Idempotent - safe to run multiple times
#   - Detects and configures ALL log groups (Lambda, API Gateway, etc.)
#
# USAGE:
#   ./set-log-retention.sh --profile <aws-profile> [OPTIONS]
#
# CRITICAL: Execute this script directly (./set-log-retention.sh), NEVER with bash command
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
# DEFAULT CONFIGURATION
# =============================================================================
DEFAULT_REGION="us-east-1"
DEFAULT_RETENTION_DAYS=60
DEFAULT_PATTERN="/aws/lambda/serverless-saas"
MAX_PARALLEL_JOBS=10

# Tag values
TAG_APPLICATION="serverless-saas-workshop"
TAG_ENVIRONMENT="dev"
TAG_OWNER="workshop-participant"
TAG_COST_CENTER="serverless-saas-workshop"

# =============================================================================
# VARIABLES
# =============================================================================
PROFILE=""
REGION="$DEFAULT_REGION"
RETENTION_DAYS="$DEFAULT_RETENTION_DAYS"
PATTERN="$DEFAULT_PATTERN"
VERBOSE=false
ALL_LOGS=false
TAG_FILTERS=()
TAG_RETENTION_DAYS=90
USE_TAG_MODE=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_info() {
    print_message "$GREEN" "$1"
}

log_warn() {
    print_message "$YELLOW" "$1"
}

log_error() {
    print_message "$RED" "$1"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        print_message "$CYAN" "$1"
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
AWS Serverless SaaS Workshop - Set Log Group Retention and Tags Script

USAGE:
    ./set-log-retention.sh --profile <aws-profile> [OPTIONS]

REQUIRED:
    --profile <profile>         AWS CLI profile name (REQUIRED)

OPTIONS:
    --region <region>           AWS region (default: $DEFAULT_REGION)
    --retention <days>          Retention period in days (default: $DEFAULT_RETENTION_DAYS)
    --pattern <pattern>         Log group name pattern to match (default: $DEFAULT_PATTERN)
    --all                       Process ALL serverless-saas log groups (Lambda + API Gateway + others)
    --by-tag <key=value>        Set retention on log groups with specific tag (can use multiple times)
    --tag-retention <days>      Retention period for tag-based filtering (default: 90 days)
    --verbose                   Enable verbose output
    --help                      Show this help message

EXAMPLES:
    # Set 60-day retention on all serverless-saas Lambda log groups
    ./set-log-retention.sh --profile my-profile

    # Set retention on ALL serverless-saas log groups (including API Gateway)
    ./set-log-retention.sh --profile my-profile --all

    # Set 30-day retention with custom pattern
    ./set-log-retention.sh --profile my-profile --retention 30 --pattern "/aws/lambda/my-app"

    # Set 90-day retention on log groups with specific tag
    ./set-log-retention.sh --profile my-profile --by-tag "Application=serverless-saas-workshop"

    # Set 90-day retention on log groups matching any of multiple tags
    ./set-log-retention.sh --profile my-profile --by-tag "Environment=prod" --by-tag "CostCenter=my-team"

    # Set custom retention (120 days) on tagged log groups
    ./set-log-retention.sh --profile my-profile --by-tag "Application=serverless-saas-workshop" --tag-retention 120

    # Verbose output for debugging
    ./set-log-retention.sh --profile my-profile --verbose

CRITICAL:
    - Execute this script directly: ./set-log-retention.sh
    - NEVER run with bash command: bash set-log-retention.sh (WILL FAIL)

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --profile requires a value"; exit 1; }
                PROFILE="$2"; shift 2 ;;
            --region)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --region requires a value"; exit 1; }
                REGION="$2"; shift 2 ;;
            --retention)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --retention requires a value"; exit 1; }
                RETENTION_DAYS="$2"; shift 2 ;;
            --pattern)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --pattern requires a value"; exit 1; }
                PATTERN="$2"; shift 2 ;;
            --by-tag)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --by-tag requires a value (format: key=value)"; exit 1; }
                TAG_FILTERS+=("$2")
                USE_TAG_MODE=true
                shift 2 ;;
            --tag-retention)
                [[ -z "$2" || "$2" == --* ]] && { log_error "ERROR: --tag-retention requires a value"; exit 1; }
                TAG_RETENTION_DAYS="$2"; shift 2 ;;
            --all) ALL_LOGS=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --help) show_help ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Validate required parameters
    [[ -z "$PROFILE" ]] && { log_error "ERROR: --profile is required"; exit 1; }
    
    # Validate retention is a number
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        log_error "ERROR: --retention must be a positive integer"
        exit 1
    fi
    
    # Validate tag retention is a number
    if ! [[ "$TAG_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        log_error "ERROR: --tag-retention must be a positive integer"
        exit 1
    fi
    
    # Validate tag filters format
    for filter in "${TAG_FILTERS[@]}"; do
        if [[ ! "$filter" =~ ^[^=]+=.+$ ]]; then
            log_error "ERROR: Invalid tag filter format: $filter (expected: key=value)"
            exit 1
        fi
    done
}

# =============================================================================
# EXTRACT LAB NUMBER FROM LOG GROUP NAME
# =============================================================================

get_lab_from_log_group() {
    local log_group_name=$1
    
    # Extract lab number from log group name
    # Patterns: serverless-saas-lab1, serverless-saas-lab2, etc.
    if [[ "$log_group_name" =~ lab([0-9]+) ]]; then
        echo "lab${BASH_REMATCH[1]}"
    else
        echo "shared"
    fi
}

# =============================================================================
# SET RETENTION AND TAGS ON SINGLE LOG GROUP
# =============================================================================

process_log_group() {
    local log_group_name=$1
    local retention_days=$2
    local lab_tag
    
    # Get lab tag from log group name
    lab_tag=$(get_lab_from_log_group "$log_group_name")
    
    local success=true
    local status_msg=""
    
    # Set retention policy
    if aws logs put-retention-policy \
        --log-group-name "$log_group_name" \
        --retention-in-days "$retention_days" \
        --profile "$PROFILE" \
        --region "$REGION" 2>/dev/null; then
        status_msg="retention:✓"
    else
        status_msg="retention:✗"
        success=false
    fi
    
    # Add tags
    if aws logs tag-log-group \
        --log-group-name "$log_group_name" \
        --tags "Application=$TAG_APPLICATION,Lab=$lab_tag,Environment=$TAG_ENVIRONMENT,Owner=$TAG_OWNER,CostCenter=$TAG_COST_CENTER" \
        --profile "$PROFILE" \
        --region "$REGION" 2>/dev/null; then
        status_msg="$status_msg tags:✓"
    else
        status_msg="$status_msg tags:✗"
        success=false
    fi
    
    if [[ "$success" == true ]]; then
        echo "✓ $log_group_name [$lab_tag] ($status_msg)"
        return 0
    else
        echo "⚠ $log_group_name [$lab_tag] ($status_msg)"
        return 1
    fi
}

# =============================================================================
# SET 90-DAY RETENTION ON LOG GROUPS WITH SPECIFIC TAGS
# =============================================================================

set_retention_by_tags() {
    local tag_key=$1
    local tag_value=$2
    local retention_days=${3:-90}
    
    log_info "Finding log groups with tag $tag_key=$tag_value..."
    
    # Get all log groups
    local all_log_groups
    all_log_groups=$(aws logs describe-log-groups \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "logGroups[*].logGroupName" \
        --output text 2>/dev/null | tr '\t' '\n')
    
    if [[ -z "$all_log_groups" ]]; then
        log_warn "No log groups found in the account"
        return 0
    fi
    
    local matched_count=0
    local success_count=0
    local fail_count=0
    
    while IFS= read -r log_group; do
        [[ -z "$log_group" ]] && continue
        
        # Get tags for this log group
        local tags
        tags=$(aws logs list-tags-log-group \
            --log-group-name "$log_group" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "tags" \
            --output json 2>/dev/null || echo "{}")
        
        # Check if the tag matches
        local tag_match
        tag_match=$(echo "$tags" | jq -r --arg key "$tag_key" --arg val "$tag_value" '.[$key] // empty | select(. == $val)' 2>/dev/null || echo "")
        
        if [[ -n "$tag_match" ]]; then
            ((matched_count++))
            
            # Set retention policy
            if aws logs put-retention-policy \
                --log-group-name "$log_group" \
                --retention-in-days "$retention_days" \
                --profile "$PROFILE" \
                --region "$REGION" 2>/dev/null; then
                echo "✓ $log_group - retention set to $retention_days days"
                ((success_count++))
            else
                echo "✗ $log_group - failed to set retention"
                ((fail_count++))
            fi
        fi
    done <<< "$all_log_groups"
    
    echo ""
    log_info "Tag-based retention summary:"
    log_info "  Log groups with tag $tag_key=$tag_value: $matched_count"
    log_info "  Successfully updated: $success_count"
    if [[ $fail_count -gt 0 ]]; then
        log_warn "  Failed: $fail_count"
    fi
    
    return 0
}

# =============================================================================
# SET 90-DAY RETENTION ON LOG GROUPS WITH ANY MATCHING TAG
# =============================================================================

set_retention_by_any_tag() {
    local retention_days=${1:-90}
    shift
    local tag_filters=("$@")
    
    if [[ ${#tag_filters[@]} -eq 0 ]]; then
        log_error "ERROR: At least one tag filter required (format: key=value)"
        return 1
    fi
    
    log_info "Finding log groups matching any of the specified tags..."
    
    # Get all log groups
    local all_log_groups
    all_log_groups=$(aws logs describe-log-groups \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query "logGroups[*].logGroupName" \
        --output text 2>/dev/null | tr '\t' '\n')
    
    if [[ -z "$all_log_groups" ]]; then
        log_warn "No log groups found in the account"
        return 0
    fi
    
    local matched_count=0
    local success_count=0
    local fail_count=0
    
    while IFS= read -r log_group; do
        [[ -z "$log_group" ]] && continue
        
        # Get tags for this log group
        local tags
        tags=$(aws logs list-tags-log-group \
            --log-group-name "$log_group" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "tags" \
            --output json 2>/dev/null || echo "{}")
        
        # Check if any tag filter matches
        local matched=false
        for filter in "${tag_filters[@]}"; do
            local tag_key="${filter%%=*}"
            local tag_value="${filter#*=}"
            
            local tag_match
            tag_match=$(echo "$tags" | jq -r --arg key "$tag_key" --arg val "$tag_value" '.[$key] // empty | select(. == $val)' 2>/dev/null || echo "")
            
            if [[ -n "$tag_match" ]]; then
                matched=true
                break
            fi
        done
        
        if [[ "$matched" == true ]]; then
            ((matched_count++))
            
            # Set retention policy
            if aws logs put-retention-policy \
                --log-group-name "$log_group" \
                --retention-in-days "$retention_days" \
                --profile "$PROFILE" \
                --region "$REGION" 2>/dev/null; then
                echo "✓ $log_group - retention set to $retention_days days"
                ((success_count++))
            else
                echo "✗ $log_group - failed to set retention"
                ((fail_count++))
            fi
        fi
    done <<< "$all_log_groups"
    
    echo ""
    log_info "Tag-based retention summary:"
    log_info "  Log groups matching tags: $matched_count"
    log_info "  Successfully updated: $success_count"
    if [[ $fail_count -gt 0 ]]; then
        log_warn "  Failed: $fail_count"
    fi
    
    return 0
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    parse_arguments "$@"
    
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "Setting CloudWatch Log Group Retention & Tags"
    print_message "$BLUE" "========================================"
    echo ""
    
    log_info "Profile: $PROFILE"
    log_info "Region: $REGION"
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity --profile "$PROFILE" &> /dev/null; then
        log_error "ERROR: AWS profile '$PROFILE' is not configured or credentials are invalid"
        exit 1
    fi
    
    # Check if tag-based mode is enabled
    if [[ "$USE_TAG_MODE" == true ]]; then
        log_info "Mode: Tag-based retention"
        log_info "Tag retention: $TAG_RETENTION_DAYS days"
        log_info "Tag filters: ${TAG_FILTERS[*]}"
        echo ""
        
        set_retention_by_any_tag "$TAG_RETENTION_DAYS" "${TAG_FILTERS[@]}"
        
        echo ""
        log_info "✓ Tag-based log retention configuration complete"
        exit 0
    fi
    
    # Standard mode (pattern-based)
    log_info "Retention: $RETENTION_DAYS days"
    if [[ "$ALL_LOGS" == true ]]; then
        log_info "Mode: ALL serverless-saas log groups"
    else
        log_info "Pattern: $PATTERN*"
    fi
    echo ""
    
    # Find all matching log groups
    log_info "Finding log groups..."
    
    local log_groups=""
    
    if [[ "$ALL_LOGS" == true ]]; then
        # Find ALL serverless-saas log groups (Lambda, API Gateway, etc.)
        # Pattern 1: Lambda logs - /aws/lambda/serverless-saas*
        local lambda_logs
        lambda_logs=$(aws logs describe-log-groups \
            --log-group-name-prefix "/aws/lambda/serverless-saas" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "logGroups[*].logGroupName" \
            --output text 2>/dev/null | tr '\t' '\n' || echo "")
        
        # Pattern 2: API Gateway logs - /aws/api-gateway/*serverless-saas*
        local apigw_logs
        apigw_logs=$(aws logs describe-log-groups \
            --log-group-name-prefix "/aws/api-gateway/" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "logGroups[?contains(logGroupName, 'serverless-saas')].logGroupName" \
            --output text 2>/dev/null | tr '\t' '\n' || echo "")
        
        # Pattern 3: Other logs with serverless-saas pattern (CodeBuild, etc.)
        local other_logs
        other_logs=$(aws logs describe-log-groups \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "logGroups[?contains(logGroupName, 'serverless-saas') && !starts_with(logGroupName, '/aws/lambda/') && !starts_with(logGroupName, '/aws/api-gateway/')].logGroupName" \
            --output text 2>/dev/null | tr '\t' '\n' || echo "")
        
        # Combine all log groups
        log_groups=$(echo -e "${lambda_logs}\n${apigw_logs}\n${other_logs}" | grep -v '^$' | sort -u)
    else
        # Find log groups matching the pattern
        log_groups=$(aws logs describe-log-groups \
            --log-group-name-prefix "$PATTERN" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "logGroups[*].logGroupName" \
            --output text 2>/dev/null | tr '\t' '\n')
    fi
    
    if [[ -z "$log_groups" ]]; then
        log_warn "No log groups found."
        log_info "This is normal if:"
        log_info "  - Lambda functions haven't been invoked yet"
        log_info "  - CloudFormation deployment is still in progress"
        log_info "  - Log groups will be created when functions are first invoked"
        exit 0
    fi
    
    # Count log groups
    local total_count
    total_count=$(echo "$log_groups" | wc -l | tr -d ' ')
    log_info "Found $total_count log groups"
    echo ""
    
    # Process log groups in parallel
    log_info "Setting retention ($RETENTION_DAYS days) and tags (parallel processing)..."
    echo ""
    
    local success_count=0
    local fail_count=0
    local pids=()
    local results_file
    results_file=$(mktemp)
    
    # Process in batches to limit parallelism
    local batch_count=0
    
    while IFS= read -r log_group; do
        [[ -z "$log_group" ]] && continue
        
        # Run in background
        (
            if process_log_group "$log_group" "$RETENTION_DAYS"; then
                echo "SUCCESS" >> "$results_file"
            else
                echo "FAIL" >> "$results_file"
            fi
        ) &
        
        pids+=($!)
        ((batch_count++))
        
        # Wait for batch to complete if we hit the limit
        if [[ $batch_count -ge $MAX_PARALLEL_JOBS ]]; then
            for pid in "${pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
            pids=()
            batch_count=0
        fi
    done <<< "$log_groups"
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Count results
    if [[ -f "$results_file" ]]; then
        success_count=$(grep -c "SUCCESS" "$results_file" 2>/dev/null | tr -d '[:space:]' || echo "0")
        fail_count=$(grep -c "FAIL" "$results_file" 2>/dev/null | tr -d '[:space:]' || echo "0")
        rm -f "$results_file"
    fi
    
    # Ensure counts are valid integers
    [[ -z "$success_count" || ! "$success_count" =~ ^[0-9]+$ ]] && success_count=0
    [[ -z "$fail_count" || ! "$fail_count" =~ ^[0-9]+$ ]] && fail_count=0
    
    echo ""
    log_info "========================================"
    log_info "Summary"
    log_info "========================================"
    log_info "Total log groups: $total_count"
    log_info "Successfully updated: $success_count"
    
    if [[ $fail_count -gt 0 ]]; then
        log_warn "Partial failures: $fail_count"
        log_warn "Some operations may have failed (check output above)"
    fi
    
    echo ""
    log_info "Tags applied:"
    log_info "  Application: $TAG_APPLICATION"
    log_info "  Environment: $TAG_ENVIRONMENT"
    log_info "  Owner: $TAG_OWNER"
    log_info "  CostCenter: $TAG_COST_CENTER"
    log_info "  Lab: (auto-detected from log group name)"
    
    echo ""
    log_info "✓ Log retention and tags configuration complete"
}

main "$@"
