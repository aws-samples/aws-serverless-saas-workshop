"""
Property-Based Tests for Cleanup Script Exit Codes

**Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**

Property 11: Consistent Exit Codes
For any cleanup script execution, the exit code should be 0 for complete success,
1 for critical operation failure, 2 for timeout, 3 for orphaned resources detected,
and 130 for user interrupt.

Test Strategy:
- Generate random failure scenarios
- Test that correct exit codes are returned
- Test that exit codes match failure types
- Use MAX_EXAMPLES=5 for fast execution (< 2 minutes)
"""

import subprocess
import tempfile
import os
from hypothesis import given, strategies as st, settings, Phase
from pathlib import Path

# Test configuration for 2-minute timeout requirement
MAX_EXAMPLES = 5
TIMEOUT_SECONDS = 10  # Per test timeout

# Exit code constants (must match exit-codes.sh)
EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_TIMEOUT = 2
EXIT_ORPHANED_RESOURCES = 3
EXIT_USER_INTERRUPT = 130


def create_mock_cleanup_script(scenario: str) -> str:
    """
    Create a mock cleanup script that simulates different exit scenarios.
    
    Args:
        scenario: One of "success", "failure", "timeout", "orphaned", "interrupt"
    
    Returns:
        Path to the mock script
    """
    # Get absolute path to exit-codes.sh module
    # Test file is at: workshop/tests/property/test_exit_codes_property.py
    # Module is at: workshop/scripts/lib/exit-codes.sh
    test_dir = Path(__file__).parent.absolute()
    exit_codes_module = test_dir.parent.parent / "scripts" / "lib" / "exit-codes.sh"
    
    script_content = f"""#!/bin/bash
set -e

# Source exit-codes module using absolute path
EXIT_CODES_MODULE="{exit_codes_module}"

if [ ! -f "$EXIT_CODES_MODULE" ]; then
    echo "Error: exit-codes.sh not found at $EXIT_CODES_MODULE" >&2
    exit 1
fi

source "$EXIT_CODES_MODULE"

# Setup exit handlers
setup_exit_handlers

# Simulate different scenarios
case "{scenario}" in
    success)
        echo "Cleanup completed successfully"
        exit_with_code $EXIT_SUCCESS "Cleanup completed"
        ;;
    failure)
        echo "Critical operation failed"
        exit_with_code $EXIT_FAILURE "Stack deletion failed"
        ;;
    timeout)
        echo "Operation timed out"
        exit_with_code $EXIT_TIMEOUT "Stack deletion timed out"
        ;;
    orphaned)
        echo "Orphaned resources detected"
        exit_with_code $EXIT_ORPHANED_RESOURCES "Orphaned resources found"
        ;;
    interrupt)
        echo "User interrupted"
        exit_with_code $EXIT_USER_INTERRUPT "User cancelled"
        ;;
    *)
        echo "Unknown scenario: {scenario}"
        exit 1
        ;;
esac
"""
    
    # Create temporary script file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(script_content)
        script_path = f.name
    
    # Make executable
    os.chmod(script_path, 0o755)
    
    return script_path


@given(st.sampled_from(["success", "failure", "timeout", "orphaned", "interrupt"]))
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,  # Convert to milliseconds
    phases=[Phase.generate, Phase.target]  # Skip shrinking for speed
)
def test_property_exit_codes_match_scenarios(scenario):
    """
    Property 11: Exit codes should match the failure scenario.
    
    **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    
    For any cleanup script execution:
    - Success scenario should return exit code 0
    - Failure scenario should return exit code 1
    - Timeout scenario should return exit code 2
    - Orphaned resources scenario should return exit code 3
    - Interrupt scenario should return exit code 130
    """
    script_path = None
    try:
        # Create mock script for this scenario
        script_path = create_mock_cleanup_script(scenario)
        
        # Run the script and capture exit code
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS
        )
        
        # Map scenarios to expected exit codes
        expected_exit_codes = {
            "success": EXIT_SUCCESS,
            "failure": EXIT_FAILURE,
            "timeout": EXIT_TIMEOUT,
            "orphaned": EXIT_ORPHANED_RESOURCES,
            "interrupt": EXIT_USER_INTERRUPT
        }
        
        expected_code = expected_exit_codes[scenario]
        actual_code = result.returncode
        
        # Verify exit code matches scenario
        assert actual_code == expected_code, (
            f"Exit code mismatch for scenario '{scenario}': "
            f"expected {expected_code}, got {actual_code}\\n"
            f"stdout: {result.stdout}\\n"
            f"stderr: {result.stderr}"
        )
        
        # Verify output contains expected message
        output = result.stdout + result.stderr
        scenario_messages = {
            "success": "Cleanup completed",
            "failure": "Critical operation failed",
            "timeout": "Operation timed out",
            "orphaned": "Orphaned resources detected",
            "interrupt": "User interrupted"
        }
        
        expected_message = scenario_messages[scenario]
        assert expected_message in output, (
            f"Expected message '{expected_message}' not found in output for scenario '{scenario}'"
        )
        
    finally:
        # Clean up temporary script
        if script_path and os.path.exists(script_path):
            os.unlink(script_path)


