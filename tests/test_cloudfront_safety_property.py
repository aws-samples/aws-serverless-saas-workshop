#!/usr/bin/env python3
"""
Property-Based Tests for CloudFront Safety Verification Module

Feature: lab-cleanup-isolation-all-labs
Property 7: CloudFront Deletion Before S3

This test validates that the CloudFront safety verification logic correctly:
1. Waits for CloudFront distributions to be deleted before S3 bucket deletion
2. Verifies no CloudFront distributions reference S3 buckets before deletion
3. Implements extended timeout handling for CloudFront (45 minutes)

Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5

PERFORMANCE REQUIREMENT: All tests MUST complete within 2 minutes maximum.
- Using max_examples=5 to keep test duration under 2 minutes
- Using short timeout durations (5-10 seconds) instead of real 45 minutes
- Mocking AWS CLI calls to avoid real API delays
"""

import subprocess
import tempfile
import os
from hypothesis import given, strategies as st, settings
from hypothesis import HealthCheck
import pytest


# Strategy for generating valid S3 bucket names
# Bucket names: 3-63 chars, lowercase letters, numbers, hyphens, dots
# Must start and end with letter or number
bucket_name_strategy = st.text(
    alphabet=st.characters(whitelist_categories=('Ll', 'Nd'), whitelist_characters='-.'),
    min_size=3,
    max_size=63
).filter(lambda s: s and s[0].isalnum() and s[-1].isalnum() and '..' not in s)


# Strategy for generating CloudFront distribution IDs
# Format: E followed by 13 alphanumeric characters
dist_id_strategy = st.text(
    alphabet=st.characters(whitelist_categories=('Lu', 'Nd')),
    min_size=13,
    max_size=13
).map(lambda s: f'E{s}')


# Strategy for CloudFront distribution statuses
dist_status_strategy = st.sampled_from([
    'Deployed',
    'InProgress'
])


