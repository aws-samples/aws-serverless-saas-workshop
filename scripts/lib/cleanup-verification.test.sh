#!/bin/bash

# Unit Tests for Cleanup Verification Module
#
# This test suite validates the cleanup verification functions that query
# AWS for remaining resources after cleanup operations.
#
# Test Coverage:
# - query_remaining_stacks: Verify stack querying logic
# - query_remaining_buckets: Verify S3 bucket querying logic
# - query_remaining_log_groups: Verify CloudWatch log group querying logic
# - query_remaining_cognito_pools: Verify Cognito user pool querying logic
# - verify_complete_cleanup: Verify comprehensive cleanup verification
#
# Usage:
#   ./cleanup-verification.test.sh

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module under test
source "$SCRIPT_DIR/cleanup-verification.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

##############################################################################
# Test Helper Functions
##############################################################################

# Mock AWS CLI for testing
mock_aws() {
    local command="$1"
    shift
    
    case "$command" in
        "cloudformation")
            if [[ "$1" == "list-stacks" ]]; then
                # Return mock stack list
                echo '{"StackSummaries":[{"StackName":"serverless-saas-lab6-stack1"},{"StackName":"serverless-saas-lab6-stack2"}]}'
            fi
            ;;
        "s3api")
            if [[ "$1" == "list-buckets" ]]; then
                # Return mock bucket list
                echo '{"Buckets":[{"Name":"serverless-saas-lab6-bucket1"},{"Name":"serverless-saas-lab6-bucket2"}]}'
            fi
            ;;
        "logs")
            if [[ "$1" == "describe-log-groups" ]]; then
                # Return mock log groups
                echo '{"logGroups":[{"logGroupName":"/aws/lambda/lab6-function1"},{"logGroupName":"/aws/lambda/lab6-function2"}]}'
            fi
            ;;
        "cognito-idp")
            if [[ "$1" == "list-user-pools" ]]; then
                # Return mock user pools
                echo '{"UserPools":[{"Id":"us-east-1_ABC123","Name":"lab6-user-pool"},{"Id":"us-east-1_DEF456","Name":"lab6-admin-pool"}]}'
            fi
            ;;
    esac
}

# Assert function
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo -e "${RED}  Expected: $expected${NC}"
        echo -e "${RED}  Actual: $actual${NC}"
        return 1
    fi
}

# Assert contains function
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo -e "${RED}  Expected to contain: $needle${NC}"
        echo -e "${RED}  Actual: $haystack${NC}"
        return 1
    fi
}

# Assert not empty function
assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -n "$value" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo -e "${RED}  Expected non-empty value${NC}"
        return 1
    fi
}

# Assert empty function
assert_empty() {
    local value="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -z "$value" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo -e "${RED}  Expected empty value, got: $value${NC}"
        return 1
    fi
}

##############################################################################
# Test Cases
##############################################################################

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Cleanup Verification Module - Unit Tests              ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Test 1: query_remaining_stacks with missing lab_id
echo -e "${YELLOW}Test 1: query_remaining_stacks requires lab_id${NC}"
result=$(query_remaining_stacks "" "" 2>&1)
exit_code=$?
assert_equals "1" "$exit_code" "Should return error code 1 for missing lab_id"
assert_contains "$result" "Lab identifier is required" "Should show error message"
echo ""

# Test 2: query_remaining_buckets with missing lab_id
echo -e "${YELLOW}Test 2: query_remaining_buckets requires lab_id${NC}"
result=$(query_remaining_buckets "" "" 2>&1)
exit_code=$?
assert_equals "1" "$exit_code" "Should return error code 1 for missing lab_id"
assert_contains "$result" "Lab identifier is required" "Should show error message"
echo ""

# Test 3: query_remaining_log_groups with missing lab_id
echo -e "${YELLOW}Test 3: query_remaining_log_groups requires lab_id${NC}"
result=$(query_remaining_log_groups "" "" 2>&1)
exit_code=$?
assert_equals "1" "$exit_code" "Should return error code 1 for missing lab_id"
assert_contains "$result" "Lab identifier is required" "Should show error message"
echo ""

# Test 4: query_remaining_cognito_pools with missing lab_id
echo -e "${YELLOW}Test 4: query_remaining_cognito_pools requires lab_id${NC}"
result=$(query_remaining_cognito_pools "" "" 2>&1)
exit_code=$?
assert_equals "1" "$exit_code" "Should return error code 1 for missing lab_id"
assert_contains "$result" "Lab identifier is required" "Should show error message"
echo ""

# Test 5: verify_complete_cleanup with missing lab_id
echo -e "${YELLOW}Test 5: verify_complete_cleanup requires lab_id${NC}"
result=$(verify_complete_cleanup "" "" 2>&1)
exit_code=$?
assert_equals "1" "$exit_code" "Should return error code 1 for missing lab_id"
assert_contains "$result" "Lab identifier is required" "Should show error message"
echo ""

# Test 6: Query functions output format
echo -e "${YELLOW}Test 6: Query functions produce correct output format${NC}"
echo -e "${BLUE}Note: This test requires actual AWS CLI access${NC}"
echo -e "${BLUE}Skipping in unit test mode - covered by integration tests${NC}"
echo ""

# Test 7: verify_complete_cleanup detects orphaned resources
echo -e "${YELLOW}Test 7: verify_complete_cleanup exit codes${NC}"
echo -e "${BLUE}Note: This test requires actual AWS CLI access${NC}"
echo -e "${BLUE}Skipping in unit test mode - covered by integration tests${NC}"
echo ""

# Test 8: generate_cleanup_commands produces valid commands
echo -e "${YELLOW}Test 8: generate_cleanup_commands output format${NC}"
result=$(generate_cleanup_commands "lab6" "" 2>&1)
assert_contains "$result" "MANUAL CLEANUP COMMANDS" "Should show header"
assert_contains "$result" "aws cloudformation delete-stack" "Should include stack deletion command"
echo ""

##############################################################################
# Test Summary
##############################################################################

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST SUMMARY                           ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Total Tests Run: ${TESTS_RUN}${NC}"
echo -e "${GREEN}Tests Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Tests Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    exit 1
fi
