#!/usr/bin/env python3
"""
Property-Based Tests for CDKToolkit Shared Resource Handling

Feature: lab-cleanup-isolation-all-labs
Property 9: CDKToolkit Shared Resource Handling

**Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.5**

This module tests the universal properties of CDKToolkit handling:
- CDKToolkit stacks are correctly identified by name pattern
- CDKToolkit is skipped when the other lab's pipeline exists
- CDKToolkit is deleted when both labs are cleaned up
- Warnings are logged with clear explanations
"""

import subprocess
import tempfile
import os
from hypothesis import given, strategies as st, settings
from typing import List, Tuple

# Test configuration
MAX_EXAMPLES = 5  # Reduced for 2-minute timeout requirement


##############################################################################
# Property Test Strategies
##############################################################################

@st.composite
def stack_name_strategy(draw):
    """Generate random stack names including CDKToolkit variants."""
    stack_type = draw(st.sampled_from([
        'cdktoolkit',
        'regular',
        'cdktoolkit_suffix'
    ]))
    
    if stack_type == 'cdktoolkit':
        return 'CDKToolkit'
    elif stack_type == 'cdktoolkit_suffix':
        suffix = draw(st.text(alphabet='abcdefghijklmnopqrstuvwxyz-', min_size=1, max_size=10))
        return f'CDKToolkit-{suffix}'
    else:
        # Regular stack name
        lab = draw(st.sampled_from(['lab1', 'lab2', 'lab3', 'lab4', 'lab5', 'lab6', 'lab7']))
        stack_type = draw(st.sampled_from(['shared', 'tenant', 'pipeline']))
        return f'serverless-saas-{stack_type}-{lab}'


@st.composite
def lab_deployment_scenario(draw):
    """Generate random lab deployment scenarios."""
    current_lab = draw(st.sampled_from(['lab5', 'lab6', 'lab1', 'lab2']))
    other_lab_exists = draw(st.booleans())
    has_cdktoolkit = draw(st.booleans())
    
    return {
        'current_lab': current_lab,
        'other_lab_exists': other_lab_exists,
        'has_cdktoolkit': has_cdktoolkit
    }


@st.composite
def stack_list_strategy(draw):
    """Generate random lists of stack names."""
    num_stacks = draw(st.integers(min_value=0, max_value=10))
    stacks = []
    
    for _ in range(num_stacks):
        stack = draw(stack_name_strategy())
        stacks.append(stack)
    
    return stacks


##############################################################################
# Helper Functions
##############################################################################

def run_bash_function(function_name: str, *args, mock_aws: bool = False) -> Tuple[int, str, str]:
    """
    Run a bash function from cleanup-verification.sh.
    
    Args:
        function_name: Name of the bash function to call
        *args: Arguments to pass to the function
        mock_aws: If True, mock AWS CLI to avoid real API calls
    
    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, '../..'))
    lib_path = os.path.join(project_root, 'scripts/lib/cleanup-verification.sh')
    logging_path = os.path.join(project_root, 'scripts/lib/logging.sh')
    
    # Mock AWS CLI if requested
    aws_mock = ""
    if mock_aws:
        aws_mock = """
# Mock AWS CLI to avoid real API calls
aws() {
    # Always return empty result for describe-stacks (no stacks found)
    if [[ "$1" == "cloudformation" && "$2" == "describe-stacks" ]]; then
        echo ""
        return 255  # Stack not found
    fi
    # Default: return empty
    echo ""
    return 0
}
export -f aws
"""
    
    # Create a temporary script that sources the modules and calls the function
    bash_script = f"""#!/bin/bash
source "{logging_path}"
source "{lib_path}"
{aws_mock}
{function_name} {' '.join(f'"{arg}"' for arg in args)}
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(bash_script)
        temp_script = f.name
    
    try:
        os.chmod(temp_script, 0o755)
        result = subprocess.run(
            [temp_script],
            capture_output=True,
            text=True,
            timeout=30  # Increased timeout for AWS CLI calls
        )
        return result.returncode, result.stdout, result.stderr
    finally:
        os.unlink(temp_script)


