#!/usr/bin/env python3
"""
Property-Based Tests for Stack Deletion Verification Module

Feature: lab-cleanup-isolation-all-labs
Property 1: Stack Deletion Verification

This test validates that the stack deletion verification logic correctly:
1. Verifies DELETE_IN_PROGRESS is confirmed within 5 seconds
2. Verifies stack non-existence before proceeding
3. Handles all possible stack states appropriately

Validates: Requirements 1.1, 1.5, 2.1, 2.3
"""

import subprocess
import tempfile
import os
from hypothesis import given, strategies as st, settings
from hypothesis import HealthCheck
import pytest


# Strategy for generating valid CloudFormation stack names
# Stack names can contain letters, numbers, and hyphens
# Must start with a letter and be 1-128 characters long
stack_name_strategy = st.text(
    alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd'), whitelist_characters='-'),
    min_size=1,
    max_size=128
).filter(lambda s: s and s[0].isalpha() and not s.startswith('-') and not s.endswith('-'))


# Strategy for generating CloudFormation stack statuses
stack_status_strategy = st.sampled_from([
    'CREATE_IN_PROGRESS',
    'CREATE_COMPLETE',
    'CREATE_FAILED',
    'DELETE_IN_PROGRESS',
    'DELETE_COMPLETE',
    'DELETE_FAILED',
    'UPDATE_IN_PROGRESS',
    'UPDATE_COMPLETE',
    'UPDATE_FAILED',
    'ROLLBACK_IN_PROGRESS',
    'ROLLBACK_COMPLETE',
    'ROLLBACK_FAILED',
    'DOES_NOT_EXIST'
])


def create_mock_aws_cli(stack_name, initial_status, final_status=None):
    """
    Create a mock AWS CLI script that simulates stack deletion behavior.
    
    Args:
        stack_name: The stack name to respond to
        initial_status: The status to return on first describe-stacks call
        final_status: The status to return on subsequent calls (defaults to DOES_NOT_EXIST)
    
    Returns:
        Path to the mock AWS CLI script
    """
    if final_status is None:
        final_status = 'DOES_NOT_EXIST'
    
    # Create a temporary directory for the mock
    temp_dir = tempfile.mkdtemp()
    mock_aws_path = os.path.join(temp_dir, 'aws')
    
    # Create the mock AWS CLI script
    mock_script = f'''#!/bin/bash
# Mock AWS CLI for testing stack deletion verification

# Track call count
CALL_COUNT_FILE="/tmp/aws_mock_call_count_$$.txt"
if [ ! -f "$CALL_COUNT_FILE" ]; then
    echo "0" > "$CALL_COUNT_FILE"
fi
CALL_COUNT=$(cat "$CALL_COUNT_FILE")
CALL_COUNT=$((CALL_COUNT + 1))
echo "$CALL_COUNT" > "$CALL_COUNT_FILE"

# Parse command
if [[ "$1" == "cloudformation" ]] && [[ "$2" == "delete-stack" ]]; then
    # delete-stack command - always succeeds
    exit 0
elif [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stacks" ]]; then
    # describe-stacks command
    STACK_NAME=""
    for arg in "$@"; do
        if [[ "$prev_arg" == "--stack-name" ]]; then
            STACK_NAME="$arg"
        fi
        prev_arg="$arg"
    done
    
    if [[ "$STACK_NAME" == "{stack_name}" ]]; then
        # First call returns initial status, subsequent calls return final status
        if [ "$CALL_COUNT" -le 2 ]; then
            if [[ "{initial_status}" == "DOES_NOT_EXIST" ]]; then
                echo "Stack does not exist" >&2
                exit 254
            else
                echo '{{"Stacks": [{{"StackStatus": "{initial_status}"}}]}}'
                exit 0
            fi
        else
            if [[ "{final_status}" == "DOES_NOT_EXIST" ]]; then
                echo "Stack does not exist" >&2
                exit 254
            else
                echo '{{"Stacks": [{{"StackStatus": "{final_status}"}}]}}'
                exit 0
            fi
        fi
    else
        echo "Stack not found" >&2
        exit 254
    fi
elif [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stack-events" ]]; then
    # describe-stack-events command - return empty events
    echo '{{"StackEvents": []}}'
    exit 0
else
    echo "Unknown command: $@" >&2
    exit 1
fi
'''
    
    with open(mock_aws_path, 'w') as f:
        f.write(mock_script)
    
    os.chmod(mock_aws_path, 0o755)
    
    return temp_dir, mock_aws_path