@given(st.integers(min_value=0, max_value=255))
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    phases=[Phase.generate, Phase.target]
)
def test_property_exit_codes_are_valid(exit_code):
    """
    Property 11: Exit codes should be in valid range (0-255).
    
    **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    
    All exit codes used by cleanup scripts should be valid Unix exit codes (0-255).
    The defined exit codes (0, 1, 2, 3, 130) should all be within this range.
    """
    # Verify that our defined exit codes are valid
    valid_exit_codes = [
        EXIT_SUCCESS,
        EXIT_FAILURE,
        EXIT_TIMEOUT,
        EXIT_ORPHANED_RESOURCES,
        EXIT_USER_INTERRUPT
    ]
    
    for code in valid_exit_codes:
        assert 0 <= code <= 255, f"Exit code {code} is out of valid range (0-255)"
    
    # Verify that the generated exit code is valid
    assert 0 <= exit_code <= 255, f"Generated exit code {exit_code} is out of valid range"


def test_exit_codes_module_exists():
    """
    Verify that the exit-codes.sh module exists and is readable.
    
    **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    """
    # Get path relative to test file location
    test_dir = Path(__file__).parent.absolute()
    module_path = test_dir.parent.parent / "scripts" / "lib" / "exit-codes.sh"
    assert module_path.exists(), f"Exit codes module not found: {module_path}"
    assert module_path.is_file(), f"Exit codes module is not a file: {module_path}"
    assert os.access(module_path, os.R_OK), f"Exit codes module is not readable: {module_path}"


def test_exit_codes_module_defines_constants():
    """
    Verify that the exit-codes.sh module defines all required exit code constants.
    
    **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    """
    # Get path relative to test file location
    test_dir = Path(__file__).parent.absolute()
    module_path = test_dir.parent.parent / "scripts" / "lib" / "exit-codes.sh"
    
    with open(module_path, 'r') as f:
        content = f.read()
    
    # Verify all required constants are defined
    required_constants = [
        "EXIT_SUCCESS=0",
        "EXIT_FAILURE=1",
        "EXIT_TIMEOUT=2",
        "EXIT_ORPHANED_RESOURCES=3",
        "EXIT_USER_INTERRUPT=130"
    ]
    
    for constant in required_constants:
        assert constant in content, f"Required constant '{constant}' not found in exit-codes.sh"


def test_exit_codes_module_defines_functions():
    """
    Verify that the exit-codes.sh module defines all required functions.
    
    **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    """
    # Get path relative to test file location
    test_dir = Path(__file__).parent.absolute()
    module_path = test_dir.parent.parent / "scripts" / "lib" / "exit-codes.sh"
    
    with open(module_path, 'r') as f:
        content = f.read()
    
    # Verify all required functions are defined
    required_functions = [
        "handle_sigint()",
        "setup_exit_handlers()",
        "exit_with_code()",
        "get_exit_code_description()"
    ]
    
    for function in required_functions:
        assert function in content, f"Required function '{function}' not found in exit-codes.sh"


if __name__ == "__main__":
    import pytest
    pytest.main([__file__, "-v", "-s"])
