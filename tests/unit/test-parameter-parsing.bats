#!/usr/bin/env bats

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ============================================================================
# Unit Tests for Parameter Parsing Template
# ============================================================================
# These tests verify the parameter parsing logic for cleanup scripts with
# optional stack name support.
#
# Test Framework: BATS (Bash Automated Testing System)
# Run: bats workshop/tests/unit/test-parameter-parsing.bats
# ============================================================================

# Setup function - runs before each test
setup() {
  # Source the parameter parsing template
  source "workshop/scripts/lib/parameter-parsing-template.sh"
  
  # Set default values for testing
  export DEFAULT_STACK_NAME="serverless-saas-lab1"
  export LAB_NUMBER="1"
}

# Teardown function - runs after each test
teardown() {
  # Clean up environment variables
  unset DEFAULT_STACK_NAME
  unset LAB_NUMBER
  unset STACK_NAME
  unset AWS_PROFILE
  unset AWS_REGION
  unset SKIP_CONFIRMATION
  unset PROFILE_ARG
}

# ============================================================================
# Test Category: Stack Name Validation
# ============================================================================

@test "validate_stack_name: accepts non-empty stack name" {
  run validate_stack_name "my-stack"
  [ "$status" -eq 0 ]
}

@test "validate_stack_name: rejects empty stack name" {
  run validate_stack_name ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stack name cannot be empty"* ]]
}

@test "validate_stack_name: rejects whitespace-only stack name" {
  run validate_stack_name "   "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stack name cannot contain only whitespace"* ]]
}

@test "validate_stack_name: accepts stack name with hyphens" {
  run validate_stack_name "serverless-saas-lab1"
  [ "$status" -eq 0 ]
}

@test "validate_stack_name: accepts stack name with numbers" {
  run validate_stack_name "my-stack-123"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Test Category: Default Stack Name Assignment
# ============================================================================

@test "assign_default_stack_name: assigns default when STACK_NAME is empty" {
  STACK_NAME=""
  run assign_default_stack_name "serverless-saas-lab1"
  [ "$status" -eq 0 ]
  [ "$STACK_NAME" = "serverless-saas-lab1" ]
  [[ "$output" == *"Using default stack name: serverless-saas-lab1"* ]]
}

@test "assign_default_stack_name: preserves existing STACK_NAME" {
  STACK_NAME="custom-stack"
  run assign_default_stack_name "serverless-saas-lab1"
  [ "$status" -eq 0 ]
  [ "$STACK_NAME" = "custom-stack" ]
  [[ "$output" != *"Using default"* ]]
}

@test "assign_default_stack_name: logs informative message when using default" {
  STACK_NAME=""
  run assign_default_stack_name "serverless-saas-lab2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ℹ️  Using default stack name: serverless-saas-lab2"* ]]
}

# ============================================================================
# Test Category: Parameter Parsing - Stack Name
# ============================================================================

@test "parse_cleanup_parameters: uses default stack name when not provided" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile
  [ "$STACK_NAME" = "serverless-saas-lab1" ]
}

@test "parse_cleanup_parameters: uses provided stack name" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --stack-name custom-stack --profile test-profile
  [ "$STACK_NAME" = "custom-stack" ]
}

@test "parse_cleanup_parameters: explicit stack name overrides default" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --stack-name my-custom-stack --profile test-profile
  [ "$STACK_NAME" = "my-custom-stack" ]
  [ "$STACK_NAME" != "serverless-saas-lab1" ]
}

# ============================================================================
# Test Category: Parameter Parsing - AWS Profile
# ============================================================================

@test "parse_cleanup_parameters: requires AWS profile" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters
  [ "$status" -eq 1 ]
  [[ "$output" == *"--profile parameter is required"* ]]
}

@test "parse_cleanup_parameters: accepts AWS profile" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile my-profile
  [ "$AWS_PROFILE" = "my-profile" ]
}

@test "parse_cleanup_parameters: sets PROFILE_ARG correctly" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile
  [ "$PROFILE_ARG" = "--profile test-profile" ]
}

# ============================================================================
# Test Category: Parameter Parsing - AWS Region
# ============================================================================

@test "parse_cleanup_parameters: uses default region us-east-1" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile
  [ "$AWS_REGION" = "us-east-1" ]
}

@test "parse_cleanup_parameters: accepts custom region" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile --region us-west-2
  [ "$AWS_REGION" = "us-west-2" ]
}

# ============================================================================
# Test Category: Parameter Parsing - Confirmation Flag
# ============================================================================

