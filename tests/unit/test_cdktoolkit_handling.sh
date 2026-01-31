#!/bin/bash

# Unit tests for CDKToolkit handling module
# Tests the logic for detecting Lab5/Lab6 pipeline stacks and determining
# when CDKToolkit can be safely deleted

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test-framework.sh"

# Mock AWS CLI for testing
aws() {
    # Check what command is being run
    if [[ "$1" == "cloudformation" && "$2" == "describe-stacks" ]]; then
        # Extract stack name from query parameter
        local query=""
        for arg in "$@"; do
            if [[ "$arg" == *"StackName=="* ]]; then
                query="$arg"
                break
            fi
        done
        
        # Return mock data based on test scenario
        if [[ "$query" == *"serverless-saas-pipeline-lab5"* ]]; then
            if [[ "${MOCK_LAB5_PIPELINE_EXISTS:-false}" == "true" ]]; then
                echo "serverless-saas-pipeline-lab5"
                return 0
            else
                return 255  # Stack not found
            fi
        elif [[ "$query" == *"serverless-saas-shared-lab5"* ]]; then
            if [[ "${MOCK_LAB5_SHARED_EXISTS:-false}" == "true" ]]; then
                echo "serverless-saas-shared-lab5"
                return 0
            else
                return 255  # Stack not found
            fi
        elif [[ "$query" == *"serverless-saas-pipeline-lab6"* ]]; then
            if [[ "${MOCK_LAB6_PIPELINE_EXISTS:-false}" == "true" ]]; then
                echo "serverless-saas-pipeline-lab6"
                return 0
            else
                return 255  # Stack not found
            fi
        elif [[ "$query" == *"serverless-saas-shared-lab6"* ]]; then
            if [[ "${MOCK_LAB6_SHARED_EXISTS:-false}" == "true" ]]; then
                echo "serverless-saas-shared-lab6"
                return 0
            else
                return 255  # Stack not found
            fi
        fi
    fi
    
    # Default: command not found
    return 255
}

# Export mock function
export -f aws

# Source the module under test
source "${SCRIPT_DIR}/../../scripts/lib/cdktoolkit-handling.sh"

# Test 1: check_lab5_pipeline_exists returns 0 when Lab5 pipeline exists
test_check_lab5_pipeline_exists_when_pipeline_exists() {
    export MOCK_LAB5_PIPELINE_EXISTS=true
    export MOCK_LAB5_SHARED_EXISTS=false
    
    if check_lab5_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_success "check_lab5_pipeline_exists should return 0 when pipeline exists"
    else
        assert_failure "check_lab5_pipeline_exists returned non-zero when pipeline exists"
    fi
    
    unset MOCK_LAB5_PIPELINE_EXISTS
    unset MOCK_LAB5_SHARED_EXISTS
}

# Test 2: check_lab5_pipeline_exists returns 0 when Lab5 shared exists
test_check_lab5_pipeline_exists_when_shared_exists() {
    export MOCK_LAB5_PIPELINE_EXISTS=false
    export MOCK_LAB5_SHARED_EXISTS=true
    
    if check_lab5_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_success "check_lab5_pipeline_exists should return 0 when shared stack exists"
    else
        assert_failure "check_lab5_pipeline_exists returned non-zero when shared stack exists"
    fi
    
    unset MOCK_LAB5_PIPELINE_EXISTS
    unset MOCK_LAB5_SHARED_EXISTS
}

# Test 3: check_lab5_pipeline_exists returns 1 when Lab5 not deployed
test_check_lab5_pipeline_exists_when_not_deployed() {
    export MOCK_LAB5_PIPELINE_EXISTS=false
    export MOCK_LAB5_SHARED_EXISTS=false
    
    if check_lab5_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_failure "check_lab5_pipeline_exists should return 1 when Lab5 not deployed"
    else
        assert_success "check_lab5_pipeline_exists correctly returned 1 when Lab5 not deployed"
    fi
    
    unset MOCK_LAB5_PIPELINE_EXISTS
    unset MOCK_LAB5_SHARED_EXISTS
}

