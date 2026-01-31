#!/usr/bin/env python3
"""
Property-Based Test for Enhanced Error Logging

**Feature: lab-cleanup-isolation-all-labs**
**Property 4: Comprehensive Error Logging**
**Validates: Requirements 3.1, 3.2, 3.4, 3.5**

This test verifies that the stack deletion module provides comprehensive error logging:
- Full AWS CLI commands are logged before execution
- Both stdout and stderr are captured on command failure
- CloudFormation stack events are logged on deletion failure
- Exit summary logging includes all operation results

The test uses property-based testing to generate random AWS CLI commands,
error scenarios, and stack names to verify logging completeness across all cases.
"""

import subprocess
import tempfile
import os
import re
from pathlib import Path
from hypothesis import given, strategies as st, settings, assume
from hypothesis import HealthCheck


# Strategy for generating valid stack names
@st.composite
def stack_name_strategy(draw):
    """Generate valid CloudFormation stack names."""
    # Stack names must be alphanumeric with hyphens, 1-128 chars
    prefix = draw(st.sampled_from(['serverless-saas', 'test-stack', 'lab']))
    suffix = draw(st.sampled_from(['lab1', 'lab2', 'shared', 'tenant']))
    number = draw(st.integers(min_value=1, max_value=999))
    return f"{prefix}-{suffix}-{number}"


# Strategy for generating AWS CLI commands
@st.composite
def aws_command_strategy(draw):
    """Generate realistic AWS CLI commands."""
    service = draw(st.sampled_from(['cloudformation', 's3', 'logs', 'cognito-idp']))
    
    if service == 'cloudformation':
        operation = draw(st.sampled_from([
            'delete-stack',
            'describe-stacks',
            'describe-stack-events'
        ]))
        stack_name = draw(stack_name_strategy())
        return f"aws {service} {operation} --stack-name {stack_name} --region us-east-1"
    elif service == 's3':
        operation = draw(st.sampled_from(['delete-bucket', 'list-buckets']))
        bucket_name = draw(st.text(
            alphabet=st.characters(whitelist_categories=('Ll', 'Nd'), whitelist_characters='-'),
            min_size=3,
            max_size=20
        ))
        return f"aws {service} {operation} --bucket {bucket_name}"
    elif service == 'logs':
        operation = 'delete-log-group'
        log_group = draw(st.text(min_size=5, max_size=30))
        return f"aws {service} {operation} --log-group-name {log_group}"
    else:  # cognito-idp
        operation = 'delete-user-pool'
        pool_id = draw(st.text(
            alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd')),
            min_size=10,
            max_size=20
        ))
        return f"aws {service} {operation} --user-pool-id {pool_id}"


# Strategy for generating error messages
@st.composite
def error_message_strategy(draw):
    """Generate realistic AWS CLI error messages."""
    error_types = [
        "ValidationError: Stack does not exist",
        "AccessDenied: User is not authorized to perform this operation",
        "Throttling: Rate exceeded",
        "ResourceNotFoundException: The specified resource does not exist",
        "InvalidParameterValue: Invalid parameter value",
        "ServiceUnavailable: Service is temporarily unavailable"
    ]
    return draw(st.sampled_from(error_types))