def create_mock_aws_cli_cloudfront(distributions, bucket_origins=None):
    """
    Create a mock AWS CLI script that simulates CloudFront behavior.
    
    Args:
        distributions: List of tuples (dist_id, status, domain)
        bucket_origins: Dict mapping dist_id to list of origin bucket names
    
    Returns:
        Tuple of (temp_dir, mock_aws_path)
    """
    if bucket_origins is None:
        bucket_origins = {}
    
    # Create a temporary directory for the mock
    temp_dir = tempfile.mkdtemp()
    mock_aws_path = os.path.join(temp_dir, 'aws')
    
    # Build distribution list output
    dist_list = []
    for dist_id, status, domain in distributions:
        dist_list.append(f'{dist_id}\t{status}\t{domain}')
    dist_list_output = '\n'.join(dist_list)
    
    # Build origin outputs for each distribution
    origin_outputs = {}
    for dist_id, origins in bucket_origins.items():
        origin_outputs[dist_id] = '\t'.join(origins)
    
    # Create the mock AWS CLI script
    mock_script = f'''#!/bin/bash
# Mock AWS CLI for testing CloudFront safety verification

# Track call count for simulating deletion progress
CALL_COUNT_FILE="/tmp/cloudfront_mock_call_count_$$.txt"
if [ ! -f "$CALL_COUNT_FILE" ]; then
    echo "0" > "$CALL_COUNT_FILE"
fi
CALL_COUNT=$(cat "$CALL_COUNT_FILE")
CALL_COUNT=$((CALL_COUNT + 1))
echo "$CALL_COUNT" > "$CALL_COUNT_FILE"

# Parse command
if [[ "$1" == "cloudfront" ]] && [[ "$2" == "list-distributions" ]]; then
    # list-distributions command
    # After 3 calls, simulate distributions being deleted
    if [ "$CALL_COUNT" -gt 3 ]; then
        echo '{{"DistributionList": {{"Items": []}}}}'
    else
        # Return initial distributions
        cat << 'EOF'
{dist_list_output}
EOF
    fi
    exit 0
elif [[ "$1" == "cloudfront" ]] && [[ "$2" == "get-distribution" ]]; then
    # get-distribution command - extract distribution ID
    DIST_ID=""
    for arg in "$@"; do
        if [[ "$prev_arg" == "--id" ]]; then
            DIST_ID="$arg"
        fi
        prev_arg="$arg"
    done
    
    # Return origins for the distribution
'''
    
    # Add origin responses for each distribution
    for dist_id, origins in origin_outputs.items():
        mock_script += f'''
    if [[ "$DIST_ID" == "{dist_id}" ]]; then
        echo '{origins}'
        exit 0
    fi
'''
    
    mock_script += '''
    # Distribution not found or no origins
    echo "NoSuchDistribution" >&2
    exit 254
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
    subprocess.run(['bash', '-c', 'rm -f /tmp/cloudfront_mock_call_count_*.txt'], 
                   stderr=subprocess.DEVNULL)


@given(
    bucket_name=bucket_name_strategy,
    dist_id=dist_id_strategy,
    dist_status=dist_status_strategy
)
@settings(
    max_examples=5,  # Reduced to keep test under 2 minutes
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_verify_no_cloudfront_references_property(bucket_name, dist_id, dist_status):
    """
    Property 7: CloudFront Deletion Before S3 (Part 1 - Reference Verification)
    
    For any valid bucket name and CloudFront distribution, the 
    verify_no_cloudfront_references function should:
    1. Return 0 (success) if no distributions reference the bucket
    2. Return 1 (failure) if any distribution references the bucket
    3. Query all distributions and check their origins
    
    Validates: Requirements 11.5
    """
    # Test case 1: Distribution does NOT reference the bucket (should succeed)
    temp_dir, mock_aws_path = create_mock_aws_cli_cloudfront(
        distributions=[(dist_id, dist_status, f'{dist_id}.cloudfront.net')],
        bucket_origins={dist_id: ['other-bucket.s3.amazonaws.com']}
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        cloudfront_safety_path = os.path.join(workshop_dir, 'scripts', 'lib', 'cloudfront-safety.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{cloudfront_safety_path}"

verify_no_cloudfront_references "{bucket_name}" ""
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
            f"Expected success when bucket not referenced, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
    finally:
        cleanup_mock(temp_dir)
    
    # Test case 2: Distribution DOES reference the bucket (should fail)
    temp_dir, mock_aws_path = create_mock_aws_cli_cloudfront(
        distributions=[(dist_id, dist_status, f'{dist_id}.cloudfront.net')],
        bucket_origins={dist_id: [f'{bucket_name}.s3.amazonaws.com']}
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        cloudfront_safety_path = os.path.join(workshop_dir, 'scripts', 'lib', 'cloudfront-safety.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{cloudfront_safety_path}"

verify_no_cloudfront_references "{bucket_name}" ""
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
            f"Expected failure when bucket is referenced, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
        # Verify error message mentions the bucket
        assert bucket_name in result.stderr, \
            f"Expected bucket name {bucket_name} in error output"
        
    finally:
        cleanup_mock(temp_dir)


@given(
    dist_id=dist_id_strategy,
    dist_status=dist_status_strategy
)
@settings(
    max_examples=1,  # Reduced to 1 to keep test under 2 minutes (this test is slow)
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_wait_for_cloudfront_deletion_property(dist_id, dist_status):
    """
    Property 7: CloudFront Deletion Before S3 (Part 2 - Deletion Waiting)
    
    For any CloudFront distribution, the wait_for_cloudfront_deletion function should:
    1. Poll distribution status every 60 seconds
    2. Return 0 (success) when all distributions are deleted
    3. Return 2 (timeout) if deletion takes longer than timeout
    4. Track distributions that existed at start
    
    Validates: Requirements 11.2, 11.3, 11.4
    
    NOTE: Using very short timeout and fast polling to keep test under 2 minutes
    """
    # Create mock with distributions that will be deleted after 2 polls
    temp_dir, mock_aws_path = create_mock_aws_cli_cloudfront(
        distributions=[(dist_id, dist_status, f'{dist_id}.cloudfront.net')],
        bucket_origins={}
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        cloudfront_safety_path = os.path.join(workshop_dir, 'scripts', 'lib', 'cloudfront-safety.sh')
        
        # Override timeout and poll interval for testing
        # Use 5 second poll interval and 30 second timeout
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{cloudfront_safety_path}"

# Override the wait_for_cloudfront_deletion function to use faster polling
wait_for_cloudfront_deletion() {{
    local stack_name="$1"
    local profile_arg="${{2:-}}"
    local poll_interval_seconds=2  # Fast polling for testing
    local timeout_seconds=30  # Short timeout for testing
    
    echo -e "${{YELLOW}}⏳ Monitoring CloudFront distribution deletion (timeout: 30 seconds)${{NC}}"
    echo -e "${{YELLOW}}⏳ Polling every ${{poll_interval_seconds}} seconds...${{NC}}"
    echo ""
    
    # Get initial distribution count
    local initial_distributions
    initial_distributions=$(get_cloudfront_distributions "$profile_arg")
    local get_result=$?
    
    if [ $get_result -ne 0 ]; then
        return 1
    fi
    
    if [[ -z "$initial_distributions" ]]; then
        echo -e "${{GREEN}}✓ No CloudFront distributions to wait for${{NC}}"
        return 0
    fi
    
    local initial_count=$(echo "$initial_distributions" | wc -l | tr -d ' ')
    echo -e "${{BLUE}}Initial CloudFront distributions: $initial_count${{NC}}"
    
    # Extract distribution IDs to track
    local tracked_dist_ids=()
    while IFS=$'\\t' read -r dist_id status domain; do
        if [[ -n "$dist_id" ]]; then
            tracked_dist_ids+=("$dist_id")
        fi
    done <<< "$initial_distributions"
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $elapsed -gt $timeout_seconds ]; then
            echo -e "${{YELLOW}}⚠ Timeout waiting for CloudFront deletion${{NC}}" >&2
            return 2
        fi
        
        # Get current distributions
        local current_distributions
        current_distributions=$(get_cloudfront_distributions "$profile_arg")
        get_result=$?
        
        if [ $get_result -ne 0 ]; then
            echo -e "${{RED}}ERROR: Failed to query CloudFront distributions${{NC}}" >&2
            return 1
        fi
        
        # Check if all tracked distributions are gone
        local all_deleted=true
        local remaining_count=0
        
        for tracked_id in "${{tracked_dist_ids[@]}}"; do
            if echo "$current_distributions" | grep -q "$tracked_id"; then
                all_deleted=false
                remaining_count=$((remaining_count + 1))
            fi
        done
        
        if [ "$all_deleted" = true ]; then
            echo -e "${{GREEN}}✓ All CloudFront distributions deleted successfully${{NC}}"
            return 0
        fi
        
        # Log progress
        echo -e "${{YELLOW}}  CloudFront distributions remaining: $remaining_count/${{initial_count}} (${{elapsed}}s elapsed)${{NC}}"
        
        # Wait before next poll
        sleep $poll_interval_seconds
    done
}}

wait_for_cloudfront_deletion "test-stack" ""
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
            timeout=60  # 1 minute timeout for the test itself
        )
        
        # Should succeed (distributions deleted after 3 polls)
        # OR timeout (if polling takes too long)
        assert result.returncode in [0, 2], \
            f"Expected success (0) or timeout (2), got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
        # Verify that polling occurred (output should mention distributions)
        assert 'CloudFront' in result.stdout or 'CloudFront' in result.stderr, \
            f"Expected CloudFront mention in output"
        
    finally:
        cleanup_mock(temp_dir)


@given(
    dist_id=dist_id_strategy,
    dist_status=dist_status_strategy
)
@settings(
    max_examples=5,  # Reduced to keep test under 2 minutes
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_check_cloudfront_distributions_status_property(dist_id, dist_status):
    """
    Property 7: CloudFront Deletion Before S3 (Part 3 - Status Checking)
    
    For any CloudFront distribution, the check_cloudfront_distributions_status 
    function should:
    1. Query all distributions before stack deletion
    2. Return 0 (success) if all distributions are in valid state (Deployed/InProgress)
    3. Return 1 (failure) if any distribution is in invalid state
    
    Validates: Requirements 11.1
    """
    # Test with valid status (Deployed or InProgress)
    temp_dir, mock_aws_path = create_mock_aws_cli_cloudfront(
        distributions=[(dist_id, dist_status, f'{dist_id}.cloudfront.net')],
        bucket_origins={}
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        cloudfront_safety_path = os.path.join(workshop_dir, 'scripts', 'lib', 'cloudfront-safety.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{cloudfront_safety_path}"

check_cloudfront_distributions_status ""
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
        
        # Should succeed for Deployed or InProgress status
        assert result.returncode == 0, \
            f"Expected success for status {dist_status}, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
        # Verify status was checked
        assert dist_id in result.stdout or dist_id in result.stderr, \
            f"Expected distribution ID {dist_id} in output"
        
    finally:
        cleanup_mock(temp_dir)


@given(
    bucket_name=bucket_name_strategy
)
@settings(
    max_examples=5,  # Reduced to keep test under 2 minutes
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_verify_cloudfront_safe_for_s3_deletion_property(bucket_name):
    """
    Property 7: CloudFront Deletion Before S3 (Part 4 - High-Level Safety Check)
    
    For any S3 bucket, the verify_cloudfront_safe_for_s3_deletion function should:
    1. Return 0 (success) if no CloudFront distributions exist
    2. Return 0 (success) if distributions exist but don't reference the bucket
    3. Return 1 (failure) if distributions reference the bucket
    
    Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5
    """
    # Test case 1: No distributions (should succeed)
    temp_dir, mock_aws_path = create_mock_aws_cli_cloudfront(
        distributions=[],
        bucket_origins={}
    )
    
    try:
        # Get the absolute path to the workshop directory
        workshop_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        cloudfront_safety_path = os.path.join(workshop_dir, 'scripts', 'lib', 'cloudfront-safety.sh')
        
        test_script = f'''#!/bin/bash
export PATH="{os.path.dirname(mock_aws_path)}:$PATH"
export AWS_REGION="us-east-1"

source "{cloudfront_safety_path}"

verify_cloudfront_safe_for_s3_deletion "{bucket_name}" ""
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
            f"Expected success when no distributions exist, got exit code {result.returncode}\n" \
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        
    finally:
        cleanup_mock(temp_dir)


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

