"""
Property-based test for bash command reference removal.

This test validates that all markdown files use correct script execution patterns
and do not contain incorrect bash command references.

Feature: workshop-modernization, Property 10: Bash Command Reference Removal
- For any markdown file in the workshop, script examples should use direct execution (./scripts/)
- For any markdown file, it should not contain patterns like 'bash scripts/' or 'bash ./scripts/'
- Validates: Requirements 7.1, 7.2
"""

import os
import re
from pathlib import Path
from typing import List, Tuple
from hypothesis import given, strategies as st, settings, HealthCheck
import pytest


# Define the workshop root directory
WORKSHOP_ROOT = Path(__file__).parent.parent


def get_all_markdown_files() -> List[Path]:
    """
    Get all markdown files in the workshop directory.
    
    Returns:
        List of Path objects for all markdown files
    """
    markdown_files = []
    
    # Exclude certain directories
    exclude_dirs = {
        '.git', 'node_modules', '.venv', 'build', 'dist', 
        '.aws-sam', '.pytest_cache', '__pycache__', '.hypothesis'
    }
    
    # Exclude audit files that document the patterns being tested
    # (similar to how Cloud9 test excludes CLOUD9_REFERENCES_AUDIT.md)
    exclude_files = {
        'BASH_COMMAND_AUDIT_REPORT.md'
    }
    
    for root, dirs, files in os.walk(WORKSHOP_ROOT):
        # Remove excluded directories from the search
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        
        for file in files:
            if file.endswith('.md') and file not in exclude_files:
                file_path = Path(root) / file
                markdown_files.append(file_path)
    
    return markdown_files


def check_bash_command_references(file_path: Path) -> List[Tuple[int, str, str]]:
    """
    Check a file for incorrect bash command references.
    
    Args:
        file_path: Path to the file to check
        
    Returns:
        List of tuples (line_number, line_content, violation_type) containing violations
    """
    # Patterns that should NOT appear (incorrect usage)
    incorrect_patterns = [
        (r'bash\s+scripts/', 'bash scripts/'),
        (r'bash\s+\./scripts/', 'bash ./scripts/'),
    ]
    
    # Markers that indicate educational "wrong example" sections
    # These sections intentionally show incorrect usage for educational purposes
    wrong_example_markers = [
        '❌',  # Cross mark emoji
        'ABSOLUTELY WRONG',
        'NEVER DO THIS',
        'WRONG:',
        'INCORRECT:',
    ]
    
    violations = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        # Track if we're in a "wrong example" section
        in_wrong_example_section = False
        wrong_example_context_lines = 0
        
        for line_num, line in enumerate(lines, start=1):
            # Check if this line contains a "wrong example" marker
            if any(marker in line for marker in wrong_example_markers):
                in_wrong_example_section = True
                wrong_example_context_lines = 10  # Allow next 10 lines to be wrong examples
            
            # Decrement context counter
            if wrong_example_context_lines > 0:
                wrong_example_context_lines -= 1
                if wrong_example_context_lines == 0:
                    in_wrong_example_section = False
            
            # Skip violations in wrong example sections
            if in_wrong_example_section:
                continue
            
            # Check for incorrect bash command patterns
            for pattern, violation_type in incorrect_patterns:
                if re.search(pattern, line):
                    violations.append((line_num, line.strip(), violation_type))
                    break  # Only report each line once
                    
    except Exception as e:
        pytest.fail(f"Error reading file {file_path}: {e}")
    
    return violations


def test_no_bash_command_references_in_markdown():
    """
    Test that no incorrect bash command references exist in markdown files.
    
    Property: All markdown files should use direct script execution (./scripts/)
    instead of 'bash scripts/' or 'bash ./scripts/'.
    """
    markdown_files = get_all_markdown_files()
    
    assert len(markdown_files) > 0, "No markdown files found to test"
    
    all_violations = {}
    
    for file_path in markdown_files:
        violations = check_bash_command_references(file_path)
        if violations:
            all_violations[str(file_path.relative_to(WORKSHOP_ROOT))] = violations
    
    if all_violations:
        error_msg = "Incorrect bash command references found in the following files:\n\n"
        error_msg += "Scripts should be executed directly (e.g., './scripts/deployment.sh')\n"
        error_msg += "NOT with 'bash' command (e.g., 'bash scripts/deployment.sh')\n\n"
        
        for file_path, violations in all_violations.items():
            error_msg += f"\n{file_path}:\n"
            for line_num, line_content, violation_type in violations:
                error_msg += f"  Line {line_num} [{violation_type}]: {line_content}\n"
        
        pytest.fail(error_msg)


@given(st.sampled_from(get_all_markdown_files()))
@settings(
    max_examples=100,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
    deadline=None
)
def test_property_no_bash_commands_in_any_markdown(markdown_file: Path):
    """
    Property-based test: For any markdown file, it should not contain incorrect bash command patterns.
    
    This test uses Hypothesis to generate test cases by sampling from all markdown files
    in the workshop and verifying each one uses correct script execution patterns.
    
    Feature: workshop-modernization, Property 10: Bash Command Reference Removal
    
    Args:
        markdown_file: A markdown file path generated by Hypothesis
    """
    violations = check_bash_command_references(markdown_file)
    
    assert len(violations) == 0, (
        f"Incorrect bash command references found in {markdown_file.relative_to(WORKSHOP_ROOT)}:\n" +
        "Scripts should be executed directly (e.g., './scripts/deployment.sh')\n" +
        "NOT with 'bash' command (e.g., 'bash scripts/deployment.sh')\n\n" +
        "\n".join([f"  Line {line_num} [{violation_type}]: {line_content}" 
                   for line_num, line_content, violation_type in violations])
    )


def test_bash_command_references_comprehensive():
    """
    Comprehensive test that checks all aspects of bash command reference removal.
    
    This test validates:
    1. No 'bash scripts/' patterns in markdown files
    2. No 'bash ./scripts/' patterns in markdown files
    3. Documentation follows correct script execution guidelines
    """
    markdown_files = get_all_markdown_files()
    files_with_violations = 0
    total_violations = 0
    violation_details = []
    
    for file_path in markdown_files:
        violations = check_bash_command_references(file_path)
        if violations:
            files_with_violations += 1
            total_violations += len(violations)
            violation_details.append((file_path, violations))
    
    if files_with_violations > 0:
        error_msg = f"Found incorrect bash command references in {files_with_violations} files "
        error_msg += f"({total_violations} total violations)\n\n"
        error_msg += "Scripts should be executed directly (e.g., './scripts/deployment.sh')\n"
        error_msg += "NOT with 'bash' command (e.g., 'bash scripts/deployment.sh')\n\n"
        
        for file_path, violations in violation_details:
            error_msg += f"\n{file_path.relative_to(WORKSHOP_ROOT)}:\n"
            for line_num, line_content, violation_type in violations:
                error_msg += f"  Line {line_num} [{violation_type}]: {line_content}\n"
        
        pytest.fail(error_msg)


if __name__ == '__main__':
    # Run the tests
    pytest.main([__file__, '-v'])
