#!/bin/bash

# Property-Based Tests for Cleanup Verification Module
#
# **Property 3: Complete Cleanup Verification**
# **Validates: Requirements 2.5, 6.1, 6.2, 6.3, 6.4, 6.5**
#
# Property Statement:
# For any lab cleanup execution, after all deletion operations complete,
# the cleanup script should query AWS for all resource types (stacks, S3 buckets,
# log groups, Cognito pools) containing the lab identifier and exit with error
# if any remain.
#
# This property test verifies that:
# 1. All resource types are queried (stacks, buckets, logs, Cognito)
# 2. Orphaned resources are detected correctly
# 3. Exit code 3 is returned when orphaned resources exist
# 4. Exit code 0 is returned when all resources are deleted
# 5. Exit code 1 is returned when queries fail
#
# Performance Requirement: MUST complete within 2 minutes
# Optimization: max_examples=5, mocked AWS CLI calls

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
# Property Test Configuration
##############################################################################

# Number of random test cases to generate
# CRITICAL: Keep this low (5) to meet 2-minute performance requirement
MAX_EXAMPLES=5

# Random seed for reproducibility
RANDOM_SEED=42

##############################################################################
# Test Data Generators
##############################################################################

# Generate random lab identifier
generate_lab_id() {
    local lab_num=$((RANDOM % 7 + 1))
    echo "lab${lab_num}"
}

# Generate random stack names
generate_stack_names() {
    local count=$1
    local lab_id=$2
    local stacks=()
    
    for ((i=0; i<count; i++)); do
        local stack_type=$((RANDOM % 3))
        case $stack_type in
            0) stacks+=("serverless-saas-${lab_id}-stack${i}") ;;
            1) stacks+=("serverless-saas-shared-${lab_id}") ;;
            2) stacks+=("serverless-saas-tenant${i}-${lab_id}") ;;
        esac
    done
    
    printf '%s\n' "${stacks[@]}"
}

# Generate random bucket names
generate_bucket_names() {
    local count=$1
    local lab_id=$2
    local buckets=()
    
    for ((i=0; i<count; i++)); do
        local bucket_type=$((RANDOM % 2))
        case $bucket_type in
            0) buckets+=("serverless-saas-${lab_id}-bucket${i}-$(date +%s)") ;;
            1) buckets+=("${lab_id}-deployment-bucket-$(date +%s)") ;;
        esac
    done
    
    printf '%s\n' "${buckets[@]}"
}

# Generate random log group names
generate_log_group_names() {
    local count=$1
    local lab_id=$2
    local log_groups=()
    
    for ((i=0; i<count; i++)); do
        local log_type=$((RANDOM % 3))
        case $log_type in
            0) log_groups+=("/aws/lambda/${lab_id}-function${i}") ;;
            1) log_groups+=("/aws/apigateway/${lab_id}-api") ;;
            2) log_groups+=("/aws/codebuild/${lab_id}-build${i}") ;;
        esac
    done
    
    printf '%s\n' "${log_groups[@]}"
}

# Generate random Cognito pool info
generate_cognito_pool_info() {
    local count=$1
    local lab_id=$2
    local pools=()
    
    for ((i=0; i<count; i++)); do
        local pool_id="us-east-1_$(head /dev/urandom | tr -dc A-Z0-9 | head -c 6)"
        local pool_name="${lab_id}-user-pool${i}"
        pools+=("${pool_id} (${pool_name})")
    done
    
    printf '%s\n' "${pools[@]}"
}

##############################################################################
# Mock AWS CLI for Property Testing
##############################################################################

# Global variables to control mock behavior
MOCK_STACKS=""
MOCK_BUCKETS=""
MOCK_LOG_GROUPS=""
MOCK_COGNITO_POOLS=""
MOCK_SHOULD_FAIL=false

