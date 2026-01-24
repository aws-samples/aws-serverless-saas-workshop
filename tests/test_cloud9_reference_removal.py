"""
Property-based test for Cloud9 reference removal.

This test validates that all Cloud9 references have been removed from the workshop
documentation and configuration files.

Property 3: Cloud9 Reference Removal
- For any documentation file (README.md, markdown files) in the workshop,
  the content should not contain references to Cloud9 or Cloud9-specific instructions.
- Validates: Requirements 3.1
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
    
    for root, dirs, files in os.walk(WORKSHOP_ROOT):
        # Remove excluded directories from the search
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        
        for file in files:
            if file.endswith('.md'):
                file_path = Path(root) / file
                # Exclude the audit document itself
                if 'CLOUD9_REFERENCES_AUDIT.md' not in str(file_path):
                    markdown_files.append(file_path)
    
    return markdown_files


def check_cloud9_references(file_path: Path) -> List[Tuple[int, str]]:
    """
    Check a file for Cloud9 references.
    
    Args:
        file_path: Path to the file to check
        
    Returns:
        List of tuples (line_number, line_content) containing Cloud9 references
    """
    cloud9_patterns = [
        r'\bCloud9\b',
        r'\bcloud9\b',
        r'\bC9\b',
        r'Cloud9Setup',
        r'cloud9-',
        r'~/environment/aws-serverless-saas-workshop/Cloud9Setup'
    ]
    
    # Patterns that are acceptable (documenting removal status)
    acceptable_patterns = [
        r'###\s+Cloud9\s+References',  # Section headers
        r'##\s+Cloud9\s+References',
        r'Cloud9Setup directory has been removed',
        r'All Cloud9 references removed',
        r'Remove Cloud9 references',
        r'Cloud9 removal',
        r'Cloud9 Removal',
        r'Cloud9 Directory',
        r'Cloud9 References in Documentation',
        r'Cloud9 setup scripts',
        r'Cloud9-specific',
        r'no Cloud9',
        r'without Cloud9',
        r'REMOVED as part of modernization',
        r'✅.*Cloud9',
        r'Cloud9.*✅',
        r'workshop/Cloud9Setup/.*REMOVED'
    ]
    
    violations = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, start=1):
                # Check if line matches acceptable patterns
                is_acceptable = False
                for acceptable_pattern in acceptable_patterns:
                    if re.search(acceptable_pattern, line):
                        is_acceptable = True
                        break
                
                if is_acceptable:
                    continue
                
                # Check for Cloud9 references
                for pattern in cloud9_patterns:
                    if re.search(pattern, line):
                        violations.append((line_num, line.strip()))
                        break  # Only report each line once
    except Exception as e:
        pytest.fail(f"Error reading file {file_path}: {e}")
    
    return violations


def test_cloud9_setup_directory_removed():
    """
    Test that the Cloud9Setup directory has been removed.
    
    Property: The Cloud9Setup directory should not exist in the workshop.
    """
    cloud9_setup_path = WORKSHOP_ROOT / 'Cloud9Setup'
    
    assert not cloud9_setup_path.exists(), (
        f"Cloud9Setup directory still exists at {cloud9_setup_path}. "
        "This directory should be completely removed."
    )


def test_no_cloud9_references_in_markdown():
    """
    Test that no Cloud9 references exist in markdown files.
    
    Property: All markdown files should be free of Cloud9 references.
    """
    markdown_files = get_all_markdown_files()
    
    assert len(markdown_files) > 0, "No markdown files found to test"
    
    all_violations = {}
    
    for file_path in markdown_files:
        violations = check_cloud9_references(file_path)
        if violations:
            all_violations[str(file_path.relative_to(WORKSHOP_ROOT))] = violations
    
    if all_violations:
        error_msg = "Cloud9 references found in the following files:\n\n"
        for file_path, violations in all_violations.items():
            error_msg += f"\n{file_path}:\n"
            for line_num, line_content in violations:
                error_msg += f"  Line {line_num}: {line_content}\n"
        
        pytest.fail(error_msg)


@given(st.sampled_from(get_all_markdown_files()))
@settings(
    max_examples=100,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
    deadline=None
)
def test_property_no_cloud9_in_any_markdown(markdown_file: Path):
    """
    Property-based test: For any markdown file, it should not contain Cloud9 references.
    
    This test uses Hypothesis to generate test cases by sampling from all markdown files
    in the workshop and verifying each one is free of Cloud9 references.
    
    Args:
        markdown_file: A markdown file path generated by Hypothesis
    """
    violations = check_cloud9_references(markdown_file)
    
    assert len(violations) == 0, (
        f"Cloud9 references found in {markdown_file.relative_to(WORKSHOP_ROOT)}:\n" +
        "\n".join([f"  Line {line_num}: {line_content}" 
                   for line_num, line_content in violations])
    )


def test_cloud9_references_comprehensive():
    """
    Comprehensive test that checks all aspects of Cloud9 removal.
    
    This test validates:
    1. Cloud9Setup directory is removed
    2. No Cloud9 references in markdown files
    3. No Cloud9-specific file paths in documentation
    """
    # Check 1: Cloud9Setup directory removed
    cloud9_setup_path = WORKSHOP_ROOT / 'Cloud9Setup'
    assert not cloud9_setup_path.exists(), "Cloud9Setup directory still exists"
    
    # Check 2: No Cloud9 references in markdown files
    markdown_files = get_all_markdown_files()
    files_with_violations = 0
    total_violations = 0
    
    for file_path in markdown_files:
        violations = check_cloud9_references(file_path)
        if violations:
            files_with_violations += 1
            total_violations += len(violations)
    
    assert files_with_violations == 0, (
        f"Found Cloud9 references in {files_with_violations} files "
        f"({total_violations} total violations)"
    )
    
    # Check 3: Verify specific files that should be updated
    critical_files = [
        WORKSHOP_ROOT / '.kiro' / 'specs' / 'workshop-modernization' / 'workshop-content.md',
        WORKSHOP_ROOT / 'BASELINE_DOCUMENTATION.md'
    ]
    
    for file_path in critical_files:
        if file_path.exists():
            violations = check_cloud9_references(file_path)
            assert len(violations) == 0, (
                f"Critical file {file_path.relative_to(WORKSHOP_ROOT)} "
                f"still contains Cloud9 references"
            )


if __name__ == '__main__':
    # Run the tests
    pytest.main([__file__, '-v'])