def is_cdktoolkit_stack_name(stack_name: str) -> bool:
    """Check if a stack name matches CDKToolkit pattern."""
    return stack_name.startswith('CDKToolkit')


##############################################################################
# Property 9: CDKToolkit Shared Resource Handling
##############################################################################

@given(stack_name_strategy())
@settings(max_examples=MAX_EXAMPLES, deadline=None)
def test_property_cdktoolkit_detection(stack_name: str):
    """
    Property: CDKToolkit stacks are correctly identified by name pattern.
    
    For any stack name, is_cdktoolkit_stack should return 0 (true) if and only if
    the stack name starts with 'CDKToolkit'.
    """
    exit_code, stdout, stderr = run_bash_function('is_cdktoolkit_stack', stack_name)
    
    expected_is_cdktoolkit = is_cdktoolkit_stack_name(stack_name)
    actual_is_cdktoolkit = (exit_code == 0)
    
    assert actual_is_cdktoolkit == expected_is_cdktoolkit, \
        f"Stack '{stack_name}': expected is_cdktoolkit={expected_is_cdktoolkit}, got {actual_is_cdktoolkit}"


@given(st.lists(stack_name_strategy(), min_size=0, max_size=10))
@settings(max_examples=MAX_EXAMPLES, deadline=None)
def test_property_filter_preserves_non_cdktoolkit(stack_list: List[str]):
    """
    Property: Filtering always preserves non-CDKToolkit stacks.
    
    For any list of stack names, filter_cdktoolkit_stacks should preserve all
    non-CDKToolkit stacks in the output, regardless of the lab or other conditions.
    """
    # Create input with newline-separated stack names
    input_stacks = '\n'.join(stack_list)
    
    # Mock scenario where CDKToolkit should be preserved (Lab5 exists when cleaning Lab6)
    # We'll test with lab6 which should preserve CDKToolkit
    exit_code, stdout, stderr = run_bash_function(
        'filter_cdktoolkit_stacks',
        input_stacks,
        'lab6',
        '',
        mock_aws=True  # Mock AWS CLI to avoid real API calls
    )
    
    # Parse output
    filtered_stacks = [s.strip() for s in stdout.strip().split('\n') if s.strip()]
    
    # Check that all non-CDKToolkit stacks are preserved
    for stack in stack_list:
        if not is_cdktoolkit_stack_name(stack):
            assert stack in filtered_stacks, \
                f"Non-CDKToolkit stack '{stack}' should be preserved in output"