# Mock aws command
aws() {
    if [ "$MOCK_SHOULD_FAIL" = true ]; then
        echo "ERROR: AWS CLI command failed" >&2
        return 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        "cloudformation")
            if [[ "$1" == "list-stacks" ]]; then
                # Parse lab_id from query parameter
                local query_param=""
                for arg in "$@"; do
                    if [[ "$arg" == --query* ]]; then
                        query_param="$arg"
                        break
                    fi
                done
                
                # Return mock stacks in tab-separated format
                echo "$MOCK_STACKS" | tr '\n' '\t'
                return 0
            fi
            ;;
        "s3api")
            if [[ "$1" == "list-buckets" ]]; then
                # Return mock buckets in tab-separated format
                echo "$MOCK_BUCKETS" | tr '\n' '\t'
                return 0
            fi
            ;;
        "logs")
            if [[ "$1" == "describe-log-groups" ]]; then
                # Return mock log groups in JSON format
                if [[ -z "$MOCK_LOG_GROUPS" ]]; then
                    echo '{"logGroups":[]}'
                else
                    local json_groups='{"logGroups":['
                    local first=true
                    while IFS= read -r log_group; do
                        if [ "$first" = true ]; then
                            first=false
                        else
                            json_groups+=','
                        fi
                        json_groups+="{\"logGroupName\":\"$log_group\"}"
                    done <<< "$MOCK_LOG_GROUPS"
                    json_groups+=']}'
                    echo "$json_groups"
                fi
                return 0
            fi
            ;;
        "cognito-idp")
            if [[ "$1" == "list-user-pools" ]]; then
                # Return mock Cognito pools in JSON format
                if [[ -z "$MOCK_COGNITO_POOLS" ]]; then
                    echo '{"UserPools":[]}'
                else
                    local json_pools='{"UserPools":['
                    local first=true
                    while IFS= read -r pool_info; do
                        if [ "$first" = true ]; then
                            first=false
                        else
                            json_pools+=','
                        fi
                        local pool_id=$(echo "$pool_info" | awk '{print $1}')
                        local pool_name=$(echo "$pool_info" | sed 's/^[^ ]* (\(.*\))$/\1/')
                        json_pools+="{\"Id\":\"$pool_id\",\"Name\":\"$pool_name\"}"
                    done <<< "$MOCK_COGNITO_POOLS"
                    json_pools+=']}'
                    echo "$json_pools"
                fi
                return 0
            fi
            ;;
    esac
    
    # Default: command not mocked
    echo "ERROR: Unmocked AWS command: $command $*" >&2
    return 1
}

# Export the mock function
export -f aws

##############################################################################
# Property Test Helper Functions
##############################################################################

# Assert function
assert_property() {
    local condition="$1"
    local test_name="$2"
    local details="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$condition" = true ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [[ -n "$details" ]]; then
            echo -e "${RED}  Details: $details${NC}"
        fi
        return 1
    fi
}

##############################################################################
# Property Tests
##############################################################################

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Cleanup Verification - Property-Based Tests              ${NC}"
echo -e "${BLUE}  Property 3: Complete Cleanup Verification                ${NC}"
echo -e "${BLUE}  Max Examples: ${MAX_EXAMPLES} (optimized for <2min)      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Set random seed for reproducibility
RANDOM=$RANDOM_SEED

##############################################################################
# Property 3.1: All resource types are queried
##############################################################################

echo -e "${YELLOW}Property 3.1: All resource types are queried${NC}"
echo -e "${BLUE}Testing that verify_complete_cleanup queries stacks, buckets, logs, and Cognito${NC}"
echo ""

for ((example=1; example<=MAX_EXAMPLES; example++)); do
    echo -e "${BLUE}Example $example/$MAX_EXAMPLES${NC}"
    
    # Generate test data
    lab_id=$(generate_lab_id)
    
    # Set up mocks with some resources
    MOCK_STACKS=$(generate_stack_names 2 "$lab_id")
    MOCK_BUCKETS=$(generate_bucket_names 1 "$lab_id")
    MOCK_LOG_GROUPS=$(generate_log_group_names 1 "$lab_id")
    MOCK_COGNITO_POOLS=$(generate_cognito_pool_info 1 "$lab_id")
    MOCK_SHOULD_FAIL=false
    
    # Run verification (should detect orphaned resources)
    result=$(verify_complete_cleanup "$lab_id" "" 2>&1)
    exit_code=$?
    
    # Verify all resource types were queried
    has_stacks=$(echo "$result" | grep -c "CloudFormation stacks" || true)
    has_buckets=$(echo "$result" | grep -c "S3 buckets" || true)
    has_logs=$(echo "$result" | grep -c "CloudWatch log groups" || true)
    has_cognito=$(echo "$result" | grep -c "Cognito user pools" || true)
    
    all_queried=false
    if [ $has_stacks -gt 0 ] && [ $has_buckets -gt 0 ] && [ $has_logs -gt 0 ] && [ $has_cognito -gt 0 ]; then
        all_queried=true
    fi
    
    assert_property "$all_queried" "All 4 resource types queried for $lab_id" \
        "Stacks:$has_stacks Buckets:$has_buckets Logs:$has_logs Cognito:$has_cognito"
