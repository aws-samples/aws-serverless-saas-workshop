#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ============================================================================
# Parameter Parsing Template for Cleanup Scripts
# ============================================================================
# This template provides reusable functions for parsing command-line parameters
# in cleanup scripts with optional stack name support.
#
# Usage:
#   1. Source this file in your cleanup script
#   2. Set DEFAULT_STACK_NAME before calling parse_cleanup_parameters
#   3. Call parse_cleanup_parameters with "$@"
#   4. Use the populated variables (STACK_NAME, AWS_PROFILE, etc.)
#
# Example:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/parameter-parsing-template.sh"
#   DEFAULT_STACK_NAME="serverless-saas-lab1"
#   parse_cleanup_parameters "$@"
# ============================================================================

# ============================================================================
# Function: show_cleanup_help
# ============================================================================
# Displays help text for cleanup scripts with optional stack name parameter.
#
# Parameters:
#   $1 - Lab number (e.g., "1", "2", "3")
#   $2 - Default stack name (e.g., "serverless-saas-lab1")
#
# Example:
#   show_cleanup_help "1" "serverless-saas-lab1"
# ============================================================================
show_cleanup_help() {
  local lab_number="$1"
  local default_stack_name="$2"
  
  cat << EOF
Usage: ./cleanup.sh [OPTIONS]

Cleanup script for Lab ${lab_number} - Deletes all AWS resources created by the lab.

OPTIONS:
  --stack-name <name>    CloudFormation stack name
                         (optional, default: ${default_stack_name})
  --profile <name>       AWS CLI profile name (REQUIRED)
  --region <region>      AWS region (optional, default: us-east-1)
  -y, --yes             Skip confirmation prompt
  -h, --help            Display this help message

EXAMPLES:
  # Cleanup with default stack name
  ./cleanup.sh --profile my-profile

  # Cleanup with explicit stack name
  ./cleanup.sh --stack-name my-custom-stack --profile my-profile

  # Non-interactive cleanup (skip confirmation)
  echo "yes" | ./cleanup.sh --profile my-profile

  # Cleanup with custom region
  ./cleanup.sh --profile my-profile --region us-west-2

SECURITY NOTE:
  This script follows secure deletion order to prevent CloudFront origin hijacking:
  1. Delete CloudFormation stack (includes CloudFront distributions)
  2. Wait for stack DELETE_COMPLETE (15-30 minutes for CloudFront propagation)
  3. Delete S3 buckets (safe after CloudFront is deleted)

  For more information, see: workshop/CLOUDFRONT_SECURITY_FIX.md

EOF
}

# ============================================================================
# Function: validate_stack_name
# ============================================================================
# Validates that the stack name is not empty or contains only whitespace.
#
# Parameters:
#   $1 - Stack name to validate
#
# Returns:
#   0 if valid, 1 if invalid (exits script with error message)
#
# Example:
#   validate_stack_name "$STACK_NAME"
# ============================================================================
validate_stack_name() {
  local stack_name="$1"
  
  # Check if stack name is empty
  if [ -z "$stack_name" ]; then
    echo "Error: Stack name cannot be empty"
    return 1
  fi
  
  # Check if stack name contains only whitespace
  if [[ "$stack_name" =~ ^[[:space:]]*$ ]]; then
    echo "Error: Stack name cannot contain only whitespace"
    return 1
  fi
  
  return 0
}

# ============================================================================
# Function: assign_default_stack_name
# ============================================================================
# Assigns the default stack name if STACK_NAME is empty and logs the decision.
#
# Parameters:
#   $1 - Default stack name to use
#
# Side Effects:
#   - Sets STACK_NAME to default value if empty
#   - Logs informative message when default is used
#
# Example:
#   assign_default_stack_name "serverless-saas-lab1"
# ============================================================================
assign_default_stack_name() {
  local default_stack_name="$1"
  
  if [ -z "$STACK_NAME" ]; then
    STACK_NAME="$default_stack_name"
    echo "ℹ️  Using default stack name: $STACK_NAME"
  fi
}