@test "parse_cleanup_parameters: defaults to interactive mode" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile
  [ "$SKIP_CONFIRMATION" -eq 0 ]
}

@test "parse_cleanup_parameters: accepts -y flag" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile -y
  [ "$SKIP_CONFIRMATION" -eq 1 ]
}

@test "parse_cleanup_parameters: accepts --yes flag" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --profile test-profile --yes
  [ "$SKIP_CONFIRMATION" -eq 1 ]
}

# ============================================================================
# Test Category: Parameter Parsing - Help Text
# ============================================================================

@test "parse_cleanup_parameters: displays help with -h" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./cleanup.sh"* ]]
  [[ "$output" == *"serverless-saas-lab1"* ]]
}

@test "parse_cleanup_parameters: displays help with --help" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./cleanup.sh"* ]]
  [[ "$output" == *"serverless-saas-lab1"* ]]
}

# ============================================================================
# Test Category: Parameter Parsing - Error Handling
# ============================================================================

@test "parse_cleanup_parameters: rejects unknown parameter" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters --unknown-param --profile test-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --unknown-param"* ]]
}

@test "parse_cleanup_parameters: requires DEFAULT_STACK_NAME to be set" {
  unset DEFAULT_STACK_NAME
  run parse_cleanup_parameters --profile test-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"DEFAULT_STACK_NAME must be set"* ]]
}

@test "parse_cleanup_parameters: rejects --stack-name without value" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters --stack-name --profile test-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"--stack-name requires a value"* ]]
}

@test "parse_cleanup_parameters: rejects --profile without value" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters --profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"--profile requires a value"* ]]
}

@test "parse_cleanup_parameters: rejects --region without value" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  run parse_cleanup_parameters --region --profile test-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"--region requires a value"* ]]
}

# ============================================================================
# Test Category: Parameter Parsing - Complex Scenarios
# ============================================================================

@test "parse_cleanup_parameters: handles all parameters together" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters --stack-name my-stack --profile my-profile --region us-west-2 -y
  [ "$STACK_NAME" = "my-stack" ]
  [ "$AWS_PROFILE" = "my-profile" ]
  [ "$AWS_REGION" = "us-west-2" ]
  [ "$SKIP_CONFIRMATION" -eq 1 ]
}

@test "parse_cleanup_parameters: handles parameters in different order" {
  DEFAULT_STACK_NAME="serverless-saas-lab1"
  parse_cleanup_parameters -y --region us-west-2 --profile my-profile --stack-name my-stack
  [ "$STACK_NAME" = "my-stack" ]
  [ "$AWS_PROFILE" = "my-profile" ]
  [ "$AWS_REGION" = "us-west-2" ]
  [ "$SKIP_CONFIRMATION" -eq 1 ]
}

# ============================================================================
# Test Category: Help Text Display
# ============================================================================

@test "show_cleanup_help: displays lab number" {
  run show_cleanup_help "1" "serverless-saas-lab1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lab 1"* ]]
}

@test "show_cleanup_help: displays default stack name" {
  run show_cleanup_help "2" "serverless-saas-lab2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"serverless-saas-lab2"* ]]
}

@test "show_cleanup_help: includes security note" {
  run show_cleanup_help "1" "serverless-saas-lab1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SECURITY NOTE"* ]]
  [[ "$output" == *"CloudFront origin hijacking"* ]]
}

@test "show_cleanup_help: includes usage examples" {
  run show_cleanup_help "1" "serverless-saas-lab1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXAMPLES"* ]]
  [[ "$output" == *"./cleanup.sh --profile"* ]]
}

# ============================================================================
# Test Category: Configuration Display
# ============================================================================

@test "display_cleanup_configuration: shows stack name" {
  STACK_NAME="my-stack"
  AWS_PROFILE="my-profile"
  AWS_REGION="us-east-1"
  LAB_NUMBER="1"
  run display_cleanup_configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-stack"* ]]
}

@test "display_cleanup_configuration: shows AWS profile" {
  STACK_NAME="my-stack"
  AWS_PROFILE="my-profile"
  AWS_REGION="us-east-1"
  LAB_NUMBER="1"
  run display_cleanup_configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-profile"* ]]
}

@test "display_cleanup_configuration: shows AWS region" {
  STACK_NAME="my-stack"
  AWS_PROFILE="my-profile"
  AWS_REGION="us-west-2"
  LAB_NUMBER="1"
  run display_cleanup_configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"us-west-2"* ]]
}
