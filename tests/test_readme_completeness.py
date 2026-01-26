"""
Property-based test for README completeness.

This test validates that all lab README files contain the required sections
for comprehensive documentation.

Feature: workshop-modernization, Property 8: README Completeness
- For any lab directory, the README.md file should contain all required sections
- Required sections: Overview, Prerequisites, Architecture, Deployment Steps, Verification, Cleanup, Troubleshooting
- Validates: Requirements 7.1, 7.2, 7.3
"""

import os
import re
from pathlib import Path
from typing import List, Dict, Tuple
from hypothesis import given, strategies as st, settings, HealthCheck
import pytest


# Define the workshop root directory
WORKSHOP_ROOT = Path(__file__).parent.parent


# Required sections that must be present in each lab README
REQUIRED_SECTIONS = [
    "Overview",
    "Prerequisites", 
    "Architecture",
    "Deployment Steps",
    "Verification",
    "Cleanup",
    "Troubleshooting"
]


def get_lab_directories() -> List[Path]:
    """
    Get all lab directories (Lab1 through Lab7).
    
    Returns:
        List of Path objects for lab directories
    """
    lab_dirs = []
    
    for i in range(1, 8):  # Lab1 through Lab7
        lab_dir = WORKSHOP_ROOT / f"Lab{i}"
        if lab_dir.exists() and lab_dir.is_dir():
            lab_dirs.append(lab_dir)
    
    return lab_dirs


def extract_sections_from_readme(readme_path: Path) -> List[str]:
    """
    Extract all section headings from a README file.
    
    Args:
        readme_path: Path to the README.md file
        
    Returns:
        List of section heading texts (without the # markers)
    """
    sections = []
    
    try:
        with open(readme_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Match markdown headings (## Section Name)
        # We look for level 2 headings (##) as main sections
        heading_pattern = r'^##\s+(.+)$'
        matches = re.finditer(heading_pattern, content, re.MULTILINE)
        
        for match in matches:
            section_name = match.group(1).strip()
            sections.append(section_name)
    
    except FileNotFoundError:
        # README doesn't exist
        pass
    except Exception as e:
        # Other errors reading file
        print(f"Error reading {readme_path}: {e}")
    
    return sections


def check_readme_completeness(lab_dir: Path) -> Dict[str, any]:
    """
    Check if a lab's README contains all required sections.
    
    Args:
        lab_dir: Path to the lab directory
        
    Returns:
        Dictionary with:
        - 'exists': bool - whether README.md exists
        - 'sections_found': list - sections present in README
        - 'missing_sections': list - required sections that are missing
        - 'has_all_sections': bool - whether all required sections are present
    """
    readme_path = lab_dir / "README.md"
    
    result = {
        'lab': lab_dir.name,
        'readme_path': str(readme_path),
        'exists': readme_path.exists(),
        'sections_found': [],
        'missing_sections': [],
        'has_all_sections': False
    }
    
    if not result['exists']:
        result['missing_sections'] = REQUIRED_SECTIONS.copy()
        return result
    
    # Extract sections from README
    sections_found = extract_sections_from_readme(readme_path)
    result['sections_found'] = sections_found
    
    # Check which required sections are missing
    # Use case-insensitive comparison and allow partial matches
    sections_found_lower = [s.lower() for s in sections_found]
    
    for required_section in REQUIRED_SECTIONS:
        required_lower = required_section.lower()
        
        # Check if any section contains the required section name
        # This allows "Verification Steps" to match "Verification"
        # and "Testing and Verification" to match "Verification"
        found = any(required_lower in section_lower for section_lower in sections_found_lower)
        
        if not found:
            result['missing_sections'].append(required_section)
    
    result['has_all_sections'] = len(result['missing_sections']) == 0
    
    return result


# ============================================================================
# Unit Tests
# ============================================================================

def test_all_labs_have_readme():
    """
    Test that all lab directories have a README.md file.
    """
    lab_dirs = get_lab_directories()
    
    assert len(lab_dirs) > 0, "No lab directories found"
    
    missing_readmes = []
    
    for lab_dir in lab_dirs:
        readme_path = lab_dir / "README.md"
        if not readme_path.exists():
            missing_readmes.append(lab_dir.name)
    
    assert len(missing_readmes) == 0, \
        f"The following labs are missing README.md files: {', '.join(missing_readmes)}"


def test_all_labs_have_required_sections():
    """
    Test that all lab README files contain all required sections.
    """
    lab_dirs = get_lab_directories()
    
    assert len(lab_dirs) > 0, "No lab directories found"
    
    incomplete_readmes = []
    
    for lab_dir in lab_dirs:
        result = check_readme_completeness(lab_dir)
        
        if not result['has_all_sections']:
            incomplete_readmes.append({
                'lab': result['lab'],
                'missing': result['missing_sections']
            })
    
    if incomplete_readmes:
        error_msg = "The following labs have incomplete README files:\n"
        for item in incomplete_readmes:
            error_msg += f"  {item['lab']}: Missing sections: {', '.join(item['missing'])}\n"
        
        pytest.fail(error_msg)


def test_readme_sections_comprehensive():
    """
    Comprehensive test that checks all labs and provides detailed feedback.
    """
    lab_dirs = get_lab_directories()
    
    assert len(lab_dirs) > 0, "No lab directories found"
    
    all_results = []
    
    for lab_dir in lab_dirs:
        result = check_readme_completeness(lab_dir)
        all_results.append(result)
    
    # Check if any labs have issues
    labs_with_issues = [r for r in all_results if not r['has_all_sections']]
    
    if labs_with_issues:
        error_msg = "\n=== README Completeness Issues ===\n\n"
        
        for result in labs_with_issues:
            error_msg += f"Lab: {result['lab']}\n"
            error_msg += f"  README exists: {result['exists']}\n"
            
            if result['exists']:
                error_msg += f"  Sections found: {', '.join(result['sections_found'])}\n"
                error_msg += f"  Missing sections: {', '.join(result['missing_sections'])}\n"
            else:
                error_msg += f"  ERROR: README.md file not found at {result['readme_path']}\n"
            
            error_msg += "\n"
        
        pytest.fail(error_msg)


# ============================================================================
# Property-Based Tests
# ============================================================================

@given(st.sampled_from(get_lab_directories()))
@settings(
    max_examples=100,  # Run 100 iterations as per requirements
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_readme_has_all_required_sections(lab_dir):
    """
    Property test: For any lab directory, the README.md should contain all required sections.
    
    This property-based test validates that every lab's README includes:
    - Overview
    - Prerequisites
    - Architecture
    - Deployment Steps
    - Verification
    - Cleanup
    - Troubleshooting
    
    Feature: workshop-modernization, Property 8: README Completeness
    Validates: Requirements 7.1, 7.2, 7.3
    """
    result = check_readme_completeness(lab_dir)
    
    # Assert README exists
    assert result['exists'], \
        f"{result['lab']}: README.md file not found at {result['readme_path']}"
    
    # Assert all required sections are present
    assert result['has_all_sections'], \
        f"{result['lab']}: README is missing required sections: {', '.join(result['missing_sections'])}\n" \
        f"Sections found: {', '.join(result['sections_found'])}"


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v"])
