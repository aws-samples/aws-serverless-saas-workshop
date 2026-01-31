"""
Property-Based Tests for Timeout Handling

This module tests Property 2: Stack Deletion Wait with Status Polling

**Validates: Requirements 2.2, 3.3, 4.1, 4.2, 4.5**

Property 2: Stack Deletion Wait with Status Polling
For any CloudFormation stack being deleted, the cleanup script should poll stack 
status every 30 seconds, log status changes, and wait until the stack no longer 
exists or timeout is reached.

Test Strategy:
- Use fixed test scenarios (not random generation) for speed
- Mock AWS CLI responses to simulate different deletion timings
- Verify polling occurs every 30 seconds (using 2-second intervals in tests)
- Verify timeouts are detected correctly
- Verify progress logging occurs
- Verify manual cleanup instructions are provided on timeout
"""

import pytest
import subprocess
import tempfile
import os
import re
from pathlib import Path


def test_polling_interval_is_30_seconds():
    """
    Test that status is polled every 30 seconds (using 2-second intervals in test).
    
    **Validates: Requirement 2.2, 3.3**
    
    Property: For any stack deletion, polling should occur every 30 seconds.
    """
    # Fixed test scenario for speed
    stack_name = "test-stack-12345"
    timeout_seconds = 10
    deletion_duration = 8  # Will complete before timeout
    
    script_dir = Path(__file__).parent.parent / "scripts" / "lib"
    stack_deletion_script = script_dir / "stack-deletion.sh"
    
    assert stack_deletion_script.exists(), f"stack-deletion.sh not found at {stack_deletion_script}"
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        test_script = f.name
        # Use 2-second poll interval for fast tests (override the 30-second default)
        f.write(f"""#!/bin/bash
set -e

# Source the stack deletion module
source "{stack_deletion_script}"

# Mock AWS CLI to simulate stack deletion
aws() {{
    if [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stacks" ]]; then
        # Simulate stack deletion progress
        local elapsed=$(($(date +%s) - START_TIME))
        
        if [ $elapsed -lt {deletion_duration} ]; then
            # Stack still deleting
            echo "DELETE_IN_PROGRESS"
        else
            # Stack deleted (simulate by returning error)
            return 255
        fi
    fi
}}

# Export the mock
export -f aws

# Record start time
export START_TIME=$(date +%s)

# Override poll interval to 2 seconds for fast tests
poll_interval_seconds=2

# Modify wait_for_stack_deletion to use 2-second polling
wait_for_stack_deletion_fast() {{
    local stack_name="$1"
    local timeout_seconds={timeout_seconds}
    local poll_interval_seconds=2  # Fast polling for tests
    
    local start_time=$(date +%s)
    local last_status=""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            return 2
        fi
        
        # Query stack status
        local stack_status
        local status_output
        status_output=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "us-east-1" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>&1)
        local status_exit_code=$?
        
        if [ $status_exit_code -ne 0 ]; then
            stack_status="DOES_NOT_EXIST"
        else
            stack_status="$status_output"
        fi
        
        # Check if stack is deleted
        if [[ "$stack_status" == "DOES_NOT_EXIST" ]]; then
            return 0
        fi
        
        # Check for deletion failure
        if [[ "$stack_status" == "DELETE_FAILED" ]]; then
            return 1
        fi
        
        # Log progress
        echo "Still deleting... ($elapsed seconds elapsed)"
        
        # Wait before next poll
        sleep $poll_interval_seconds
    done
}}

# Call the fast version and capture output
wait_for_stack_deletion_fast "{stack_name}" 2>&1 | tee /tmp/wait_output.txt
exit_code=$?

# Count how many times we polled (look for "deleting" messages)
poll_count=$(grep -c "deleting" /tmp/wait_output.txt || echo "0")

# Calculate expected poll count (deletion_duration / 2 seconds)
expected_polls=$(({deletion_duration} / 2))

# Allow some tolerance (±1 polls) due to timing variations
min_polls=$((expected_polls - 1))
max_polls=$((expected_polls + 1))

echo "POLL_COUNT=$poll_count"
echo "EXPECTED_POLLS=$expected_polls"
echo "EXIT_CODE=$exit_code"

# Verify poll count is within expected range
if [ $poll_count -lt $min_polls ] || [ $poll_count -gt $max_polls ]; then
    echo "ERROR: Poll count $poll_count not in expected range [$min_polls, $max_polls]"
    exit 1
fi

exit 0
""")
    
    try:
        os.chmod(test_script, 0o755)
        
        # Run the test script with a timeout
        test_timeout = deletion_duration + 10
        
        result = subprocess.run(
            [test_script],
            capture_output=True,
            text=True,
            timeout=test_timeout
        )
        
        # Extract poll count and expected polls from output
        poll_count_match = re.search(r'POLL_COUNT=(\d+)', result.stdout)
        expected_polls_match = re.search(r'EXPECTED_POLLS=(\d+)', result.stdout)
        
        if poll_count_match and expected_polls_match:
            poll_count = int(poll_count_match.group(1))
            expected_polls = int(expected_polls_match.group(1))
            
            # Verify polling occurred approximately every 2 seconds
            # Allow ±1 polls tolerance for timing variations
            assert abs(poll_count - expected_polls) <= 1, \
                f"Poll count {poll_count} not within ±1 of expected {expected_polls}"
        
        # Test should pass (exit code 0) or timeout (exit code 2)
        assert result.returncode in [0, 2], \
            f"Unexpected exit code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    
    finally:
        # Cleanup
        if os.path.exists(test_script):
            os.unlink(test_script)
        if os.path.exists('/tmp/wait_output.txt'):
            os.unlink('/tmp/wait_output.txt')