done

echo ""

##############################################################################
# Property 3.2: Orphaned resources are detected correctly
##############################################################################

echo -e "${YELLOW}Property 3.2: Orphaned resources are detected correctly${NC}"
echo -e "${BLUE}Testing that orphaned resources cause exit code 3${NC}"
echo ""

for ((example=1; example<=MAX_EXAMPLES; example++)); do
    echo -e "${BLUE}Example $example/$MAX_EXAMPLES${NC}"
    
    # Generate test data
    lab_id=$(generate_lab_id)
    resource_count=$((RANDOM % 5 + 1))  # 1-5 orphaned resources
    
    # Set up mocks with orphaned resources
    MOCK_STACKS=$(generate_stack_names $resource_count "$lab_id")
    MOCK_BUCKETS=""
    MOCK_LOG_GROUPS=""
    MOCK_COGNITO_POOLS=""
    MOCK_SHOULD_FAIL=false
    
    # Run verification (should detect orphaned resources)
    result=$(verify_complete_cleanup "$lab_id" "" 2>&1)
    exit_code=$?
    
    # Verify exit code is 3 (orphaned resources)
    correct_exit_code=false
    if [ $exit_code -eq 3 ]; then
        correct_exit_code=true
    fi
    
    assert_property "$correct_exit_code" "Exit code 3 for $resource_count orphaned stack(s)" \
        "Expected: 3, Actual: $exit_code"
    
    # Verify orphaned resources are listed
    has_orphaned_msg=$(echo "$result" | grep -c "Orphaned resources detected" || true)
    orphaned_listed=false
    if [ $has_orphaned_msg -gt 0 ]; then
        orphaned_listed=true
    fi
    
    assert_property "$orphaned_listed" "Orphaned resources listed in output" \
        "Found 'Orphaned resources detected': $has_orphaned_msg"
done

echo ""

##############################################################################
# Property 3.3: Exit code 0 when all resources are deleted
##############################################################################

echo -e "${YELLOW}Property 3.3: Exit code 0 when all resources are deleted${NC}"
echo -e "${BLUE}Testing that clean state returns exit code 0${NC}"
echo ""

for ((example=1; example<=MAX_EXAMPLES; example++)); do
    echo -e "${BLUE}Example $example/$MAX_EXAMPLES${NC}"
    
    # Generate test data
    lab_id=$(generate_lab_id)
    
    # Set up mocks with NO resources (clean state)
    MOCK_STACKS=""
    MOCK_BUCKETS=""
    MOCK_LOG_GROUPS=""
    MOCK_COGNITO_POOLS=""
    MOCK_SHOULD_FAIL=false
    
    # Run verification (should pass)
    result=$(verify_complete_cleanup "$lab_id" "" 2>&1)
    exit_code=$?
    
    # Verify exit code is 0 (success)
    correct_exit_code=false
    if [ $exit_code -eq 0 ]; then
        correct_exit_code=true
    fi
    
    assert_property "$correct_exit_code" "Exit code 0 for clean state ($lab_id)" \
        "Expected: 0, Actual: $exit_code"
    
    # Verify success message
    has_success_msg=$(echo "$result" | grep -c "VERIFICATION PASSED" || true)
    success_shown=false
    if [ $has_success_msg -gt 0 ]; then
        success_shown=true
    fi
    
    assert_property "$success_shown" "Success message shown for clean state" \
        "Found 'VERIFICATION PASSED': $has_success_msg"
done

echo ""

##############################################################################
# Property 3.4: Exit code 1 when queries fail
##############################################################################

