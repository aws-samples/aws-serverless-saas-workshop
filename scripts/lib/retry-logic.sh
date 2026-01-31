#!/bin/bash

# Retry Logic with Exponential Backoff Module
#
# This module provides retry logic for handling transient AWS API failures
# such as throttling and network errors. It implements exponential backoff
# to avoid overwhelming AWS services during temporary issues.
#
# Key Features:
# - Detects retryable errors (throttling, network errors)
# - Implements exponential backoff (2s, 4s, 8s)
# - Logs retry attempts with attempt number and reason
# - Enforces max retry limit (3 attempts)
# - Logs final error if all retries fail
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"
#   execute_with_retry aws cloudformation describe-stacks --stack-name my-stack
#   if is_retryable_error "$error_output"; then
#       echo "Error is retryable"
#   fi

# Color codes for output (if not already defined)
if [[ -z "$RED" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Global variables for retry tracking
RETRY_ATTEMPT=0
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_BACKOFF=2  # seconds

##############################################################################
# is_retryable_error
#
# Determines if an error message indicates a retryable failure.
#
# This function checks error messages for patterns that indicate transient
# failures that are likely to succeed on retry, such as:
# - AWS API throttling errors
# - Network connectivity issues
# - Temporary service unavailability
#
# Arguments:
#   $1 - Error message or output from AWS CLI (required)
#
# Returns:
#   0 - Error is retryable (should retry)
#   1 - Error is not retryable (permanent failure)
#
# Example:
#   if is_retryable_error "$error_output"; then
#       echo "Will retry this operation"
#   else
#       echo "Permanent failure, will not retry"
#   fi
##############################################################################
is_retryable_error() {
    local error_message="$1"
    
    if [[ -z "$error_message" ]]; then
        return 1  # No error message means not retryable
    fi
    
    # Convert to lowercase for case-insensitive matching
    local error_lower=$(echo "$error_message" | tr '[:upper:]' '[:lower:]')
    
    # Check for throttling errors
    if [[ "$error_lower" == *"throttling"* ]] || \
       [[ "$error_lower" == *"throttled"* ]] || \
       [[ "$error_lower" == *"toomanyrequests"* ]] || \
       [[ "$error_lower" == *"too many requests"* ]] || \
       [[ "$error_lower" == *"rate exceeded"* ]] || \
       [[ "$error_lower" == *"requestlimitexceeded"* ]]; then
        return 0  # Retryable
    fi
    
    # Check for network errors
    if [[ "$error_lower" == *"connection"* ]] || \
       [[ "$error_lower" == *"timeout"* ]] || \
       [[ "$error_lower" == *"timed out"* ]] || \
       [[ "$error_lower" == *"network"* ]] || \
       [[ "$error_lower" == *"could not connect"* ]] || \
       [[ "$error_lower" == *"connection reset"* ]] || \
       [[ "$error_lower" == *"connection refused"* ]]; then
        return 0  # Retryable
    fi
    
    # Check for temporary service unavailability
    if [[ "$error_lower" == *"serviceunavailable"* ]] || \
       [[ "$error_lower" == *"service unavailable"* ]] || \
       [[ "$error_lower" == *"temporarily unavailable"* ]] || \
       [[ "$error_lower" == *"internal error"* ]] || \
       [[ "$error_lower" == *"internalerror"* ]]; then
        return 0  # Retryable
    fi
    
    # Not a retryable error
    return 1
}

##############################################################################
# log_retry_attempt
#
# Logs information about a retry attempt.
#
# This function provides detailed logging about retry attempts, including
# the attempt number, reason for retry, and backoff duration.
#
# Arguments:
#   $1 - Retry attempt number (1-based, required)
#   $2 - Max retry attempts (required)
#   $3 - Backoff duration in seconds (required)
#   $4 - Reason for retry (error message, required)
#
# Example:
#   log_retry_attempt 1 3 2 "Throttling error"
##############################################################################
log_retry_attempt() {
    local attempt="$1"
    local max_attempts="$2"
    local backoff_seconds="$3"
    local reason="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${YELLOW}[${timestamp}] Retry attempt ${attempt}/${max_attempts}${NC}"
    echo -e "${YELLOW}  Reason: ${reason}${NC}"
    echo -e "${YELLOW}  Waiting ${backoff_seconds} seconds before retry...${NC}"
}

##############################################################################
# log_retry_exhausted
#
# Logs that all retry attempts have been exhausted.
#
# This function is called when the maximum number of retries has been
# reached and the operation still fails. It logs the final error message
# and provides context about the retry attempts.
#
# Arguments:
#   $1 - Total retry attempts made (required)
#   $2 - Final error message (required)
#   $3 - Command that was being retried (optional)
#
# Example:
#   log_retry_exhausted 3 "Throttling error" "aws cloudformation describe-stacks"
##############################################################################
log_retry_exhausted() {
    local total_attempts="$1"
    local final_error="$2"
    local command="${3:-unknown command}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${RED}[${timestamp}] All retry attempts exhausted${NC}" >&2
    echo -e "${RED}  Total attempts: ${total_attempts}${NC}" >&2
    echo -e "${RED}  Command: ${command}${NC}" >&2
    echo -e "${RED}  Final error: ${final_error}${NC}" >&2
}

##############################################################################
# calculate_backoff
#
# Calculates the backoff duration for a given retry attempt.
#
# This function implements exponential backoff with the formula:
# backoff = base_backoff * (2 ^ (attempt - 1))
#
# For base_backoff=2 seconds:
# - Attempt 1: 2 seconds
# - Attempt 2: 4 seconds
# - Attempt 3: 8 seconds
#
# Arguments:
#   $1 - Retry attempt number (1-based, required)
#   $2 - Base backoff in seconds (optional, defaults to RETRY_BASE_BACKOFF)
#
# Returns:
#   Prints the backoff duration in seconds to stdout
#
# Example:
#   backoff=$(calculate_backoff 2)
#   echo "Backoff: $backoff seconds"  # Output: Backoff: 4 seconds
##############################################################################
calculate_backoff() {
    local attempt="$1"
    local base_backoff="${2:-$RETRY_BASE_BACKOFF}"
    
    # Calculate exponential backoff: base * (2 ^ (attempt - 1))
    # For attempt 1: 2 * (2^0) = 2 * 1 = 2
    # For attempt 2: 2 * (2^1) = 2 * 2 = 4
    # For attempt 3: 2 * (2^2) = 2 * 4 = 8
    local exponent=$((attempt - 1))
    local multiplier=$((2 ** exponent))
    local backoff=$((base_backoff * multiplier))
    
    echo "$backoff"
}

##############################################################################
# execute_with_retry
#
# Executes a command with automatic retry on transient failures.
#
# This function:
# 1. Executes the provided command
# 2. Checks if the error is retryable
# 3. Retries up to max_attempts times with exponential backoff
# 4. Logs each retry attempt with reason and backoff duration
# 5. Returns success if any attempt succeeds
# 6. Returns failure if all attempts fail
#
# The function captures both stdout and stderr from the command.
# On success, stdout is printed. On failure, stderr is available
# in the LAST_ERROR_OUTPUT variable.
#
# Arguments:
#   $@ - Command and arguments to execute (required)
#
# Returns:
#   0 - Command succeeded (either first try or after retry)
#   1 - Command failed after all retry attempts
#
# Side Effects:
#   Sets LAST_ERROR_OUTPUT to the error output from the last failed attempt
#   Sets LAST_COMMAND to the command that was executed
#
# Example:
#   if execute_with_retry aws cloudformation describe-stacks --stack-name my-stack; then
#       echo "Command succeeded"
#   else
#       echo "Command failed after retries: $LAST_ERROR_OUTPUT"
#   fi
##############################################################################
execute_with_retry() {
    local command=("$@")
    local max_attempts="${RETRY_MAX_ATTEMPTS:-3}"
    local attempt=0
    
    # Store command for logging
    LAST_COMMAND="${command[*]}"
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Execute command and capture output
        local output
        local error_output
        local exit_code
        
        # Create temporary files for stdout and stderr
        local stdout_file=$(mktemp)
        local stderr_file=$(mktemp)
        
        # Execute command
        "${command[@]}" > "$stdout_file" 2> "$stderr_file"
        exit_code=$?
        
        # Read output files
        output=$(cat "$stdout_file")
        error_output=$(cat "$stderr_file")
        
        # Clean up temp files
        rm -f "$stdout_file" "$stderr_file"
        
        # Check if command succeeded
        if [ $exit_code -eq 0 ]; then
            # Success - print output and return
            if [[ -n "$output" ]]; then
                echo "$output"
            fi
            
            # Log success if this was a retry
            if [ $attempt -gt 1 ]; then
                local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                echo -e "${GREEN}[${timestamp}] Command succeeded on attempt ${attempt}${NC}"
            fi
            
            return 0
        fi
        
        # Command failed - store error output
        LAST_ERROR_OUTPUT="$error_output"
        
        # Check if we should retry
        if [ $attempt -lt $max_attempts ]; then
            # Check if error is retryable
            if is_retryable_error "$error_output"; then
                # Calculate backoff
                local backoff=$(calculate_backoff "$attempt")
                
                # Log retry attempt
                log_retry_attempt "$attempt" "$max_attempts" "$backoff" "$error_output"
                
                # Wait before retry
                sleep "$backoff"
            else
                # Not a retryable error - fail immediately
                local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                echo -e "${RED}[${timestamp}] Non-retryable error encountered${NC}" >&2
                echo -e "${RED}  Error: ${error_output}${NC}" >&2
                log_retry_exhausted "$attempt" "$error_output" "${command[*]}"
                return 1
            fi
        else
            # Max attempts reached
            log_retry_exhausted "$attempt" "$error_output" "${command[*]}"
            return 1
        fi
    done
    
    # Should never reach here, but just in case
    return 1
}

##############################################################################
# execute_aws_command_with_retry
#
# Convenience wrapper for executing AWS CLI commands with retry logic.
#
# This function is a specialized version of execute_with_retry that:
# 1. Automatically prepends "aws" to the command
# 2. Logs the command before execution
# 3. Provides AWS-specific error handling
#
# Arguments:
#   $@ - AWS CLI command and arguments (without "aws" prefix)
#
# Returns:
#   0 - Command succeeded
#   1 - Command failed after all retries
#
# Example:
#   if execute_aws_command_with_retry cloudformation describe-stacks --stack-name my-stack; then
#       echo "AWS command succeeded"
#   else
#       echo "AWS command failed: $LAST_ERROR_OUTPUT"
#   fi
##############################################################################
execute_aws_command_with_retry() {
    local aws_command=("$@")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log the command
    echo -e "${BLUE}[${timestamp}] Executing with retry: aws ${aws_command[*]}${NC}"
    
    # Execute with retry
    execute_with_retry aws "${aws_command[@]}"
    return $?
}

##############################################################################
# reset_retry_state
#
# Resets the retry state variables.
#
# This function should be called between independent operations to ensure
# retry state doesn't carry over. It's particularly useful in scripts that
# perform multiple operations.
#
# Example:
#   execute_with_retry command1
#   reset_retry_state
#   execute_with_retry command2
##############################################################################
reset_retry_state() {
    RETRY_ATTEMPT=0
    LAST_ERROR_OUTPUT=""
    LAST_COMMAND=""
}
