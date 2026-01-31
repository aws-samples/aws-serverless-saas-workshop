#!/bin/bash

################################################################################
# Parallel Deletion Module
#
# Feature: lab-cleanup-isolation-all-labs
# Module: parallel-deletion.sh
#
# This module provides safe parallel deletion of independent AWS resources
# while maintaining proper dependency ordering for dependent resources.
#
# Requirements: 12.1, 12.2, 12.3, 12.4, 12.5
################################################################################

# Minimal logging functions if not already defined
if ! declare -f log_info &>/dev/null; then
    log_info() {
        echo "[INFO] $*"
    }
    
    log_success() {
        echo "[SUCCESS] $*"
    }
    
    log_warning() {
        echo "[WARNING] $*"
    }
    
    log_error() {
        echo "[ERROR] $*" >&2
    }
fi

################################################################################
# Global Variables
################################################################################

# Array to track background process IDs
declare -a PARALLEL_PIDS=()

# Array to track background process descriptions
declare -a PARALLEL_DESCRIPTIONS=()

# Array to track background process exit codes
declare -a PARALLEL_EXIT_CODES=()

################################################################################
# Function: delete_stacks_parallel
#
# Delete multiple CloudFormation stacks in parallel
#
# Arguments:
#   $@ - Stack names to delete
#
# Returns:
#   0 if all deletions succeeded
#   1 if any deletion failed
################################################################################
delete_stacks_parallel() {
    local stack_names=("$@")
    
    if [ ${#stack_names[@]} -eq 0 ]; then
        log_info "No stacks to delete"
        return 0
    fi
    
    log_info "Deleting ${#stack_names[@]} stacks in parallel..."
    
    # Reset parallel tracking arrays
    PARALLEL_PIDS=()
    PARALLEL_DESCRIPTIONS=()
    PARALLEL_EXIT_CODES=()
    
    # Start deletion for each stack in background
    for stack_name in "${stack_names[@]}"; do
        (
            log_info "  Starting deletion: $stack_name"
            
            # Initiate stack deletion
            if ! aws cloudformation delete-stack \
                --stack-name "$stack_name" \
                --region "${AWS_REGION:-us-east-1}" \
                ${PROFILE_ARG} 2>&1; then
                log_error "Failed to initiate deletion for stack: $stack_name"
                exit 1
            fi
            
            # Wait for deletion to complete
            if ! aws cloudformation wait stack-delete-complete \
                --stack-name "$stack_name" \
                --region "${AWS_REGION:-us-east-1}" \
                ${PROFILE_ARG} 2>&1; then
                log_error "Stack deletion failed or timed out: $stack_name"
                exit 1
            fi
            
            log_success "  Completed deletion: $stack_name"
            exit 0
        ) &
        
        local pid=$!
        PARALLEL_PIDS+=("$pid")
        PARALLEL_DESCRIPTIONS+=("Stack deletion: $stack_name")
    done
    
    # Wait for all deletions to complete
    wait_for_parallel_operations
}

################################################################################
# Function: empty_buckets_parallel
#
# Empty multiple S3 buckets in parallel (but don't delete them yet)
#
# Arguments:
#   $@ - Bucket names to empty
#
# Returns:
#   0 if all operations succeeded
#   1 if any operation failed
################################################################################
empty_buckets_parallel() {
    local bucket_names=("$@")
    
    if [ ${#bucket_names[@]} -eq 0 ]; then
        log_info "No buckets to empty"
        return 0
    fi
    
    log_info "Emptying ${#bucket_names[@]} buckets in parallel..."
    
    # Reset parallel tracking arrays
    PARALLEL_PIDS=()
    PARALLEL_DESCRIPTIONS=()
    PARALLEL_EXIT_CODES=()
    
    # Start emptying each bucket in background
    for bucket_name in "${bucket_names[@]}"; do
        (
            log_info "  Starting to empty: $bucket_name"
            
            # Check if bucket exists
            if ! aws s3 ls "s3://$bucket_name" \
                --region "${AWS_REGION:-us-east-1}" \
                ${PROFILE_ARG} &>/dev/null; then
                log_warning "  Bucket does not exist: $bucket_name"
                exit 0
            fi
            
            # Empty the bucket
            if ! aws s3 rm "s3://$bucket_name" \
                --recursive \
                --region "${AWS_REGION:-us-east-1}" \
                ${PROFILE_ARG} 2>&1; then
                log_error "Failed to empty bucket: $bucket_name"
                exit 1
            fi
            
            log_success "  Completed emptying: $bucket_name"
            exit 0
        ) &
        
        local pid=$!
        PARALLEL_PIDS+=("$pid")
        PARALLEL_DESCRIPTIONS+=("Bucket emptying: $bucket_name")
    done
    
    # Wait for all operations to complete
    wait_for_parallel_operations
}

################################################################################
# Function: delete_buckets_sequential
#
# Delete multiple S3 buckets sequentially (after they've been emptied)
#
# Arguments:
#   $@ - Bucket names to delete
#
# Returns:
#   0 if all deletions succeeded
#   1 if any deletion failed
################################################################################
delete_buckets_sequential() {
    local bucket_names=("$@")
    local failed=0
    
    if [ ${#bucket_names[@]} -eq 0 ]; then
        log_info "No buckets to delete"
        return 0
    fi
    
    log_info "Deleting ${#bucket_names[@]} buckets sequentially..."
    
    # Delete each bucket one at a time
    for bucket_name in "${bucket_names[@]}"; do
        log_info "  Deleting bucket: $bucket_name"
        
        # Check if bucket exists
        if ! aws s3 ls "s3://$bucket_name" \
            --region "${AWS_REGION:-us-east-1}" \
            ${PROFILE_ARG} &>/dev/null; then
            log_warning "  Bucket does not exist: $bucket_name"
            continue
        fi
        
        # Delete the bucket
        if ! aws s3 rb "s3://$bucket_name" \
            --region "${AWS_REGION:-us-east-1}" \
            ${PROFILE_ARG} 2>&1; then
            log_error "Failed to delete bucket: $bucket_name"
            failed=1
        else
            log_success "  Deleted bucket: $bucket_name"
        fi
    done
    
    return $failed
}

################################################################################
# Function: delete_log_groups_parallel
#
# Delete multiple CloudWatch log groups in parallel
#
# Arguments:
#   $@ - Log group names to delete
#
# Returns:
#   0 if all deletions succeeded
#   1 if any deletion failed
################################################################################
delete_log_groups_parallel() {
    local log_group_names=("$@")
    
    if [ ${#log_group_names[@]} -eq 0 ]; then
        log_info "No log groups to delete"
        return 0
    fi
    
    log_info "Deleting ${#log_group_names[@]} log groups in parallel..."
    
    # Reset parallel tracking arrays
    PARALLEL_PIDS=()
    PARALLEL_DESCRIPTIONS=()
    PARALLEL_EXIT_CODES=()
    
    # Start deletion for each log group in background
    for log_group_name in "${log_group_names[@]}"; do
        (
            log_info "  Starting deletion: $log_group_name"
            
            # Delete the log group
            if ! aws logs delete-log-group \
                --log-group-name "$log_group_name" \
                --region "${AWS_REGION:-us-east-1}" \
                ${PROFILE_ARG} 2>&1; then
                log_error "Failed to delete log group: $log_group_name"
                exit 1
            fi
            
            log_success "  Completed deletion: $log_group_name"
            exit 0
        ) &
        
        local pid=$!
        PARALLEL_PIDS+=("$pid")
        PARALLEL_DESCRIPTIONS+=("Log group deletion: $log_group_name")
    done
    
    # Wait for all deletions to complete
    wait_for_parallel_operations
}

################################################################################
# Function: wait_for_parallel_operations
#
# Wait for all background operations to complete and collect exit codes
#
# Returns:
#   0 if all operations succeeded
#   1 if any operation failed
################################################################################
wait_for_parallel_operations() {
    local failed=0
    local total=${#PARALLEL_PIDS[@]}
    
    if [ $total -eq 0 ]; then
        return 0
    fi
    
    log_info "Waiting for $total parallel operations to complete..."
    
    # Wait for each process and collect exit codes
    for i in "${!PARALLEL_PIDS[@]}"; do
        local pid="${PARALLEL_PIDS[$i]}"
        local description="${PARALLEL_DESCRIPTIONS[$i]}"
        
        # Wait for the process
        if wait "$pid"; then
            PARALLEL_EXIT_CODES[$i]=0
            log_success "  ✓ $description"
        else
            local exit_code=$?
            PARALLEL_EXIT_CODES[$i]=$exit_code
            log_error "  ✗ $description (exit code: $exit_code)"
            failed=1
        fi
    done
    
    # Summary
    if [ $failed -eq 0 ]; then
        log_success "All $total parallel operations completed successfully"
    else
        local failed_count=0
        for exit_code in "${PARALLEL_EXIT_CODES[@]}"; do
            if [ "$exit_code" -ne 0 ]; then
                ((failed_count++))
            fi
        done
        log_error "$failed_count of $total parallel operations failed"
    fi
    
    return $failed
}

################################################################################
# Function: cleanup_parallel_processes
#
# Clean up any remaining background processes (call on script exit)
#
# Returns:
#   None
################################################################################
cleanup_parallel_processes() {
    if [ ${#PARALLEL_PIDS[@]} -gt 0 ]; then
        log_warning "Cleaning up ${#PARALLEL_PIDS[@]} background processes..."
        
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                log_info "  Terminating process: $pid"
                kill "$pid" 2>/dev/null || true
            fi
        done
        
        # Wait a moment for processes to terminate
        sleep 1
        
        # Force kill any remaining processes
        for pid in "${PARALLEL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                log_warning "  Force killing process: $pid"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
}

# Register cleanup handler
trap cleanup_parallel_processes EXIT INT TERM
