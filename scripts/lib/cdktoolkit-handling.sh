#!/bin/bash

# CDKToolkit Shared Resource Handling Module
# This module provides functions to safely handle the CDKToolkit stack
# which is shared between Lab5 and Lab6.
#
# CRITICAL: CDKToolkit is a SHARED resource between Lab5 and Lab6
# Both labs use the same CDK execution role from CDKToolkit
# We can only delete it if BOTH labs are NOT deployed

# Logging functions (inline to avoid dependency on external logging module)
log_info() {
    echo "  $1"
}

log_warning() {
    echo "  ⚠️  $1"
}

log_error() {
    echo "  ✗ $1"
}

log_success() {
    echo "  ✓ $1"
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Check if Lab5 pipeline stack exists
# Returns: 0 if exists, 1 if not exists
check_lab5_pipeline_exists() {
    local profile_arg="$1"
    local region="${2:-us-east-1}"
    
    log_info "Checking for Lab5 pipeline stack..."
    
    # Check for Lab5 pipeline stack
    local lab5_pipeline
    lab5_pipeline=$(aws cloudformation $profile_arg describe-stacks \
        --region "$region" \
        --query "Stacks[?StackName=='serverless-saas-pipeline-lab5'].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lab5_pipeline" ]]; then
        log_info "Lab5 pipeline stack found: $lab5_pipeline"
        return 0
    fi
    
    # Also check for Lab5 shared stack as a secondary indicator
    local lab5_shared
    lab5_shared=$(aws cloudformation $profile_arg describe-stacks \
        --region "$region" \
        --query "Stacks[?StackName=='serverless-saas-shared-lab5'].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lab5_shared" ]]; then
        log_info "Lab5 shared stack found: $lab5_shared"
        return 0
    fi
    
    log_info "Lab5 is not deployed"
    return 1
}

# Check if Lab6 pipeline stack exists
# Returns: 0 if exists, 1 if not exists
check_lab6_pipeline_exists() {
    local profile_arg="$1"
    local region="${2:-us-east-1}"
    
    log_info "Checking for Lab6 pipeline stack..."
    
    # Check for Lab6 pipeline stack
    local lab6_pipeline
    lab6_pipeline=$(aws cloudformation $profile_arg describe-stacks \
        --region "$region" \
        --query "Stacks[?StackName=='serverless-saas-pipeline-lab6'].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lab6_pipeline" ]]; then
        log_info "Lab6 pipeline stack found: $lab6_pipeline"
        return 0
    fi
    
    # Also check for Lab6 shared stack as a secondary indicator
    local lab6_shared
    lab6_shared=$(aws cloudformation $profile_arg describe-stacks \
        --region "$region" \
        --query "Stacks[?StackName=='serverless-saas-shared-lab6'].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lab6_shared" ]]; then
        log_info "Lab6 shared stack found: $lab6_shared"
        return 0
    fi
    
    log_info "Lab6 is not deployed"
    return 1
}

# Determine if CDKToolkit can be safely deleted
# For Lab5 cleanup: Check if Lab6 exists
# For Lab6 cleanup: Check if Lab5 exists
# Returns: 0 if safe to delete, 1 if should skip
can_delete_cdktoolkit() {
    local current_lab="$1"  # "lab5" or "lab6"
    local profile_arg="$2"
    local region="${3:-us-east-1}"
    
    log_info "Checking if CDKToolkit can be safely deleted for $current_lab cleanup..."
    
    if [[ "$current_lab" == "lab5" ]]; then
        # Lab5 cleanup: Check if Lab6 exists
        if check_lab6_pipeline_exists "$profile_arg" "$region"; then
            log_warning "Lab6 is still deployed - CDKToolkit is in use"
            return 1
        fi
    elif [[ "$current_lab" == "lab6" ]]; then
        # Lab6 cleanup: Check if Lab5 exists
        if check_lab5_pipeline_exists "$profile_arg" "$region"; then
            log_warning "Lab5 is still deployed - CDKToolkit is in use"
            return 1
        fi
    else
        log_error "Invalid lab identifier: $current_lab (must be 'lab5' or 'lab6')"
        return 1
    fi
    
    log_success "No other lab is using CDKToolkit - safe to delete"
    return 0
}

# Log skip warning with explanation
# This function provides clear explanation of why CDKToolkit deletion was skipped
log_cdktoolkit_skip_warning() {
    local current_lab="$1"  # "lab5" or "lab6"
    local other_lab="$2"    # "Lab5" or "Lab6"
    
    log_warning "⚠️  Skipping CDKToolkit stack deletion - $other_lab is still deployed"
    log_warning "   $other_lab pipeline stack uses the shared CDK execution role from CDKToolkit"
    log_warning "   CDKToolkit will be deleted when $other_lab is cleaned up"
    log_warning ""
    log_warning "Why CDKToolkit is shared:"
    log_warning "   - Both Lab5 and Lab6 use AWS CDK for infrastructure deployment"
    log_warning "   - CDK bootstrap creates a CDKToolkit stack with execution roles"
    log_warning "   - These roles are used by both labs' pipeline stacks"
    log_warning "   - Deleting CDKToolkit while a lab is deployed would break that lab"
    log_warning ""
    log_warning "When CDKToolkit will be deleted:"
    log_warning "   - After both Lab5 AND Lab6 are cleaned up"
    log_warning "   - The last lab to be cleaned up will delete CDKToolkit"
    log_warning ""
    log_warning "To manually delete CDKToolkit:"
    log_warning "   1. Ensure both Lab5 and Lab6 are fully cleaned up"
    log_warning "   2. Run: aws cloudformation delete-stack --stack-name CDKToolkit"
    log_warning "   3. Wait for deletion: aws cloudformation wait stack-delete-complete --stack-name CDKToolkit"
}

# Main function to handle CDKToolkit deletion decision
# Returns: 0 if CDKToolkit was deleted or skipped successfully, 1 on error
handle_cdktoolkit_deletion() {
    local current_lab="$1"  # "lab5" or "lab6"
    local profile_arg="$2"
    local region="${3:-us-east-1}"
    
    log_section "CDKToolkit Shared Resource Handling"
    
    # Determine the other lab name for messaging
    local other_lab
    if [[ "$current_lab" == "lab5" ]]; then
        other_lab="Lab6"
    else
        other_lab="Lab5"
    fi
    
    # Check if CDKToolkit can be safely deleted
    if can_delete_cdktoolkit "$current_lab" "$profile_arg" "$region"; then
        log_success "✓ $other_lab is not deployed - safe to delete CDKToolkit"
        return 0  # Caller should proceed with deletion
    else
        log_cdktoolkit_skip_warning "$current_lab" "$other_lab"
        return 1  # Caller should skip deletion
    fi
}

# Export functions for use in other scripts
export -f check_lab5_pipeline_exists
export -f check_lab6_pipeline_exists
export -f can_delete_cdktoolkit
export -f log_cdktoolkit_skip_warning
export -f handle_cdktoolkit_deletion