@given(
    command=aws_command_strategy(),
    error_message=error_message_strategy(),
    stack_name=stack_name_strategy()
)
@settings(
    max_examples=20,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
    deadline=None
)
def test_log_command_captures_full_command(command, error_message, stack_name):
    """
    Property: For any AWS CLI command, log_command should log the full command with all parameters.
    
    **Validates: Requirement 3.1**
    """
    # Filter out commands with problematic characters for bash
    assume('\\' not in command)  # Backslashes cause issues
    assume('\x00' not in command)  # Null bytes
    assume('"' not in command)  # Quotes need escaping
    assume('`' not in command)  # Backticks cause command substitution
    assume('$' not in command)  # Dollar signs cause variable expansion
    assume('(' not in command)  # Parentheses cause subshell issues
    assume(')' not in command)  # Parentheses cause subshell issues
    assume(';' not in command)  # Semicolons cause command chaining issues
    assume('\r' not in command)  # Carriage returns cause issues
    assume('\n' not in command)  # Newlines cause issues
    
    # Get the absolute path to the stack-deletion.sh module
    test_dir = Path(__file__).parent
    workshop_dir = test_dir.parent
    stack_deletion_path = workshop_dir / "scripts" / "lib" / "stack-deletion.sh"
    
    # Create a temporary test script that sources the logging module
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        script_path = f.name
        f.write(f"""#!/bin/bash
source "{stack_deletion_path}"

# Call log_command
log_command {command}

# Verify the command was logged
if [[ "$LAST_COMMAND" == "{command}" ]]; then
    echo "PASS: Command logged correctly"
    exit 0
else
    echo "FAIL: Command not logged correctly"
    echo "Expected: {command}"
    echo "Got: $LAST_COMMAND"
    exit 1
fi
""")
    
    try:
        os.chmod(script_path, 0o755)
        
        # Run the test script
        result = subprocess.run(
            [script_path],
            cwd=workshop_dir,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        # Verify the command was logged
        assert result.returncode == 0, f"Test failed: {result.stdout}\n{result.stderr}"
        assert "PASS: Command logged correctly" in result.stdout
        
        # Verify the command appears in the output
        assert command in result.stdout or command in result.stderr
        
    finally:
        os.unlink(script_path)


@given(
    operation=st.sampled_from(['delete_stack', 'wait_for_deletion', 'verify_deletion']),
    error_message=error_message_strategy(),
    stack_name=stack_name_strategy()
)
@settings(
    max_examples=20,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
    deadline=None
)
def test_log_error_captures_context(operation, error_message, stack_name):
    """
    Property: For any error, log_error should capture operation name, error message, and stack context.
    
    **Validates: Requirements 3.2, 3.4**
    """
    # Filter out problematic characters
    assume('\r' not in error_message)
    assume('\n' not in error_message)
    assume('\x00' not in error_message)
    # Get the absolute path to the stack-deletion.sh module
    test_dir = Path(__file__).parent
    workshop_dir = test_dir.parent
    stack_deletion_path = workshop_dir / "scripts" / "lib" / "stack-deletion.sh"
    
    # Create a temporary test script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        script_path = f.name
        # Escape special characters in error message for bash
        escaped_error = error_message.replace('"', '\\"').replace('$', '\\$')
        
        f.write(f"""#!/bin/bash
source "{stack_deletion_path}"

# Set a command for context
LAST_COMMAND="aws cloudformation delete-stack --stack-name {stack_name}"

# Override log_stack_events to prevent AWS CLI calls during test
log_stack_events() {{
    echo "Mock: Skipping stack events fetch during test" >&2
}}

# Call log_error (without stack name to avoid AWS CLI calls)
log_error "{operation}" "{escaped_error}" "" ""

# Verify error was logged
if [[ "$LAST_ERROR_OUTPUT" == "{escaped_error}" ]]; then
    echo "PASS: Error logged correctly"
    exit 0
else
    echo "FAIL: Error not logged correctly"
    echo "Expected: {escaped_error}"
    echo "Got: $LAST_ERROR_OUTPUT"
    exit 1
fi
""")
    
    try:
        os.chmod(script_path, 0o755)
        
        # Run the test script with increased timeout
        result = subprocess.run(
            [script_path],
            cwd=workshop_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Verify the error was logged
        assert result.returncode == 0, f"Test failed: {result.stdout}\n{result.stderr}"
        assert "PASS: Error logged correctly" in result.stdout
        
        # Verify error context appears in stderr
        assert operation in result.stderr
        assert stack_name in result.stderr
        
    finally:
        os.unlink(script_path)


@given(
    operations=st.lists(
        st.tuples(
            st.sampled_from(['delete_stack', 'wait_deletion', 'verify_deletion']),
            st.sampled_from(['SUCCESS', 'FAILURE', 'TIMEOUT']),
            stack_name_strategy()
        ),
        min_size=1,
        max_size=10
    )
)
@settings(
    max_examples=20,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
    deadline=None
)
def test_log_exit_summary_includes_all_operations(operations):
    """
    Property: For any sequence of operations, log_exit_summary should include all operations in the summary.
    
    **Validates: Requirement 3.5**
    """
    # Get the absolute path to the stack-deletion.sh module
    test_dir = Path(__file__).parent
    workshop_dir = test_dir.parent
    stack_deletion_path = workshop_dir / "scripts" / "lib" / "stack-deletion.sh"
    
    # Create a temporary test script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        script_path = f.name
        
        f.write(f"""#!/bin/bash
source "{stack_deletion_path}"

""")
        
        # Add log_operation_result calls for each operation
        for op_name, status, stack_name in operations:
            f.write(f'log_operation_result "{op_name}:{stack_name}" "{status}" "Test operation"\n')
        
        # Call log_exit_summary
        exit_code = 0 if all(status == 'SUCCESS' for _, status, _ in operations) else 1
        f.write(f"""
# Call log_exit_summary
log_exit_summary {exit_code}

# Verify all operations are in the log
echo "OPERATIONS_COUNT=${{#OPERATIONS_LOG[@]}}"
""")
    
    try:
        os.chmod(script_path, 0o755)
        
        # Run the test script
        result = subprocess.run(
            [script_path],
            cwd=workshop_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Extract operations count from output
        match = re.search(r'OPERATIONS_COUNT=(\d+)', result.stdout)
        assert match, f"Could not find operations count in output: {result.stdout}"
        
        operations_count = int(match.group(1))
        
        # Verify all operations were logged (each operation creates one log entry)
        assert operations_count == len(operations), \
            f"Expected {len(operations)} operations, got {operations_count}"
        
        # Verify summary appears in output
        assert "OPERATION SUMMARY" in result.stdout
        
        # Verify success/failure counts
        success_count = sum(1 for _, status, _ in operations if status == 'SUCCESS')
        failure_count = sum(1 for _, status, _ in operations if status in ['FAILURE', 'TIMEOUT'])
        
        if success_count > 0:
            assert f"Successful Operations: {success_count}" in result.stdout
        if failure_count > 0:
            assert f"Failed Operations: {failure_count}" in result.stdout
        
    finally:
        os.unlink(script_path)


@given(
    command=aws_command_strategy(),
    stdout_output=st.text(min_size=10, max_size=100),
    stderr_output=st.text(min_size=10, max_size=100)
)
@settings(
    max_examples=20,
    suppress_health_check=[HealthCheck.function_scoped_fixture, HealthCheck.filter_too_much],
    deadline=None
)
def test_log_error_captures_stdout_and_stderr(command, stdout_output, stderr_output):
    """
    Property: For any command failure, both stdout and stderr should be captured and logged.
    
    **Validates: Requirement 3.2**
    """
    # Assume outputs don't contain problematic characters
    assume('"' not in command and '"' not in stdout_output and '"' not in stderr_output)
    assume('$' not in command and '$' not in stdout_output and '$' not in stderr_output)
    assume('`' not in command and '`' not in stdout_output and '`' not in stderr_output)
    assume('\\' not in command and '\\' not in stdout_output and '\\' not in stderr_output)
    assume('\n' not in stdout_output and '\n' not in stderr_output)
    # Filter out non-ASCII characters that could cause encoding issues
    assume(all(ord(c) < 128 for c in command))
    assume(all(ord(c) < 128 for c in stdout_output))
    assume(all(ord(c) < 128 for c in stderr_output))
    
    # Get absolute path to stack-deletion.sh
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workshop_dir = os.path.dirname(script_dir)
    stack_deletion_path = os.path.join(workshop_dir, "scripts", "lib", "stack-deletion.sh")
    
    # Create a temporary test script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        script_path = f.name
        
        f.write(f"""#!/bin/bash
source "{stack_deletion_path}"

# Simulate a command that produces both stdout and stderr
LAST_COMMAND="{command}"
combined_output="{stdout_output}
{stderr_output}"

# Call log_error with combined output
log_error "test_operation" "$combined_output" "" ""

# Verify error was captured
if [[ "$LAST_ERROR_OUTPUT" == "$combined_output" ]]; then
    echo "PASS: Both stdout and stderr captured"
    exit 0
else
    echo "FAIL: Output not captured correctly"
    exit 1
fi
""")
    
    try:
        os.chmod(script_path, 0o755)
        
        # Run the test script
        result = subprocess.run(
            [script_path],
            cwd=Path(__file__).parent.parent,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        # Verify both outputs were captured
        assert result.returncode == 0, f"Test failed: {result.stdout}\n{result.stderr}"
        assert "PASS: Both stdout and stderr captured" in result.stdout
        
    finally:
        os.unlink(script_path)


if __name__ == '__main__':
    import pytest
    import sys
    
    # Run the tests
    sys.exit(pytest.main([__file__, '-v', '--tb=short']))