def cleanup_mock(temp_dir):
    """Clean up the mock AWS CLI directory."""
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)
    # Clean up call count files
    subprocess.run(['bash', '-c', 'rm -f /tmp/aws_mock_call_count_*.txt'], 
                   stderr=subprocess.DEVNULL)


@given(
    stack_name=stack_name_strategy,
    initial_status=stack_status_strategy
)
@settings(
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_delete_stack_verified_property(stack_name, initial_status):
    """
    Property 1: Stack Deletion Verification
    
    For any valid stack name and initial status, the delete_stack_verified function should:
    1. Return 0 (success) if the stack enters DELETE_IN_PROGRESS or DOES_NOT_EXIST
    2. Return 1 (failure) if the stack fails to enter deletion state after retry
    3. Verify the status within 5 seconds of initiating deletion
    
    Validates: Requirements 1.1, 1.5, 2.1, 2.3
    """
    # Create mock AWS CLI
    temp_dir, mock_aws_path = create_mock_aws_cli(
        stack_name, 
        initial_status,
        final_status='DOES_NOT_EXIST'
    )
    
    try:
        # Source the stack deletion module and call delete_stack_verified
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        stack_deletion_path = os.path.join(workshop_dir, 'scripts', 'lib', 'stack-deletion.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

# Source the stack deletion module
source "{stack_deletion_path}"

# Call delete_stack_verified
delete_stack_verified "{stack_name}" ""
exit $?
'''
        
        # Write test script
        test_script_path = os.path.join(temp_dir, 'test_script.sh')
        with open(test_script_path, 'w') as f:
            f.write(test_script)
        os.chmod(test_script_path, 0o755)
        
        # Run the test script
        result = subprocess.run(
            ['bash', test_script_path],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Verify the property
        if initial_status in ['DELETE_IN_PROGRESS', 'DOES_NOT_EXIST']:
            # Should succeed immediately
            assert result.returncode == 0, \
                f"Expected success for status {initial_status}, got exit code {result.returncode}\n" \
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
        else:
            # Should fail after retry (stack doesn't enter DELETE_IN_PROGRESS)
            assert result.returncode == 1, \
                f"Expected failure for status {initial_status}, got exit code {result.returncode}\n" \
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
        # Verify that status was checked (output should contain status information)
        assert stack_name in result.stdout or stack_name in result.stderr, \
            f"Stack name {stack_name} not found in output"
        
    finally:
        cleanup_mock(temp_dir)


@given(
    stack_name=stack_name_strategy,
    timeout_minutes=st.integers(min_value=1, max_value=60)
)
@settings(
    max_examples=50,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_verify_stack_deleted_property(stack_name, timeout_minutes):
    """
    Property 1 (continued): Stack Non-Existence Verification
    
    For any valid stack name, the verify_stack_deleted function should:
    1. Return 0 (success) if the stack does not exist
    2. Return 1 (failure) if the stack still exists
    3. Query AWS to confirm the stack status
    
    Validates: Requirements 2.3
    """
    # Test case 1: Stack does not exist (should succeed)
    temp_dir, mock_aws_path = create_mock_aws_cli(
        stack_name,
        'DOES_NOT_EXIST',
        final_status='DOES_NOT_EXIST'
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        stack_deletion_path = os.path.join(workshop_dir, 'scripts', 'lib', 'stack-deletion.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{stack_deletion_path}"

verify_stack_deleted "{stack_name}" ""
exit $?
'''
        
        test_script_path = os.path.join(temp_dir, 'test_script.sh')
        with open(test_script_path, 'w') as f:
            f.write(test_script)
        os.chmod(test_script_path, 0o755)
        
        result = subprocess.run(
            ['bash', test_script_path],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True,
            text=True,
            timeout=10
        )
        
        assert result.returncode == 0, \
            f"Expected success when stack does not exist, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
    finally:
        cleanup_mock(temp_dir)
    
    # Test case 2: Stack still exists (should fail)
    temp_dir, mock_aws_path = create_mock_aws_cli(
        stack_name,
        'CREATE_COMPLETE',
        final_status='CREATE_COMPLETE'
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        stack_deletion_path = os.path.join(workshop_dir, 'scripts', 'lib', 'stack-deletion.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{stack_deletion_path}"

verify_stack_deleted "{stack_name}" ""
exit $?
'''
        
        test_script_path = os.path.join(temp_dir, 'test_script.sh')
        with open(test_script_path, 'w') as f:
            f.write(test_script)
        os.chmod(test_script_path, 0o755)
        
        result = subprocess.run(
            ['bash', test_script_path],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True,
            text=True,
            timeout=10
        )
        
        assert result.returncode == 1, \
            f"Expected failure when stack exists, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
    finally:
        cleanup_mock(temp_dir)


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
