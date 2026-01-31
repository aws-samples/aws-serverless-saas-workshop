#!/usr/bin/env python3
"""
Property-Based Tests for Manual Cleanup Instructions

**Property 12: Manual Cleanup Instructions**
**Validates: Requirements 14.1, 14.2, 14.3, 14.4, 14.5, 4.4**

For any cleanup failure or orphaned resource detection, the cleanup script should provide
specific AWS Console URLs and exact AWS CLI commands needed to manually clean up the
remaining resources, with explanations for any skipped operations.

Test Configuration:
- MAX_EXAMPLES: 5 (reduced for 2-minute timeout requirement)
- TIMEOUT_SECONDS: 10 (per test, total ~50 seconds for all tests)
"""

import subprocess
import tempfile
import os
from hypothesis import given, strategies as st, settings, HealthCheck
from pathlib import Path

# Test configuration for 2-minute timeout requirement
MAX_EXAMPLES = 5
TIMEOUT_SECONDS = 10

# Get absolute path to test directory
TEST_DIR = Path(__file__).parent.absolute()
WORKSHOP_ROOT = TEST_DIR.parent.parent
SCRIPTS_LIB_DIR = WORKSHOP_ROOT / "scripts" / "lib"

# Strategy for generating stack names
stack_names = st.text(
    alphabet=st.characters(whitelist_categories=("Lu", "Ll", "Nd"), min_codepoint=65, max_codepoint=122),
    min_size=10,
    max_size=30
).filter(lambda x: x and x[0].isalpha())

# Strategy for generating AWS regions
aws_regions = st.sampled_from([
    "us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"
])

# Strategy for generating S3 bucket names
bucket_names = st.text(
    alphabet=st.characters(whitelist_categories=("Ll", "Nd"), min_codepoint=97, max_codepoint=122),
    min_size=10,
    max_size=30
).map(lambda x: x + "-bucket").filter(lambda x: x and x[0].isalpha())

# Strategy for generating Cognito pool IDs
cognito_pool_ids = st.text(
    alphabet=st.characters(whitelist_categories=("Ll", "Nd"), min_codepoint=97, max_codepoint=122),
    min_size=20,
    max_size=30
).map(lambda x: f"us-east-1_{x}")


def create_mock_manual_cleanup_script(stack_name: str, region: str, profile_arg: str = "") -> str:
    """
    Creates a mock script that calls log_manual_cleanup_instructions.
    
    This script sources the stack-deletion.sh module and calls the
    log_manual_cleanup_instructions function to generate manual cleanup instructions.
    """
    script_content = f"""#!/bin/bash
set -e

# Source the stack-deletion module
source "{SCRIPTS_LIB_DIR}/stack-deletion.sh"

# Set AWS region
export AWS_REGION="{region}"

# Call log_manual_cleanup_instructions
log_manual_cleanup_instructions "{stack_name}" "{profile_arg}"
"""
    return script_content


@given(stack_names, aws_regions)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow]
)
def test_property_console_url_generation(stack_name: str, region: str):
    """
    Property 12.1: Console URLs are generated correctly for manual cleanup.
    
    For any stack name and region, the manual cleanup instructions should include
    a valid AWS Console URL that points to the CloudFormation console in the
    correct region.
    
    **Validates: Requirement 14.1**
    """
    # Create mock script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(create_mock_manual_cleanup_script(stack_name, region))
        script_path = f.name
    
    try:
        # Make script executable
        os.chmod(script_path, 0o755)
        
        # Execute script and capture output
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        output = result.stdout + result.stderr
        
        # Verify console URL is present
        assert "console.aws.amazon.com/cloudformation" in output, \
            f"Console URL not found in output for stack {stack_name}"
        
        # Verify region is in the URL
        assert f"region={region}" in output, \
            f"Region {region} not found in console URL"
        
        # Verify the URL is properly formatted
        assert "https://" in output, \
            "Console URL should use HTTPS"
        
    finally:
        # Cleanup
        os.unlink(script_path)


@given(stack_names, aws_regions)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow]
)
def test_property_stack_delete_commands(stack_name: str, region: str):
    """
    Property 12.2: AWS CLI commands for orphaned stacks are valid and complete.
    
    For any orphaned stack, the manual cleanup instructions should provide
    exact AWS CLI commands that include all required parameters (stack name,
    region) and are properly formatted.
    
    **Validates: Requirement 14.2**
    """
    # Create mock script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(create_mock_manual_cleanup_script(stack_name, region))
        script_path = f.name
    
    try:
        # Make script executable
        os.chmod(script_path, 0o755)
        
        # Execute script and capture output
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        output = result.stdout + result.stderr
        
        # Verify delete-stack command is present
        assert "aws cloudformation delete-stack" in output, \
            "delete-stack command not found in output"
        
        # Verify stack name is in the command
        assert f'--stack-name "{stack_name}"' in output or f"--stack-name {stack_name}" in output, \
            f"Stack name {stack_name} not found in delete-stack command"
        
        # Verify region is in the command
        assert f'--region "{region}"' in output or f"--region {region}" in output, \
            f"Region {region} not found in delete-stack command"
        
        # Verify describe-stacks command is present (for status checking)
        assert "aws cloudformation describe-stacks" in output, \
            "describe-stacks command not found in output"
        
    finally:
        # Cleanup
        os.unlink(script_path)