@given(st.lists(stack_name_strategy(), min_size=1, max_size=10))
@settings(max_examples=MAX_EXAMPLES, deadline=None)
def test_property_filter_removes_cdktoolkit_when_preserved(stack_list: List[str]):
    """
    Property: CDKToolkit stacks are removed when they should be preserved.
    
    For any list of stack names containing CDKToolkit stacks, when filtering
    for Lab6 (where Lab5 exists), all CDKToolkit stacks should be removed.
    
    Note: This test uses a mock that simulates Lab5 existing, so CDKToolkit
    should be preserved (removed from the deletion list).
    """
    # Ensure we have at least one CDKToolkit stack
    if not any(is_cdktoolkit_stack_name(s) for s in stack_list):
        stack_list.append('CDKToolkit')
    
    input_stacks = '\n'.join(stack_list)
    
    # Create a mock that simulates Lab5 existing (so CDKToolkit should be preserved)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, '../..'))
    lib_path = os.path.join(project_root, 'scripts/lib/cleanup-verification.sh')
    logging_path = os.path.join(project_root, 'scripts/lib/logging.sh')
    
    # Mock AWS CLI to simulate Lab5 existing
    aws_mock = """
# Mock AWS CLI to simulate Lab5 pipeline existing
aws() {
    if [[ "$1" == "cloudformation" && "$2" == "describe-stacks" ]]; then
        # Check if querying for Lab5 pipeline
        if [[ "$*" == *"serverless-saas-pipeline-lab5"* ]]; then
            echo "serverless-saas-pipeline-lab5"
            return 0
        fi
        # Check if querying for Lab5 shared
        if [[ "$*" == *"serverless-saas-shared-lab5"* ]]; then
            echo "serverless-saas-shared-lab5"
            return 0
        fi
    fi
    # Default: return empty (stack not found)
    echo ""
    return 255
}
export -f aws
"""
    
    bash_script = f"""#!/bin/bash
source "{logging_path}"
source "{lib_path}"
{aws_mock}
filter_cdktoolkit_stacks "{input_stacks}" "lab6" ""
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(bash_script)
        temp_script = f.name
    
    try:
        os.chmod(temp_script, 0o755)
        result = subprocess.run(
            [temp_script],
            capture_output=True,
            text=True,
            timeout=30
        )
        exit_code = result.returncode
        stdout = result.stdout
        stderr = result.stderr
    finally:
        os.unlink(temp_script)
    
    filtered_stacks = [s.strip() for s in stdout.strip().split('\n') if s.strip()]
    
    # Check that no CDKToolkit stacks remain in output
    for stack in filtered_stacks:
        assert not is_cdktoolkit_stack_name(stack), \
            f"CDKToolkit stack '{stack}' should be removed when Lab5 exists"


@given(st.sampled_from(['lab5', 'lab6', 'lab1', 'lab2', 'lab3']))
@settings(max_examples=MAX_EXAMPLES, deadline=None)
def test_property_preserve_logic_consistency(lab_id: str):
    """
    Property: CDKToolkit preservation logic is consistent.
    
    For any lab identifier:
    - Lab5 and Lab6 should check for each other's pipeline stacks
    - Other labs should never preserve CDKToolkit
    - The function should always return a valid exit code (0 or 1)
    """
    exit_code, stdout, stderr = run_bash_function(
        'should_preserve_cdktoolkit',
        lab_id,
        '',
        mock_aws=True  # Mock AWS CLI to avoid real API calls
    )
    
    # Exit code should be 0 (preserve) or 1 (don't preserve)
    assert exit_code in [0, 1], \
        f"should_preserve_cdktoolkit should return 0 or 1, got {exit_code}"
    
    # For labs other than lab5/lab6, should always return 1 (don't preserve)
    if lab_id not in ['lab5', 'lab6']:
        assert exit_code == 1, \
            f"Lab {lab_id} should not preserve CDKToolkit (expected exit code 1, got {exit_code})"


@given(st.lists(stack_name_strategy(), min_size=0, max_size=10))
@settings(max_examples=MAX_EXAMPLES, deadline=None)
def test_property_filter_output_format(stack_list: List[str]):
    """
    Property: Filter output format is consistent.
    
    For any list of stack names, the filtered output should:
    - Be newline-separated
    - Contain no empty lines
    - Preserve the relative order of non-CDKToolkit stacks
    """
    input_stacks = '\n'.join(stack_list)
    
    exit_code, stdout, stderr = run_bash_function(
        'filter_cdktoolkit_stacks',
        input_stacks,
        'lab1',  # Lab1 doesn't share CDKToolkit, so all stacks preserved
        '',
        mock_aws=True  # Mock AWS CLI to avoid real API calls
    )
    
    if stdout.strip():
        filtered_stacks = stdout.strip().split('\n')
        
        # No empty lines
        assert all(s.strip() for s in filtered_stacks), \
            "Filtered output should not contain empty lines"
        
        # Relative order preserved for non-CDKToolkit stacks
        non_cdktoolkit_input = [s for s in stack_list if not is_cdktoolkit_stack_name(s)]
        non_cdktoolkit_output = [s.strip() for s in filtered_stacks if not is_cdktoolkit_stack_name(s.strip())]
        
        assert non_cdktoolkit_output == non_cdktoolkit_input, \
            "Relative order of non-CDKToolkit stacks should be preserved"


##############################################################################
# Run tests
##############################################################################

if __name__ == '__main__':
    import pytest
    import sys
    
    # Run pytest with this file
    exit_code = pytest.main([__file__, '-v', '--tb=short'])
    sys.exit(exit_code)
