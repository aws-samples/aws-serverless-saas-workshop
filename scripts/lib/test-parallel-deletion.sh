#!/bin/bash

################################################################################
# Test Script for Parallel Deletion Module
#
# This script tests the parallel-deletion.sh module with mock operations
################################################################################

# Source the parallel deletion module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/parallel-deletion.sh"

# Mock AWS CLI profile argument
PROFILE_ARG=""
AWS_REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Testing Parallel Deletion Module"
print_message "$BLUE" "=========================================="
echo ""

# Test 1: Test delete_stacks_parallel with mock stacks
print_message "$YELLOW" "Test 1: Testing parallel stack deletion (mock)"
echo "This test will simulate deleting 3 stacks in parallel..."
echo ""

# Override AWS CLI commands for testing
aws() {
    local command=$1
    shift
    
    case "$command" in
        cloudformation)
            local subcommand=$1
            shift
            case "$subcommand" in
                delete-stack)
                    # Extract stack name
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            --stack-name)
                                local stack_name=$2
                                echo "Mock: Initiating deletion for $stack_name"
                                sleep 1  # Simulate API call
                                return 0
                                ;;
                        esac
                        shift
                    done
                    ;;
                wait)
                    local wait_type=$1
                    shift
                    # Extract stack name
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            --stack-name)
                                local stack_name=$2
                                echo "Mock: Waiting for $stack_name to delete..."
                                sleep 2  # Simulate wait time
                                echo "Mock: $stack_name deleted successfully"
                                return 0
                                ;;
                        esac
                        shift
                    done
                    ;;
            esac
            ;;
    esac
    
    return 0
}

export -f aws

# Run the test
if delete_stacks_parallel "mock-stack-1" "mock-stack-2" "mock-stack-3"; then
    print_message "$GREEN" "✓ Test 1 PASSED: Parallel stack deletion completed successfully"
else
    print_message "$RED" "✗ Test 1 FAILED: Parallel stack deletion failed"
    exit 1
fi

echo ""

# Test 2: Test empty_buckets_parallel with mock buckets
print_message "$YELLOW" "Test 2: Testing parallel bucket emptying (mock)"
echo "This test will simulate emptying 2 buckets in parallel..."
echo ""

# Override AWS CLI for S3 operations
aws() {
    local command=$1
    shift
    
    case "$command" in
        s3)
            local subcommand=$1
            shift
            case "$subcommand" in
                ls)
                    # Simulate bucket exists
                    echo "Mock: Bucket exists"
                    return 0
                    ;;
                rm)
                    # Extract bucket name from s3://bucket
                    local bucket_path=$1
                    local bucket_name=$(echo "$bucket_path" | sed 's|s3://||' | cut -d'/' -f1)
                    echo "Mock: Emptying bucket $bucket_name"
                    sleep 1  # Simulate emptying
                    return 0
                    ;;
            esac
            ;;
        s3api)
            local subcommand=$1
            shift
            case "$subcommand" in
                head-bucket)
                    # Simulate bucket exists
                    return 0
                    ;;
            esac
            ;;
    esac
    
    return 0
}

export -f aws

# Run the test
if empty_buckets_parallel "mock-bucket-1" "mock-bucket-2"; then
    print_message "$GREEN" "✓ Test 2 PASSED: Parallel bucket emptying completed successfully"
else
    print_message "$RED" "✗ Test 2 FAILED: Parallel bucket emptying failed"
    exit 1
fi

echo ""

# Test 3: Test delete_buckets_sequential with mock buckets
print_message "$YELLOW" "Test 3: Testing sequential bucket deletion (mock)"
echo "This test will simulate deleting 2 buckets sequentially..."
echo ""

# Override AWS CLI for S3 operations
aws() {
    local command=$1
    shift
    
    case "$command" in
        s3)
            local subcommand=$1
            shift
            case "$subcommand" in
                ls)
                    # Simulate bucket exists
                    echo "Mock: Bucket exists"
                    return 0
                    ;;
                rb)
                    # Extract bucket name from s3://bucket
                    local bucket_path=$1
                    local bucket_name=$(echo "$bucket_path" | sed 's|s3://||')
                    echo "Mock: Deleting bucket $bucket_name"
                    sleep 1  # Simulate deletion
                    return 0
                    ;;
            esac
            ;;
        s3api)
            local subcommand=$1
            shift
            case "$subcommand" in
                head-bucket)
                    # Simulate bucket exists
                    return 0
                    ;;
            esac
            ;;
    esac
    
    return 0
}

export -f aws

# Run the test
if delete_buckets_sequential "mock-bucket-1" "mock-bucket-2"; then
    print_message "$GREEN" "✓ Test 3 PASSED: Sequential bucket deletion completed successfully"
else
    print_message "$RED" "✗ Test 3 FAILED: Sequential bucket deletion failed"
    exit 1
fi

echo ""

# Test 4: Test delete_log_groups_parallel with mock log groups
print_message "$YELLOW" "Test 4: Testing parallel log group deletion (mock)"
echo "This test will simulate deleting 3 log groups in parallel..."
echo ""

# Override AWS CLI for CloudWatch Logs operations
aws() {
    local command=$1
    shift
    
    case "$command" in
        logs)
            local subcommand=$1
            shift
            case "$subcommand" in
                delete-log-group)
                    # Extract log group name
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            --log-group-name)
                                local log_group=$2
                                echo "Mock: Deleting log group $log_group"
                                sleep 1  # Simulate deletion
                                return 0
                                ;;
                        esac
                        shift
                    done
                    ;;
            esac
            ;;
    esac
    
    return 0
}

export -f aws

# Run the test
if delete_log_groups_parallel "/aws/lambda/mock-function-1" "/aws/lambda/mock-function-2" "/aws/lambda/mock-function-3"; then
    print_message "$GREEN" "✓ Test 4 PASSED: Parallel log group deletion completed successfully"
else
    print_message "$RED" "✗ Test 4 FAILED: Parallel log group deletion failed"
    exit 1
fi

echo ""

print_message "$GREEN" "=========================================="
print_message "$GREEN" "All Tests PASSED!"
print_message "$GREEN" "=========================================="
echo ""
print_message "$BLUE" "The parallel-deletion.sh module is working correctly."
print_message "$BLUE" "Ready to integrate into Lab cleanup scripts."