@given(stack_names, aws_regions)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow]
)
def test_property_cloudfront_instructions(stack_name: str, region: str):
    """
    Property 12.3: CloudFront-specific manual cleanup instructions are provided.
    
    For any stack that may contain CloudFront distributions, the manual cleanup
    instructions should include commands to list, disable, and delete CloudFront
    distributions, as these are common blockers for stack deletion.
    
    **Validates: Requirement 14.1, 14.2 (CloudFront-specific)**
    """
    # Create mock script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(create_mock_manual_cleanup_script(stack_name, region))
        script_path = f.name
    
    try:
        # Make script executable
        os.chmod(script_path, 0o755)
        
        # Execute script and capture output
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        output = result.stdout + result.stderr
        
        # Verify CloudFront commands are present
        assert "aws cloudfront list-distributions" in output, \
            "list-distributions command not found in output"
        
        assert "aws cloudfront get-distribution-config" in output, \
            "get-distribution-config command not found in output"
        
        assert "aws cloudfront update-distribution" in output, \
            "update-distribution command not found in output"
        
        # Verify instructions mention disabling before deletion
        assert "Disable" in output or "disable" in output, \
            "Instructions should mention disabling CloudFront distribution"
        
        # Verify instructions mention the Enabled flag
        assert "Enabled" in output or "enabled" in output, \
            "Instructions should mention the Enabled flag"
        
    finally:
        # Cleanup
        os.unlink(script_path)


@given(stack_names, aws_regions)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow]
)
def test_property_stack_events_commands(stack_name: str, region: str):
    """
    Property 12.4: Commands to view stack events are provided for troubleshooting.
    
    For any failed stack deletion, the manual cleanup instructions should include
    commands to view stack events, which help diagnose why the deletion failed.
    
    **Validates: Requirement 14.2**
    """
    # Create mock script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(create_mock_manual_cleanup_script(stack_name, region))
        script_path = f.name
    
    try:
        # Make script executable
        os.chmod(script_path, 0o755)
        
        # Execute script and capture output
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        output = result.stdout + result.stderr
        
        # Verify describe-stack-events command is present
        assert "aws cloudformation describe-stack-events" in output, \
            "describe-stack-events command not found in output"
        
        # Verify list-stack-resources command is present
        assert "aws cloudformation list-stack-resources" in output, \
            "list-stack-resources command not found in output"
        
        # Verify stack name is in the events command
        assert f'--stack-name "{stack_name}"' in output or f"--stack-name {stack_name}" in output, \
            f"Stack name {stack_name} not found in describe-stack-events command"
        
    finally:
        # Cleanup
        os.unlink(script_path)


@given(stack_names, aws_regions)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.too_slow]
)
def test_property_instructions_are_formatted_and_readable(stack_name: str, region: str):
    """
    Property 12.5: Manual cleanup instructions are well-formatted and readable.
    
    For any cleanup failure, the manual cleanup instructions should be clearly
    formatted with section headers, numbered steps, and explanatory text to
    guide users through the manual cleanup process.
    
    **Validates: Requirement 14.5**
    """
    # Create mock script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(create_mock_manual_cleanup_script(stack_name, region))
        script_path = f.name
    
    try:
        # Make script executable
        os.chmod(script_path, 0o755)
        
        # Execute script and capture output
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        output = result.stdout + result.stderr
        
        # Verify section header is present
        assert "MANUAL CLEANUP INSTRUCTIONS" in output, \
            "Section header not found in output"
        
        # Verify numbered steps are present
        assert "1." in output and "2." in output and "3." in output, \
            "Numbered steps not found in output"
        
        # Verify explanatory text is present
        assert "timed out" in output or "timeout" in output, \
            "Explanatory text about timeout not found"
        
        assert "monitor" in output or "check" in output, \
            "Explanatory text about monitoring not found"
        
        # Verify visual separators are present (for readability)
        assert "═" in output or "=" in output or "-" in output, \
            "Visual separators not found in output"
        
    finally:
        # Cleanup
        os.unlink(script_path)


if __name__ == "__main__":
    import pytest
    import sys
    
    # Run tests with pytest
    sys.exit(pytest.main([__file__, "-v", "--tb=short"]))