echo -e "${YELLOW}Property 3.4: Exit code 1 when queries fail${NC}"
echo -e "${BLUE}Testing that AWS CLI failures return exit code 1${NC}"
echo ""

for ((example=1; example<=MAX_EXAMPLES; example++)); do
    echo -e "${BLUE}Example $example/$MAX_EXAMPLES${NC}"
    
    # Generate test data
    lab_id=$(generate_lab_id)
    
    # Set up mocks to fail
    MOCK_STACKS=""
    MOCK_BUCKETS=""
    MOCK_LOG_GROUPS=""
    MOCK_COGNITO_POOLS=""
    MOCK_SHOULD_FAIL=true
    
    # Run verification (should fail)
    result=$(verify_complete_cleanup "$lab_id" "" 2>&1)
    exit_code=$?
    
    # Verify exit code is 1 (query failed)
    correct_exit_code=false
    if [ $exit_code -eq 1 ]; then
        correct_exit_code=true
    fi
    
    assert_property "$correct_exit_code" "Exit code 1 for query failure ($lab_id)" \
        "Expected: 1, Actual: $exit_code"
    
    # Verify error message
    has_error_msg=$(echo "$result" | grep -c "ERROR" || true)
    error_shown=false
    if [ $has_error_msg -gt 0 ]; then
        error_shown=true
    fi
    
    assert_property "$error_shown" "Error message shown for query failure" \
        "Found 'ERROR': $has_error_msg"
done

echo ""

##############################################################################
# Property 3.5: Multiple resource types detected simultaneously
##############################################################################

echo -e "${YELLOW}Property 3.5: Multiple resource types detected simultaneously${NC}"
echo -e "${BLUE}Testing that all orphaned resource types are reported${NC}"
echo ""

for ((example=1; example<=MAX_EXAMPLES; example++)); do
    echo -e "${BLUE}Example $example/$MAX_EXAMPLES${NC}"
    
    # Generate test data
    lab_id=$(generate_lab_id)
    
    # Set up mocks with multiple resource types
    MOCK_STACKS=$(generate_stack_names 1 "$lab_id")
    MOCK_BUCKETS=$(generate_bucket_names 1 "$lab_id")
    MOCK_LOG_GROUPS=$(generate_log_group_names 1 "$lab_id")
    MOCK_COGNITO_POOLS=$(generate_cognito_pool_info 1 "$lab_id")
    MOCK_SHOULD_FAIL=false
    
    # Run verification (should detect all resource types)
    result=$(verify_complete_cleanup "$lab_id" "" 2>&1)
    exit_code=$?
    
    # Verify exit code is 3 (orphaned resources)
    correct_exit_code=false
    if [ $exit_code -eq 3 ]; then
        correct_exit_code=true
    fi
    
    assert_property "$correct_exit_code" "Exit code 3 for multiple resource types" \
        "Expected: 3, Actual: $exit_code"
    
    # Verify all resource types are mentioned in orphaned list
    has_stack=$(echo "$result" | grep -c "STACK:" || true)
    has_bucket=$(echo "$result" | grep -c "S3_BUCKET:" || true)
    has_log=$(echo "$result" | grep -c "LOG_GROUP:" || true)
    has_pool=$(echo "$result" | grep -c "COGNITO_POOL:" || true)
    
    all_types_reported=false
    if [ $has_stack -gt 0 ] && [ $has_bucket -gt 0 ] && [ $has_log -gt 0 ] && [ $has_pool -gt 0 ]; then
        all_types_reported=true
    fi
    
    assert_property "$all_types_reported" "All 4 resource types reported in orphaned list" \
        "Stack:$has_stack Bucket:$has_bucket Log:$has_log Pool:$has_pool"
done

echo ""

##############################################################################
# Test Summary
##############################################################################

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST SUMMARY                           ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Property: Complete Cleanup Verification${NC}"
echo -e "${BLUE}Examples per property: ${MAX_EXAMPLES}${NC}"
echo -e "${BLUE}Total Tests Run: ${TESTS_RUN}${NC}"
echo -e "${GREEN}Tests Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Tests Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All property tests passed!${NC}"
    echo -e "${GREEN}✓ Property 3 verified across ${MAX_EXAMPLES} random examples${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some property tests failed${NC}"
    echo ""
    exit 1
fi
