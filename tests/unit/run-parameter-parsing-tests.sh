#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ============================================================================
# Simple Test Runner for Parameter Parsing Template
# ============================================================================
# This script runs unit tests for the parameter parsing template without
# requiring BATS or other external testing frameworks.
#
# Usage: ./run-parameter-parsing-tests.sh
# ============================================================================

# Note: We don't use 'set -e' here because we need to capture exit codes
# from functions that are expected to fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source the parameter parsing template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib/parameter-parsing-template.sh"

# Test helper functions
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [ "$expected" = "$actual" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $message"
    echo -e "  Expected: '$expected'"
    echo -e "  Actual:   '$actual'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $message"
    echo -e "  Expected to contain: '$needle'"
    echo -e "  Actual output: '$haystack'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

assert_exit_code() {
  local expected_code="$1"
  local actual_code="$2"
  local message="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [ "$expected_code" -eq "$actual_code" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $message"
    echo -e "  Expected exit code: $expected_code"
    echo -e "  Actual exit code:   $actual_code"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Setup function - runs before each test
setup() {
  export DEFAULT_STACK_NAME="serverless-saas-lab1"
  export LAB_NUMBER="1"
  unset STACK_NAME
  unset AWS_PROFILE
  unset AWS_REGION
  unset SKIP_CONFIRMATION
  unset PROFILE_ARG
}

# Teardown function - runs after each test
teardown() {
  unset DEFAULT_STACK_NAME
  unset LAB_NUMBER
  unset STACK_NAME
  unset AWS_PROFILE
  unset AWS_REGION
  unset SKIP_CONFIRMATION
  unset PROFILE_ARG
}

echo "========================================"
echo "Parameter Parsing Template Unit Tests"
echo "========================================"
echo ""

# ============================================================================
# Test Category: Stack Name Validation
# ============================================================================

echo -e "${BLUE}Test Category: Stack Name Validation${NC}"

setup
validate_stack_name "my-stack" > /dev/null 2>&1
assert_exit_code 0 $? "validate_stack_name accepts non-empty stack name"
teardown

setup
output=$(validate_stack_name "" 2>&1)
exit_code=$?
assert_exit_code 1 $exit_code "validate_stack_name rejects empty stack name"
assert_contains "$output" "Stack name cannot be empty" "Error message for empty stack name"
teardown

setup
output=$(validate_stack_name "   " 2>&1)
exit_code=$?
assert_exit_code 1 $exit_code "validate_stack_name rejects whitespace-only stack name"
assert_contains "$output" "whitespace" "Error message for whitespace-only stack name"
teardown

setup
validate_stack_name "serverless-saas-lab1" > /dev/null 2>&1
assert_exit_code 0 $? "validate_stack_name accepts stack name with hyphens"
teardown

setup
validate_stack_name "my-stack-123" > /dev/null 2>&1
assert_exit_code 0 $? "validate_stack_name accepts stack name with numbers"
teardown

echo ""

# ============================================================================
# Test Category: Default Stack Name Assignment
# ============================================================================

echo -e "${BLUE}Test Category: Default Stack Name Assignment${NC}"

setup
STACK_NAME=""
assign_default_stack_name "serverless-saas-lab1" > /dev/null 2>&1
assert_equals "serverless-saas-lab1" "$STACK_NAME" "assign_default_stack_name assigns default when STACK_NAME is empty"
teardown

setup
STACK_NAME=""
output=$(assign_default_stack_name "serverless-saas-lab1" 2>&1)
assert_contains "$output" "Using default stack name" "Logs message when using default"
teardown

setup
STACK_NAME="custom-stack"
output=$(assign_default_stack_name "serverless-saas-lab1" 2>&1)
assert_equals "custom-stack" "$STACK_NAME" "assign_default_stack_name preserves existing STACK_NAME"
teardown

setup
STACK_NAME=""
output=$(assign_default_stack_name "serverless-saas-lab2" 2>&1)
assert_contains "$output" "serverless-saas-lab2" "Logs correct default stack name"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - Stack Name
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - Stack Name${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile > /dev/null 2>&1
assert_equals "serverless-saas-lab1" "$STACK_NAME" "Uses default stack name when not provided"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --stack-name custom-stack --profile test-profile > /dev/null 2>&1
assert_equals "custom-stack" "$STACK_NAME" "Uses provided stack name"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --stack-name my-custom-stack --profile test-profile > /dev/null 2>&1
assert_equals "my-custom-stack" "$STACK_NAME" "Explicit stack name overrides default"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - AWS Profile
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - AWS Profile${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
output=$(parse_cleanup_parameters 2>&1)
exit_code=$?
assert_exit_code 1 $exit_code "Requires AWS profile"
assert_contains "$output" "--profile parameter is required" "Error message for missing profile"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile my-profile > /dev/null 2>&1
assert_equals "my-profile" "$AWS_PROFILE" "Accepts AWS profile"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile > /dev/null 2>&1
assert_equals "--profile test-profile" "$PROFILE_ARG" "Sets PROFILE_ARG correctly"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - AWS Region
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - AWS Region${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile > /dev/null 2>&1
assert_equals "us-east-1" "$AWS_REGION" "Uses default region us-east-1"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile --region us-west-2 > /dev/null 2>&1
assert_equals "us-west-2" "$AWS_REGION" "Accepts custom region"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - Confirmation Flag
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - Confirmation Flag${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile > /dev/null 2>&1
assert_equals "0" "$SKIP_CONFIRMATION" "Defaults to interactive mode"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile -y > /dev/null 2>&1
assert_equals "1" "$SKIP_CONFIRMATION" "Accepts -y flag"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --profile test-profile --yes > /dev/null 2>&1
assert_equals "1" "$SKIP_CONFIRMATION" "Accepts --yes flag"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - Help Text
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - Help Text${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
output=$(parse_cleanup_parameters -h 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "Displays help with -h"
assert_contains "$output" "Usage: ./cleanup.sh" "Help text contains usage"
assert_contains "$output" "serverless-saas-lab1" "Help text contains default stack name"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
output=$(parse_cleanup_parameters --help 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "Displays help with --help"
assert_contains "$output" "Usage: ./cleanup.sh" "Help text contains usage"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - Error Handling
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - Error Handling${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
output=$(parse_cleanup_parameters --unknown-param --profile test-profile 2>&1)
exit_code=$?
assert_exit_code 1 $exit_code "Rejects unknown parameter"
assert_contains "$output" "Unknown option: --unknown-param" "Error message for unknown parameter"
teardown

setup
unset DEFAULT_STACK_NAME
output=$(parse_cleanup_parameters --profile test-profile 2>&1)
exit_code=$?
assert_exit_code 1 $exit_code "Requires DEFAULT_STACK_NAME to be set"
assert_contains "$output" "DEFAULT_STACK_NAME must be set" "Error message for missing DEFAULT_STACK_NAME"
teardown

echo ""

# ============================================================================
# Test Category: Parameter Parsing - Complex Scenarios
# ============================================================================

echo -e "${BLUE}Test Category: Parameter Parsing - Complex Scenarios${NC}"

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters --stack-name my-stack --profile my-profile --region us-west-2 -y > /dev/null 2>&1
assert_equals "my-stack" "$STACK_NAME" "Handles all parameters together - stack name"
assert_equals "my-profile" "$AWS_PROFILE" "Handles all parameters together - profile"
assert_equals "us-west-2" "$AWS_REGION" "Handles all parameters together - region"
assert_equals "1" "$SKIP_CONFIRMATION" "Handles all parameters together - confirmation"
teardown

setup
DEFAULT_STACK_NAME="serverless-saas-lab1"
parse_cleanup_parameters -y --region us-west-2 --profile my-profile --stack-name my-stack > /dev/null 2>&1
assert_equals "my-stack" "$STACK_NAME" "Handles parameters in different order - stack name"
assert_equals "my-profile" "$AWS_PROFILE" "Handles parameters in different order - profile"
assert_equals "us-west-2" "$AWS_REGION" "Handles parameters in different order - region"
teardown

echo ""

# ============================================================================
# Test Category: Help Text Display
# ============================================================================

echo -e "${BLUE}Test Category: Help Text Display${NC}"

setup
output=$(show_cleanup_help "1" "serverless-saas-lab1" 2>&1)
assert_contains "$output" "Lab 1" "Displays lab number"
assert_contains "$output" "serverless-saas-lab1" "Displays default stack name"
assert_contains "$output" "SECURITY NOTE" "Includes security note"
assert_contains "$output" "CloudFront origin hijacking" "Mentions CloudFront security"
assert_contains "$output" "EXAMPLES" "Includes usage examples"
teardown

echo ""

# ============================================================================
# Test Summary
# ============================================================================

echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Tests run:    ${BLUE}$TESTS_RUN${NC}"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