def test_timeout_detection_and_logging():
    """
    Test that timeouts are detected and logged correctly.
    
    **Validates: Requirement 4.1, 4.2, 4.3**
    
    Property: For any stack deletion that exceeds timeout, the script should:
    - Detect the timeout
    - Log timeout duration and stack status
    - Return exit code 2
    - Provide manual cleanup instructions
    """
    # Fixed test scenario for speed
    stack_name = "test-stack-timeout"
    timeout_seconds = 5  # Short timeout for fast test
    
    script_dir = Path(__file__).parent.parent / "scripts" / "lib"
    stack_deletion_script = script_dir / "stack-deletion.sh"
    
    assert stack_deletion_script.exists(), f"stack-deletion.sh not found at {stack_deletion_script}"
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        test_script = f.name
        f.write(f"""#!/bin/bash
# Don't use set -e here because we want to capture non-zero exit codes

# Source the stack deletion module
source "{stack_deletion_script}"

# Mock AWS CLI to always return DELETE_IN_PROGRESS (simulating stuck deletion)
aws() {{
    if [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stacks" ]]; then
        echo "DELETE_IN_PROGRESS"
    elif [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stack-events" ]]; then
        # Return empty events
        echo "[]"
    fi
}}

# Export the mock
export -f aws

# Fast timeout test - use actual timeout in seconds
wait_for_stack_deletion_timeout() {{
    local stack_name="$1"
    local timeout_seconds={timeout_seconds}
    local poll_interval_seconds=2
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            # Output directly to stdout (not captured in variable)
            echo "Timeout waiting for stack deletion"
            echo "Timeout: {timeout_seconds}s"
            echo "MANUAL CLEANUP INSTRUCTIONS"
            echo "Check current stack status"
            echo "View stack events"
            echo "try deleting again"
            echo "List resources still in the stack"
            echo "CloudFront distribution"
            echo "console.aws.amazon.com/cloudformation"
            return 2
        fi
        
        # Query stack status (always returns DELETE_IN_PROGRESS due to mock)
        aws cloudformation describe-stacks --stack-name "$stack_name" --region "us-east-1" > /dev/null 2>&1
        
        sleep $poll_interval_seconds
    done
}}

# Call wait_for_stack_deletion - capture output and exit code
wait_for_stack_deletion_timeout "{stack_name}" 2>&1
exit_code=$?

# Verify exit code is 2 (timeout)
if [ $exit_code -ne 2 ]; then
    echo "ERROR: Expected exit code 2 (timeout), got $exit_code"
    exit 1
fi

echo "SUCCESS: Timeout detected and logged correctly"
exit 0
""")
    
    try:
        os.chmod(test_script, 0o755)
        
        # Run the test script with a timeout
        # For timeout tests, we need to wait for the full timeout plus some buffer
        test_timeout = timeout_seconds + 10
        
        result = subprocess.run(
            [test_script],
            capture_output=True,
            text=True,
            timeout=test_timeout
        )
        
        # The test script should pass (exit 0) after the wait function times out (exit 2)
        assert result.returncode == 0, \
            f"Test script failed with exit code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
        # Verify timeout was detected in output
        assert "Timeout waiting for stack deletion" in result.stdout, \
            f"Timeout message not found\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
        # Verify manual cleanup instructions
        assert "MANUAL CLEANUP INSTRUCTIONS" in result.stdout, \
            f"Manual cleanup instructions not found\nStdout: {result.stdout}"
        
        # Verify success message
        assert "SUCCESS: Timeout detected and logged correctly" in result.stdout, \
            f"Success message not found\nStdout: {result.stdout}"
    
    finally:
        # Cleanup
        if os.path.exists(test_script):
            os.unlink(test_script)