# Test 4: check_lab6_pipeline_exists returns 0 when Lab6 pipeline exists
test_check_lab6_pipeline_exists_when_pipeline_exists() {
    export MOCK_LAB6_PIPELINE_EXISTS=true
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if check_lab6_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_success "check_lab6_pipeline_exists should return 0 when pipeline exists"
    else
        assert_failure "check_lab6_pipeline_exists returned non-zero when pipeline exists"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 5: check_lab6_pipeline_exists returns 0 when Lab6 shared exists
test_check_lab6_pipeline_exists_when_shared_exists() {
    export MOCK_LAB6_PIPELINE_EXISTS=false
    export MOCK_LAB6_SHARED_EXISTS=true
    
    if check_lab6_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_success "check_lab6_pipeline_exists should return 0 when shared stack exists"
    else
        assert_failure "check_lab6_pipeline_exists returned non-zero when shared stack exists"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 6: check_lab6_pipeline_exists returns 1 when Lab6 not deployed
test_check_lab6_pipeline_exists_when_not_deployed() {
    export MOCK_LAB6_PIPELINE_EXISTS=false
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if check_lab6_pipeline_exists "" "us-east-1" >/dev/null 2>&1; then
        assert_failure "check_lab6_pipeline_exists should return 1 when Lab6 not deployed"
    else
        assert_success "check_lab6_pipeline_exists correctly returned 1 when Lab6 not deployed"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 7: can_delete_cdktoolkit returns 0 for Lab5 cleanup when Lab6 not deployed
test_can_delete_cdktoolkit_lab5_cleanup_lab6_not_deployed() {
    export MOCK_LAB6_PIPELINE_EXISTS=false
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if can_delete_cdktoolkit "lab5" "" "us-east-1" >/dev/null 2>&1; then
        assert_success "can_delete_cdktoolkit should return 0 for Lab5 cleanup when Lab6 not deployed"
    else
        assert_failure "can_delete_cdktoolkit returned non-zero for Lab5 cleanup when Lab6 not deployed"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 8: can_delete_cdktoolkit returns 1 for Lab5 cleanup when Lab6 deployed
test_can_delete_cdktoolkit_lab5_cleanup_lab6_deployed() {
    export MOCK_LAB6_PIPELINE_EXISTS=true
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if can_delete_cdktoolkit "lab5" "" "us-east-1" >/dev/null 2>&1; then
        assert_failure "can_delete_cdktoolkit should return 1 for Lab5 cleanup when Lab6 deployed"
    else
        assert_success "can_delete_cdktoolkit correctly returned 1 for Lab5 cleanup when Lab6 deployed"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 9: can_delete_cdktoolkit returns 0 for Lab6 cleanup when Lab5 not deployed
test_can_delete_cdktoolkit_lab6_cleanup_lab5_not_deployed() {
    export MOCK_LAB5_PIPELINE_EXISTS=false
    export MOCK_LAB5_SHARED_EXISTS=false
    
    if can_delete_cdktoolkit "lab6" "" "us-east-1" >/dev/null 2>&1; then
        assert_success "can_delete_cdktoolkit should return 0 for Lab6 cleanup when Lab5 not deployed"
    else
        assert_failure "can_delete_cdktoolkit returned non-zero for Lab6 cleanup when Lab5 not deployed"
    fi
    
    unset MOCK_LAB5_PIPELINE_EXISTS
    unset MOCK_LAB5_SHARED_EXISTS
}

# Test 10: can_delete_cdktoolkit returns 1 for Lab6 cleanup when Lab5 deployed
test_can_delete_cdktoolkit_lab6_cleanup_lab5_deployed() {
    export MOCK_LAB5_PIPELINE_EXISTS=true
    export MOCK_LAB5_SHARED_EXISTS=false
    
    if can_delete_cdktoolkit "lab6" "" "us-east-1" >/dev/null 2>&1; then
        assert_failure "can_delete_cdktoolkit should return 1 for Lab6 cleanup when Lab5 deployed"
    else
        assert_success "can_delete_cdktoolkit correctly returned 1 for Lab6 cleanup when Lab5 deployed"
    fi
    
    unset MOCK_LAB5_PIPELINE_EXISTS
    unset MOCK_LAB5_SHARED_EXISTS
}

# Test 11: handle_cdktoolkit_deletion returns 0 when safe to delete
test_handle_cdktoolkit_deletion_safe_to_delete() {
    export MOCK_LAB6_PIPELINE_EXISTS=false
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if handle_cdktoolkit_deletion "lab5" "" "us-east-1" >/dev/null 2>&1; then
        assert_success "handle_cdktoolkit_deletion should return 0 when safe to delete"
    else
        assert_failure "handle_cdktoolkit_deletion returned non-zero when safe to delete"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Test 12: handle_cdktoolkit_deletion returns 1 when should skip
test_handle_cdktoolkit_deletion_should_skip() {
    export MOCK_LAB6_PIPELINE_EXISTS=true
    export MOCK_LAB6_SHARED_EXISTS=false
    
    if handle_cdktoolkit_deletion "lab5" "" "us-east-1" >/dev/null 2>&1; then
        assert_failure "handle_cdktoolkit_deletion should return 1 when should skip"
    else
        assert_success "handle_cdktoolkit_deletion correctly returned 1 when should skip"
    fi
    
    unset MOCK_LAB6_PIPELINE_EXISTS
    unset MOCK_LAB6_SHARED_EXISTS
}

# Run all tests
run_test_suite "CDKToolkit Handling Module" \
    test_check_lab5_pipeline_exists_when_pipeline_exists \
    test_check_lab5_pipeline_exists_when_shared_exists \
    test_check_lab5_pipeline_exists_when_not_deployed \
    test_check_lab6_pipeline_exists_when_pipeline_exists \
    test_check_lab6_pipeline_exists_when_shared_exists \
    test_check_lab6_pipeline_exists_when_not_deployed \
    test_can_delete_cdktoolkit_lab5_cleanup_lab6_not_deployed \
    test_can_delete_cdktoolkit_lab5_cleanup_lab6_deployed \
    test_can_delete_cdktoolkit_lab6_cleanup_lab5_not_deployed \
    test_can_delete_cdktoolkit_lab6_cleanup_lab5_deployed \
    test_handle_cdktoolkit_deletion_safe_to_delete \
    test_handle_cdktoolkit_deletion_should_skip