# ============================================================================
# Function: parse_cleanup_parameters
# ============================================================================
# Parses command-line parameters for cleanup scripts with optional stack name.
#
# This function handles:
#   - Optional --stack-name parameter with default value
#   - Required --profile parameter
#   - Optional --region parameter (default: us-east-1)
#   - Optional -y/--yes flag for non-interactive mode
#   - Help text display with -h/--help
#   - Unknown parameter detection and error handling
#
# Prerequisites:
#   - DEFAULT_STACK_NAME must be set before calling this function
#   - LAB_NUMBER should be set for help text (optional)
#
# Side Effects:
#   - Sets STACK_NAME (from parameter or default)
#   - Sets AWS_PROFILE (required)
#   - Sets AWS_REGION (default: us-east-1)
#   - Sets SKIP_CONFIRMATION (0 or 1)
#   - May exit script with error code 1 on invalid input
#
# Example:
#   DEFAULT_STACK_NAME="serverless-saas-lab1"
#   LAB_NUMBER="1"
#   parse_cleanup_parameters "$@"
# ============================================================================
parse_cleanup_parameters() {
  # Validate prerequisites
  if [ -z "$DEFAULT_STACK_NAME" ]; then
    echo "Error: DEFAULT_STACK_NAME must be set before calling parse_cleanup_parameters"
    exit 1
  fi
  
  # Set default lab number if not provided
  if [ -z "$LAB_NUMBER" ]; then
    LAB_NUMBER="N"
  fi
  
  # Initialize variables
  STACK_NAME=""
  AWS_PROFILE=""
  AWS_REGION="us-east-1"
  SKIP_CONFIRMATION=0
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --stack-name)
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "Error: --stack-name requires a value"
          show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
          exit 1
        fi
        STACK_NAME="$2"
        shift 2
        ;;
      --profile)
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "Error: --profile requires a value"
          show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
          exit 1
        fi
        AWS_PROFILE="$2"
        shift 2
        ;;
      --region)
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "Error: --region requires a value"
          show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
          exit 1
        fi
        AWS_REGION="$2"
        shift 2
        ;;
      -y|--yes)
        SKIP_CONFIRMATION=1
        shift
        ;;
      -h|--help)
        show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
        exit 0
        ;;
      *)
        echo "Error: Unknown option: $1"
        echo ""
        show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
        exit 1
        ;;
    esac
  done
  
  # Assign default stack name if not provided
  assign_default_stack_name "$DEFAULT_STACK_NAME"
  
  # Validate stack name
  if ! validate_stack_name "$STACK_NAME"; then
    exit 1
  fi
  
  # Validate required parameters
  if [ -z "$AWS_PROFILE" ]; then
    echo "Error: --profile parameter is required"
    echo ""
    show_cleanup_help "$LAB_NUMBER" "$DEFAULT_STACK_NAME"
    exit 1
  fi
  
  # Set PROFILE_ARG for use in AWS CLI commands
  PROFILE_ARG="--profile $AWS_PROFILE"
}

# ============================================================================
# Function: display_cleanup_configuration
# ============================================================================
# Displays the current cleanup configuration (stack name, profile, region).
#
# This function should be called after parse_cleanup_parameters to show
# the user what configuration will be used for cleanup.
#
# Prerequisites:
#   - STACK_NAME must be set
#   - AWS_PROFILE must be set
#   - AWS_REGION must be set
#   - LAB_NUMBER should be set (optional)
#
# Example:
#   display_cleanup_configuration
# ============================================================================
display_cleanup_configuration() {
  local lab_label="${LAB_NUMBER:-N}"
  
  echo "========================================"
  echo "Lab${lab_label} Cleanup Configuration"
  echo "========================================"
  echo "Stack name:  $STACK_NAME"
  echo "AWS Profile: $AWS_PROFILE"
  echo "AWS Region:  $AWS_REGION"
  echo ""
}