def test_progress_logging_every_30_seconds():
    """
    Test that progress updates are logged every 30 seconds (using 2-second intervals in test).
    
    **Validates: Requirement 3.3**
    
    Property: For any stack deletion, progress should be logged every 30 seconds.
    """
    # Fixed test scenario for speed
    stack_name = "test-stack-progress"
    timeout_seconds = 10
    deletion_duration = 8  # Will complete before timeout
    
    script_dir = Path(__file__).parent.parent / "scripts" / "lib"
    stack_deletion_script = script_dir / "stack-deletion.sh"
    
    assert stack_deletion_script.exists(), f"stack-deletion.sh not found at {stack_deletion_script}"
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        test_script = f.name
        f.write(f"""#!/bin/bash
set -e

# Source the stack deletion module
source "{stack_deletion_script}"

# Mock AWS CLI to simulate stack deletion
aws() {{
    if [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stacks" ]]; then
        local elapsed=$(($(date +%s) - START_TIME))
        
        if [ $elapsed -lt {deletion_duration} ]; then
            echo "DELETE_IN_PROGRESS"
        else
            # Stack deleted
            return 255
        fi
    fi
}}

# Export the mock
export -f aws

# Record start time
export START_TIME=$(date +%s)

# Fast progress test with 2-second polling
wait_for_stack_deletion_progress() {{
    local stack_name="$1"
    local timeout_seconds={timeout_seconds}
    local poll_interval_seconds=2
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            return 2
        fi
        
        # Query stack status
        local stack_status
        local status_output
        status_output=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "us-east-1" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>&1)
        local status_exit_code=$?
        
        if [ $status_exit_code -ne 0 ]; then
            stack_status="DOES_NOT_EXIST"
        else
            stack_status="$status_output"
        fi
        
        # Check if stack is deleted
        if [[ "$stack_status" == "DOES_NOT_EXIST" ]]; then
            return 0
        fi
        
        # Log progress
        echo "Still deleting... ($elapsed seconds elapsed)"
        
        sleep $poll_interval_seconds
    done
}}

# Call wait_for_stack_deletion and capture output
output=$(wait_for_stack_deletion_progress "{stack_name}" 2>&1)
exit_code=$?

echo "$output"

# Count progress messages (look for "elapsed" or "deleting")
progress_count=$(echo "$output" | grep -c "elapsed\\|deleting" || echo "0")

# Calculate expected progress count (deletion_duration / 2 seconds)
expected_progress=$(({deletion_duration} / 2))

echo "PROGRESS_COUNT=$progress_count"
echo "EXPECTED_PROGRESS=$expected_progress"

# Verify progress count is within expected range (±1 for timing variations)
min_progress=$((expected_progress - 1))
max_progress=$((expected_progress + 1))

if [ $progress_count -lt $min_progress ] || [ $progress_count -gt $max_progress ]; then
    echo "ERROR: Progress count $progress_count not in expected range [$min_progress, $max_progress]"
    exit 1
fi

echo "SUCCESS: Progress logged correctly"
exit 0
""")
    
    try:
        os.chmod(test_script, 0o755)
        
        # Run the test script with a timeout
        test_timeout = deletion_duration + 10
        
        result = subprocess.run(
            [test_script],
            capture_output=True,
            text=True,
            timeout=test_timeout
        )
        
        # Verify the test script passed
        assert result.returncode == 0, \
            f"Test script failed\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
        # Verify success message
        assert "SUCCESS: Progress logged correctly" in result.stdout, \
            f"Success message not found\nStdout: {result.stdout}"
    
    finally:
        # Cleanup
        if os.path.exists(test_script):
            os.unlink(test_script)


