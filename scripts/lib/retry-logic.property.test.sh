#!/bin/bash

# Property-Based Tests for Retry Logic Module
#
# **Feature: lab-cleanup-isolation-all-labs**
# **Property 6: Retry with Exponential Backoff**
# **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**
#
# This test suite validates universal properties of the retry logic:
# - Retryable errors always trigger retry (up to max attempts)
# - Backoff timing follows exponential pattern (2s, 4s, 8s)
# - Max retries are always respected
# - Retry attempts are always logged
# - Final error is always logged when retries exhausted
#
# PERFORMANCE REQUIREMENT: Must complete within 2 minutes maximum

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

assert_property() {
    local condition="$1"
    local property_name="$2"
    local test_case="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${TEST_GREEN}✓ PASS${TEST_NC}: $property_name - $test_case"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${TEST_RED}✗ FAIL${TEST_NC}: $property_name - $test_case"
        echo -e "${TEST_RED}  Property violated: $condition${TEST_NC}"
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
        echo -e "${TEST_GREEN}All property tests passed!${TEST_NC}"
        echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
        return 0
    else
        echo -e "${TEST_RED}Some property tests failed!${TEST_NC}"
        echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
        return 1
    fi
}

##############################################################################
# Property Test Generators
##############################################################################

# Generate random retryable error messages
generate_retryable_error() {
    local error_types=(
        "Throttling: Rate exceeded"
        "TooManyRequests: Too many requests"
        "Connection timeout"
        "Network error occurred"
        "ServiceUnavailable: Service temporarily unavailable"
        "InternalError: An internal error occurred"
    )
    
    local random_index=$((RANDOM % ${#error_types[@]}))
    echo "${error_types[$random_index]}"
}

# Generate random non-retryable error messages
generate_non_retryable_error() {
    local error_types=(
        "ValidationError: Stack does not exist"
        "AccessDenied: User is not authorized"
        "InvalidParameterValue: Invalid parameter"
        "ResourceInUseException: Resource is in use"
    )
    
    local random_index=$((RANDOM % ${#error_types[@]}))
    echo "${error_types[$random_index]}"
}

##############################################################################
# Property 6: Retry with Exponential Backoff
# Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5
##############################################################################

property_retryable_errors_trigger_retry() {
    echo -e "\n${TEST_YELLOW}Property 6.1: Retryable errors always trigger retry${TEST_NC}"
    
    # Test with 5 random retryable errors
    for i in {1..5}; do
        local error_msg=$(generate_retryable_error)
        
        # Create mock command that fails with retryable error
        local mock_script=$(mktemp)
        cat > "$mock_script" << EOF
#!/bin/bash
echo "$error_msg" >&2
exit 1
EOF
        chmod +x "$mock_script"
        
        # Execute with retry (reduce attempts for speed)
        RETRY_MAX_ATTEMPTS=2
        RETRY_BASE_BACKOFF=1
        local output
        output=$(execute_with_retry "$mock_script" 2>&1)
        local exit_code=$?
        RETRY_MAX_ATTEMPTS=3
        RETRY_BASE_BACKOFF=2
        
        # Clean up
        rm -f "$mock_script"
        
        # Property: Retryable errors should trigger retry (output contains "Retry attempt")
        assert_property "[[ \"\$output\" == *\"Retry attempt\"* ]]" \
            "Property 6.1" \
            "Retryable error triggers retry: $error_msg"
    done
}

property_backoff_timing_exponential() {
    echo -e "\n${TEST_YELLOW}Property 6.2: Backoff timing follows exponential pattern${TEST_NC}"
    
    # Test backoff calculation for multiple attempts
    for attempt in {1..3}; do
        local backoff=$(calculate_backoff $attempt)
        local expected=$((2 ** (attempt - 1) * 2))
        
        assert_property "[ $backoff -eq $expected ]" \
            "Property 6.2" \
            "Attempt $attempt: backoff=$backoff equals expected=$expected"
    done
    
    # Test with custom base backoff
    for base in 1 3 5; do
        local backoff=$(calculate_backoff 2 $base)
        local expected=$((base * 2))
        
        assert_property "[ $backoff -eq $expected ]" \
            "Property 6.2" \
            "Custom base=$base, Attempt 2: backoff=$backoff equals expected=$expected"
    done
}

property_max_retries_respected() {
    echo -e "\n${TEST_YELLOW}Property 6.3: Max retries are always respected${TEST_NC}"
    
    # Test with different max retry values
    for max_attempts in 1 2 3; do
        # Create mock command that always fails with retryable error
        local mock_script=$(mktemp)
        cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "Throttling: Rate exceeded" >&2
exit 1
EOF
        chmod +x "$mock_script"
        
        # Execute with retry
        RETRY_MAX_ATTEMPTS=$max_attempts
        RETRY_BASE_BACKOFF=1
        local output
        output=$(execute_with_retry "$mock_script" 2>&1)
        RETRY_MAX_ATTEMPTS=3
        RETRY_BASE_BACKOFF=2
        
        # Clean up
        rm -f "$mock_script"
        
        # Property: Should see exactly max_attempts retry messages
        # Count lines containing "Retry attempt" (grep -c counts lines, not occurrences)
        local retry_count=0
        if echo "$output" | grep -q "Retry attempt"; then
            retry_count=$(echo "$output" | grep "Retry attempt" | wc -l | tr -d ' ')
        fi
        
        # Expected retry count is max_attempts - 1 (first attempt is not a retry)
        local expected_retries=$((max_attempts - 1))
        
        assert_property "[ \"$retry_count\" -eq \"$expected_retries\" ]" \
            "Property 6.3" \
            "Max attempts=$max_attempts: retry_count=$retry_count (expected $expected_retries)"
    done
}

property_retry_attempts_logged() {
    echo -e "\n${TEST_YELLOW}Property 6.4: Retry attempts are always logged${TEST_NC}"
    
    # Test with 3 random retryable errors
    for i in {1..3}; do
        local error_msg=$(generate_retryable_error)
        
        # Create mock command that fails twice then succeeds
        local counter_file=$(mktemp)
        echo "0" > "$counter_file"
        
        local mock_script=$(mktemp)
        cat > "$mock_script" << EOF
#!/bin/bash
counter=\$(cat "$counter_file")
counter=\$((counter + 1))
echo "\$counter" > "$counter_file"

if [ \$counter -lt 2 ]; then
    echo "$error_msg" >&2
    exit 1
else
    echo "success"
    exit 0
fi
EOF
        chmod +x "$mock_script"
        
        # Execute with retry
        RETRY_BASE_BACKOFF=1
        local output
        output=$(execute_with_retry "$mock_script" 2>&1)
        RETRY_BASE_BACKOFF=2
        
        # Clean up
        rm -f "$mock_script" "$counter_file"
        
        # Property: Output should contain retry attempt number and reason
        assert_property "[[ \"\$output\" == *\"Retry attempt 1\"* ]]" \
            "Property 6.4" \
            "Logs retry attempt number"
        
        assert_property "[[ \"\$output\" == *\"Reason:\"* ]]" \
            "Property 6.4" \
            "Logs retry reason"
        
        assert_property "[[ \"\$output\" == *\"Waiting\"*\"seconds\"* ]]" \
            "Property 6.4" \
            "Logs backoff duration"
    done
}

property_final_error_logged() {
    echo -e "\n${TEST_YELLOW}Property 6.5: Final error logged when retries exhausted${TEST_NC}"
    
    # Test with 3 random retryable errors
    for i in {1..3}; do
        local error_msg=$(generate_retryable_error)
        
        # Create mock command that always fails
        local mock_script=$(mktemp)
        cat > "$mock_script" << EOF
#!/bin/bash
echo "$error_msg" >&2
exit 1
EOF
        chmod +x "$mock_script"
        
        # Execute with retry
        RETRY_MAX_ATTEMPTS=2
        RETRY_BASE_BACKOFF=1
        local output
        output=$(execute_with_retry "$mock_script" 2>&1)
        RETRY_MAX_ATTEMPTS=3
        RETRY_BASE_BACKOFF=2
        
        # Clean up
        rm -f "$mock_script"
        
        # Property: Output should contain "All retry attempts exhausted"
        assert_property "[[ \"\$output\" == *\"All retry attempts exhausted\"* ]]" \
            "Property 6.5" \
            "Logs retry exhaustion message"
        
        # Property: Output should contain total attempts
        assert_property "[[ \"\$output\" == *\"Total attempts:\"* ]]" \
            "Property 6.5" \
            "Logs total attempts made"
        
        # Property: Output should contain final error
        assert_property "[[ \"\$output\" == *\"Final error:\"* ]]" \
            "Property 6.5" \
            "Logs final error message"
    done
}

property_non_retryable_errors_fail_immediately() {
    echo -e "\n${TEST_YELLOW}Property 6.6: Non-retryable errors fail immediately${TEST_NC}"
    
    # Test with 5 random non-retryable errors
    for i in {1..5}; do
        local error_msg=$(generate_non_retryable_error)
        
        # Create mock command that fails with non-retryable error
        local mock_script=$(mktemp)
        cat > "$mock_script" << EOF
#!/bin/bash
echo "$error_msg" >&2
exit 1
EOF
        chmod +x "$mock_script"
        
        # Execute with retry
        RETRY_BASE_BACKOFF=1
        local start_time=$(date +%s)
        local output
        output=$(execute_with_retry "$mock_script" 2>&1)
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        RETRY_BASE_BACKOFF=2
        
        # Clean up
        rm -f "$mock_script"
        
        # Property: Should NOT contain "Retry attempt" (no retry)
        assert_property "[[ \"\$output\" != *\"Retry attempt\"* ]]" \
            "Property 6.6" \
            "Non-retryable error does not trigger retry: $error_msg"
        
        # Property: Should complete quickly (< 2 seconds, no backoff)
        assert_property "[ $elapsed -lt 2 ]" \
            "Property 6.6" \
            "Fails immediately without backoff (elapsed=${elapsed}s)"
    done
}

##############################################################################
# Run All Property Tests
##############################################################################

main() {
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    echo -e "${TEST_BLUE}   Retry Logic Module - Property-Based Tests              ${TEST_NC}"
    echo -e "${TEST_BLUE}   Feature: lab-cleanup-isolation-all-labs                ${TEST_NC}"
    echo -e "${TEST_BLUE}   Property 6: Retry with Exponential Backoff             ${TEST_NC}"
    echo -e "${TEST_BLUE}   Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5        ${TEST_NC}"
    echo -e "${TEST_BLUE}═══════════════════════════════════════════════════════════${TEST_NC}"
    
    local start_time=$(date +%s)
    
    # Run all property tests
    property_retryable_errors_trigger_retry
    property_backoff_timing_exponential
    property_max_retries_respected
    property_retry_attempts_logged
    property_final_error_logged
    property_non_retryable_errors_fail_immediately
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    echo -e "${TEST_BLUE}Total execution time: ${total_time} seconds${TEST_NC}"
    
    # Check performance requirement (must complete within 2 minutes)
    if [ $total_time -gt 120 ]; then
        echo -e "${TEST_RED}⚠ WARNING: Tests exceeded 2-minute performance requirement!${TEST_NC}"
        echo -e "${TEST_RED}  Actual: ${total_time}s, Required: ≤120s${TEST_NC}"
    else
        echo -e "${TEST_GREEN}✓ Performance requirement met (${total_time}s ≤ 120s)${TEST_NC}"
    fi
    
    # Print summary and exit
    print_test_summary
    exit $?
}

# Run tests
main
