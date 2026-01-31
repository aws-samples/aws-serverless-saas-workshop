#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

##############################################################################
# Exit Codes Module
#
# Provides consistent exit code handling across all cleanup scripts.
#
# Exit Codes:
#   0   - EXIT_SUCCESS: Complete success
#   1   - EXIT_FAILURE: Critical operation failure
#   2   - EXIT_TIMEOUT: Operation timed out
#   3   - EXIT_ORPHANED_RESOURCES: Orphaned resources detected
#   130 - EXIT_USER_INTERRUPT: User interrupt (SIGINT/Ctrl+C)
#
# Functions:
#   setup_exit_handlers()        - Set up signal handlers for graceful exit
#   exit_with_code()             - Exit with proper logging
#   get_exit_code_description()  - Get human-readable description of exit code
#   handle_sigint()              - Handle SIGINT signal (Ctrl+C)
#
# Usage:
#   source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"
#   setup_exit_handlers
#   exit_with_code $EXIT_SUCCESS "Cleanup completed successfully"
##############################################################################

# Exit code constants
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_TIMEOUT=2
readonly EXIT_ORPHANED_RESOURCES=3
readonly EXIT_USER_INTERRUPT=130

##############################################################################
# handle_sigint
#
# Signal handler for SIGINT (Ctrl+C).
# Exits with EXIT_USER_INTERRUPT code.
#
# This function is called automatically when the user presses Ctrl+C.
##############################################################################
handle_sigint() {
    echo "" >&2
    echo "Received interrupt signal (Ctrl+C)" >&2
    echo "Exiting cleanup..." >&2
    exit $EXIT_USER_INTERRUPT
}

##############################################################################
# setup_exit_handlers
#
# Sets up signal handlers for graceful exit.
#
# This function should be called early in the cleanup script, after
# parameter parsing and before any cleanup operations.
#
# Example:
#   setup_exit_handlers
##############################################################################
setup_exit_handlers() {
    # Set up SIGINT handler (Ctrl+C)
    trap 'handle_sigint' SIGINT
}

##############################################################################
# exit_with_code
#
# Exit with a specific exit code and optional message.
#
# Arguments:
#   $1 - Exit code (required)
#   $2 - Exit message (optional)
#
# Example:
#   exit_with_code $EXIT_SUCCESS "Cleanup completed successfully"
#   exit_with_code $EXIT_FAILURE "Stack deletion failed"
##############################################################################
exit_with_code() {
    local exit_code="$1"
    local message="${2:-}"
    
    if [[ -z "$exit_code" ]]; then
        echo "ERROR: exit_with_code requires an exit code" >&2
        exit $EXIT_FAILURE
    fi
    
    # Log the exit
    if [[ -n "$message" ]]; then
        if [[ $exit_code -eq $EXIT_SUCCESS ]]; then
            echo "✓ $message" >&2
        elif [[ $exit_code -eq $EXIT_USER_INTERRUPT ]]; then
            echo "⚠ $message" >&2
        else
            echo "✗ $message" >&2
        fi
    fi
    
    # Get exit code description
    local description=$(get_exit_code_description "$exit_code")
    if [[ -n "$description" ]]; then
        echo "Exit code: $exit_code ($description)" >&2
    else
        echo "Exit code: $exit_code" >&2
    fi
    
    exit "$exit_code"
}

##############################################################################
# get_exit_code_description
#
# Get a human-readable description of an exit code.
#
# Arguments:
#   $1 - Exit code
#
# Returns:
#   Description string (or empty if unknown)
#
# Example:
#   description=$(get_exit_code_description 0)
#   echo "Exit code 0: $description"
##############################################################################
get_exit_code_description() {
    local exit_code="$1"
    
    case "$exit_code" in
        $EXIT_SUCCESS)
            echo "Success"
            ;;
        $EXIT_FAILURE)
            echo "Critical operation failure"
            ;;
        $EXIT_TIMEOUT)
            echo "Operation timed out"
            ;;
        $EXIT_ORPHANED_RESOURCES)
            echo "Orphaned resources detected"
            ;;
        $EXIT_USER_INTERRUPT)
            echo "User interrupt"
            ;;
        *)
            echo ""
            ;;
    esac
}
