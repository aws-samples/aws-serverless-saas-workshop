#!/bin/bash

# Unit Tests for Retry Logic Module
#
# This test suite validates the retry logic implementation including:
# - Error detection (retryable vs non-retryable)
# - Exponential backoff calculation
# - Retry attempt logging
# - Max retry enforcement
# - Command execution with retry

# Source the module under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/retry-logic.sh"

# Test framework variables
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes for test output
TEST_GREEN='\033[0;32m'
TEST_RED='\033[0;31m'
TEST_YELLOW='\033[1;33m'
TEST_BLUE='\033[0;34m'
TEST_NC='\033[0m'

##############################################################################
# Test Framework Functions
##############################################################################

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓ PASS${TEST_NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗ FAIL${TEST_NC}: $test_name"
        echo -e "${TEST_RED}  Expected: $expected${TEST_NC}"
        echo -e "${TEST_RED}  Actual:   $actual${TEST_NC}"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓ PASS${TEST_NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗ FAIL${TEST_NC}: $test_name"
        echo -e "${TEST_RED}  Condition failed: $condition${TEST_NC}"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓ PASS${TEST_NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗ FAIL${TEST_NC}: $test_name"
        echo -e "${TEST_RED}  Condition should be false: $condition${TEST_NC}"
        return 1
    fi
}

print_test_summary() {
    echo ""
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    echo -e "${TEST_BLUE}                    TEST SUMMARY                           ${TEST_NC}"
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    echo -e "${TEST_BLUE}Total Tests:  ${TESTS_RUN}${TEST_NC}"
    echo -e "${TEST_GREEN}Passed:       ${TESTS_PASSED}${TEST_NC}"
    echo -e "${TEST_RED}Failed:       ${TESTS_FAILED}${TEST_NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${TEST_GREEN}All tests passed!${TEST_NC}"
        echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
        return 0
    else
        echo -e "${TEST_RED}Some tests failed!${TEST_NC}"
        echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
        return 1
    fi
}

##############################################################################
# Test Cases for is_retryable_error
##############################################################################

test_is_retryable_error_throttling() {
    echo -e "\n${TEST_YELLOW}Testing is_retryable_error - Throttling Errors${TEST_NC}"
    
    # Test various throttling error messages
    is_retryable_error "Throttling: Rate exceeded"
    assert_equals "0" "$?" "Detects 'Throttling' error"
    
    is_retryable_error "Request was throttled"
    assert_equals "0" "$?" "Detects 'throttled' error"
    
    is_retryable_error "TooManyRequests: Too many requests"
    assert_equals "0" "$?" "Detects 'TooManyRequests' error"
    
    is_retryable_error "Rate exceeded for this operation"
    assert_equals "0" "$?" "Detects 'Rate exceeded' error"
    
    is_retryable_error "RequestLimitExceeded: Request limit exceeded"
    assert_equals "0" "$?" "Detects 'RequestLimitExceeded' error"
}

test_is_retryable_error_network() {
    echo -e "\n${TEST_YELLOW}Testing is_retryable_error - Network Errors${TEST_NC}"
    
    # Test various network error messages
    is_retryable_error "Connection timeout"
    assert_equals "0" "$?" "Detects 'Connection timeout' error"
    
    is_retryable_error "Could not connect to the endpoint"
    assert_equals "0" "$?" "Detects 'Could not connect' error"
    
    is_retryable_error "Network error occurred"
    assert_equals "0" "$?" "Detects 'Network error' error"
    
    is_retryable_error "Connection reset by peer"
    assert_equals "0" "$?" "Detects 'Connection reset' error"
    
    is_retryable_error "Connection refused"
    assert_equals "0" "$?" "Detects 'Connection refused' error"
    
    is_retryable_error "Operation timed out"
    assert_equals "0" "$?" "Detects 'timed out' error"
}

test_is_retryable_error_service_unavailable() {
    echo -e "\n${TEST_YELLOW}Testing is_retryable_error - Service Unavailable${TEST_NC}"
    
    # Test service unavailability errors
    is_retryable_error "ServiceUnavailable: Service is temporarily unavailable"
    assert_equals "0" "$?" "Detects 'ServiceUnavailable' error"
    
    is_retryable_error "Service temporarily unavailable"
    assert_equals "0" "$?" "Detects 'temporarily unavailable' error"
    
    is_retryable_error "InternalError: An internal error occurred"
    assert_equals "0" "$?" "Detects 'InternalError' error"
    
    is_retryable_error "Internal error occurred"
    assert_equals "0" "$?" "Detects 'Internal error' error"
}

test_is_retryable_error_non_retryable() {
    echo -e "\n${TEST_YELLOW}Testing is_retryable_error - Non-Retryable Errors${TEST_NC}"
    
    # Test non-retryable errors
    is_retryable_error "ValidationError: Stack does not exist"
    assert_equals "1" "$?" "Rejects 'ValidationError' as non-retryable"
    
    is_retryable_error "AccessDenied: User is not authorized"
    assert_equals "1" "$?" "Rejects 'AccessDenied' as non-retryable"
    
    is_retryable_error "InvalidParameterValue: Invalid parameter"
    assert_equals "1" "$?" "Rejects 'InvalidParameterValue' as non-retryable"
    
    is_retryable_error "ResourceInUseException: Resource is in use"
    assert_equals "1" "$?" "Rejects 'ResourceInUseException' as non-retryable"
    
    is_retryable_error ""
    assert_equals "1" "$?" "Rejects empty error message as non-retryable"
}

test_is_retryable_error_case_insensitive() {
    echo -e "\n${TEST_YELLOW}Testing is_retryable_error - Case Insensitivity${TEST_NC}"
    
    # Test case insensitivity
    is_retryable_error "THROTTLING ERROR"
    assert_equals "0" "$?" "Detects uppercase 'THROTTLING'"
    
    is_retryable_error "Connection Timeout"
    assert_equals "0" "$?" "Detects mixed case 'Connection Timeout'"
    
    is_retryable_error "serviceunavailable"
    assert_equals "0" "$?" "Detects lowercase 'serviceunavailable'"
}

##############################################################################
# Test Cases for calculate_backoff
##############################################################################

test_calculate_backoff() {
    echo -e "\n${TEST_YELLOW}Testing calculate_backoff${TEST_NC}"
    
    # Test exponential backoff calculation
    local backoff1=$(calculate_backoff 1)
    assert_equals "2" "$backoff1" "Attempt 1: 2 seconds"
    
    local backoff2=$(calculate_backoff 2)
    assert_equals "4" "$backoff2" "Attempt 2: 4 seconds"
    
    local backoff3=$(calculate_backoff 3)
    assert_equals "8" "$backoff3" "Attempt 3: 8 seconds"
    
    # Test with custom base backoff
    local backoff_custom=$(calculate_backoff 2 5)
    assert_equals "10" "$backoff_custom" "Custom base (5s), Attempt 2: 10 seconds"
}

##############################################################################
# Test Cases for execute_with_retry
##############################################################################

test_execute_with_retry_success_first_attempt() {
    echo -e "\n${TEST_YELLOW}Testing execute_with_retry - Success on First Attempt${TEST_NC}"
    
    # Test command that succeeds immediately
    local output
    output=$(execute_with_retry echo "test output" 2>&1)
    local exit_code=$?
    
    assert_equals "0" "$exit_code" "Returns 0 on success"
    assert_equals "test output" "$output" "Returns correct output"
}

test_execute_with_retry_non_retryable_error() {
    echo -e "\n${TEST_YELLOW}Testing execute_with_retry - Non-Retryable Error${TEST_NC}"
    
    # Create a mock command that fails with non-retryable error
    local mock_script=$(mktemp)
    cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "ValidationError: Stack does not exist" >&2
exit 1
EOF
    chmod +x "$mock_script"
    
    # Execute with retry (not in subshell to preserve LAST_ERROR_OUTPUT)
    execute_with_retry "$mock_script" > /dev/null 2>&1
    local exit_code=$?
    
    # Check error output was captured (it's in the global LAST_ERROR_OUTPUT)
    local error_captured="false"
    if [[ "$LAST_ERROR_OUTPUT" == *"ValidationError"* ]]; then
        error_captured="true"
    fi
    
    # Clean up
    rm -f "$mock_script"
    
    assert_equals "1" "$exit_code" "Returns 1 on non-retryable error"
    assert_equals "true" "$error_captured" "Captures error output in LAST_ERROR_OUTPUT"
}

test_execute_with_retry_success_after_retry() {
    echo -e "\n${TEST_YELLOW}Testing execute_with_retry - Success After Retry${TEST_NC}"
    
    # Create a mock command that fails once then succeeds
    local counter_file=$(mktemp)
    echo "0" > "$counter_file"
    
    local mock_script=$(mktemp)
    cat > "$mock_script" << EOF
#!/bin/bash
counter=\$(cat "$counter_file")
counter=\$((counter + 1))
echo "\$counter" > "$counter_file"

if [ \$counter -eq 1 ]; then
    echo "Throttling: Rate exceeded" >&2
    exit 1
else
    echo "success"
    exit 0
fi
EOF
    chmod +x "$mock_script"
    
    # Execute with retry (reduce backoff for faster test)
    RETRY_BASE_BACKOFF=1
    local output
    output=$(execute_with_retry "$mock_script" 2>&1)
    local exit_code=$?
    RETRY_BASE_BACKOFF=2  # Reset to default
    
    # Clean up
    rm -f "$mock_script" "$counter_file"
    
    assert_equals "0" "$exit_code" "Returns 0 after successful retry"
    assert_true "[[ \"\$output\" == *\"success\"* ]]" "Returns success output"
}

test_execute_with_retry_max_retries_exhausted() {
    echo -e "\n${TEST_YELLOW}Testing execute_with_retry - Max Retries Exhausted${TEST_NC}"
    
    # Create a mock command that always fails with retryable error
    local mock_script=$(mktemp)
    cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "Throttling: Rate exceeded" >&2
exit 1
EOF
    chmod +x "$mock_script"
    
    # Execute with retry (reduce backoff for faster test)
    RETRY_BASE_BACKOFF=1
    RETRY_MAX_ATTEMPTS=2  # Reduce for faster test
    local output
    output=$(execute_with_retry "$mock_script" 2>&1)
    local exit_code=$?
    RETRY_BASE_BACKOFF=2  # Reset to default
    RETRY_MAX_ATTEMPTS=3  # Reset to default
    
    # Clean up
    rm -f "$mock_script"
    
    assert_equals "1" "$exit_code" "Returns 1 after max retries"
    assert_true "[[ \"\$output\" == *\"All retry attempts exhausted\"* ]]" "Logs retry exhaustion"
}

##############################################################################
# Integration Tests
##############################################################################

test_integration_retry_with_backoff_timing() {
    echo -e "\n${TEST_YELLOW}Testing Integration - Retry with Backoff Timing${TEST_NC}"
    
    # Create a mock command that fails twice then succeeds
    local counter_file=$(mktemp)
    echo "0" > "$counter_file"
    
    local mock_script=$(mktemp)
    cat > "$mock_script" << EOF
#!/bin/bash
counter=\$(cat "$counter_file")
counter=\$((counter + 1))
echo "\$counter" > "$counter_file"

if [ \$counter -lt 3 ]; then
    echo "Throttling: Rate exceeded" >&2
    exit 1
else
    echo "success"
    exit 0
fi
EOF
    chmod +x "$mock_script"
    
    # Execute with retry and measure time (reduce backoff for faster test)
    RETRY_BASE_BACKOFF=1
    local start_time=$(date +%s)
    local output
    output=$(execute_with_retry "$mock_script" 2>&1)
    local exit_code=$?
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    RETRY_BASE_BACKOFF=2  # Reset to default
    
    # Clean up
    rm -f "$mock_script" "$counter_file"
    
    assert_equals "0" "$exit_code" "Returns 0 after retries"
    # Should take at least 3 seconds (1s + 2s backoff)
    assert_true "[ $elapsed -ge 3 ]" "Respects backoff timing (at least 3 seconds)"
}

##############################################################################
# Run All Tests
##############################################################################

main() {
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    echo -e "${TEST_BLUE}        Retry Logic Module - Unit Tests                    ${TEST_NC}"
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    
    # Run all test suites
    test_is_retryable_error_throttling
    test_is_retryable_error_network
    test_is_retryable_error_service_unavailable
    test_is_retryable_error_non_retryable
    test_is_retryable_error_case_insensitive
    test_calculate_backoff
    test_execute_with_retry_success_first_attempt
    test_execute_with_retry_non_retryable_error
    test_execute_with_retry_success_after_retry
    test_execute_with_retry_max_retries_exhausted
    test_integration_retry_with_backoff_timing
    
    # Print summary and exit
    print_test_summary
    exit $?
}

# Run tests
main