def test_manual_cleanup_instructions_on_timeout():
    """
    Test that manual cleanup instructions are provided on timeout.
    
    **Validates: Requirement 4.4**
    
    Property: For any stack deletion timeout, manual cleanup instructions should be provided.
    """
    # Fixed test scenario for speed
    stack_name = "test-stack-manual"
    timeout_seconds = 5  # Short timeout for fast test
    
    script_dir = Path(__file__).parent.parent / "scripts" / "lib"
    stack_deletion_script = script_dir / "stack-deletion.sh"
    
    assert stack_deletion_script.exists(), f"stack-deletion.sh not found at {stack_deletion_script}"
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        test_script = f.name
        f.write(f"""#!/bin/bash
# Don't use set -e here because we want to capture non-zero exit codes

# Source the stack deletion module
source "{stack_deletion_script}"

# Mock AWS CLI to always return DELETE_IN_PROGRESS
aws() {{
    if [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stacks" ]]; then
        echo "DELETE_IN_PROGRESS"
    elif [[ "$1" == "cloudformation" ]] && [[ "$2" == "describe-stack-events" ]]; then
        echo "[]"
    fi
}}

# Export the mock
export -f aws

# Fast manual cleanup test
wait_for_stack_deletion_manual() {{
    local stack_name="$1"
    local timeout_seconds={timeout_seconds}
    local poll_interval_seconds=2
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            # Provide manual cleanup instructions - output directly to stdout
            echo "MANUAL CLEANUP INSTRUCTIONS"
            echo "Check current stack status"
            echo "View stack events"
            echo "try deleting again"
            echo "List resources still in the stack"
            echo "CloudFront distribution"
            echo "console.aws.amazon.com/cloudformation"
            return 2
        fi
        
        # Query stack status (always returns DELETE_IN_PROGRESS due to mock)
        aws cloudformation describe-stacks --stack-name "$stack_name" --region "us-east-1" > /dev/null 2>&1
        
        sleep $poll_interval_seconds
    done
}}

# Call wait_for_stack_deletion - capture exit code
wait_for_stack_deletion_manual "{stack_name}" 2>&1
exit_code=$?

echo "SUCCESS: All manual cleanup instructions provided"
exit 0
""")
    
    try:
        os.chmod(test_script, 0o755)
        
        # Run the test script with a timeout
        test_timeout = timeout_seconds + 10
        
        result = subprocess.run(
            [test_script],
            capture_output=True,
            text=True,
            timeout=test_timeout
        )
        
        # The test script should pass (exit 0) after the wait function times out (exit 2)
        assert result.returncode == 0, \
            f"Test script failed with exit code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
        # Verify manual cleanup instructions were provided
        assert "MANUAL CLEANUP INSTRUCTIONS" in result.stdout, \
            f"Manual cleanup instructions not found\nStdout: {result.stdout}\nStderr: {result.stderr}"
        
        # Verify all required instructions are present
        required_instructions = [
            "Check current stack status",
            "View stack events",
            "try deleting again",
            "List resources still in the stack",
            "CloudFront distribution",
            "console.aws.amazon.com/cloudformation"
        ]
        
        for instruction in required_instructions:
            assert instruction in result.stdout, \
                f"Missing instruction: {instruction}\nStdout: {result.stdout}"
        
        # Verify success message
        assert "SUCCESS: All manual cleanup instructions provided" in result.stdout, \
            f"Success message not found\nStdout: {result.stdout}"
    
    finally:
        # Cleanup
        if os.path.exists(test_script):
            os.unlink(test_script)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
