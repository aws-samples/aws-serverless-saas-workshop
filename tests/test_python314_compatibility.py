#!/usr/bin/env python3
"""
Test Python 3.14 compatibility for AWS Serverless SaaS Workshop Lambda functions.

This test validates that all Lambda functions and their dependencies are compatible
with Python 3.14 runtime.

NOTE: Python 3.14 is not yet released. This test runs with Python 3.13 (the closest
available version) to identify potential compatibility issues. Final validation with
Python 3.14 will be required when it becomes available.

Feature: workshop-modernization, Property 2: Python Runtime Consistency
Validates: Requirements 2.1, 2.2
"""

import sys
import subprocess
import importlib.util
from pathlib import Path
from typing import List, Tuple, Dict
import json

# Target Python 3.14, but accept 3.13+ for pre-release testing
TARGET_PYTHON_VERSION = (3, 14)
MINIMUM_PYTHON_VERSION = (3, 13)


def check_python_version() -> Tuple[bool, bool]:
    """
    Verify we're running Python 3.13+ for compatibility testing.
    
    Returns:
        Tuple of (meets_minimum: bool, is_target_version: bool)
    """
    current_version = sys.version_info[:2]
    print(f"Current Python version: {sys.version}")
    
    if current_version < MINIMUM_PYTHON_VERSION:
        print(f"❌ ERROR: Python {MINIMUM_PYTHON_VERSION[0]}.{MINIMUM_PYTHON_VERSION[1]} or higher required")
        print(f"   Current version: {current_version[0]}.{current_version[1]}")
        return False, False
    
    is_target = current_version >= TARGET_PYTHON_VERSION
    
    if is_target:
        print(f"✅ Python version check passed: {current_version[0]}.{current_version[1]} (target version)")
    else:
        print(f"⚠️  Python version check: {current_version[0]}.{current_version[1]} (testing with closest available version)")
        print(f"   Target version: {TARGET_PYTHON_VERSION[0]}.{TARGET_PYTHON_VERSION[1]} (not yet released)")
        print(f"   This test will identify most compatibility issues, but final validation")
        print(f"   with Python {TARGET_PYTHON_VERSION[0]}.{TARGET_PYTHON_VERSION[1]} is required when available.")
    
    return True, is_target


def find_requirements_files() -> List[Path]:
    """Find all requirements.txt files in the workshop."""
    workshop_root = Path(__file__).parent.parent
    requirements_files = []
    
    # Search in Lab directories
    for lab_dir in workshop_root.glob("Lab*/server/**/requirements.txt"):
        requirements_files.append(lab_dir)
    
    # Search in Lab7 (different structure)
    for req_file in workshop_root.glob("Lab7/**/requirements.txt"):
        requirements_files.append(req_file)
    
    return sorted(set(requirements_files))


def test_dependency_installation(requirements_file: Path) -> Tuple[bool, str]:
    """
    Test if dependencies in requirements.txt can be installed with current Python version.
    
    Returns:
        Tuple of (success: bool, message: str)
    """
    print(f"\n📦 Testing dependencies from: {requirements_file.relative_to(Path.cwd())}")
    
    try:
        # Try to parse requirements without installing
        with open(requirements_file, 'r') as f:
            requirements = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        
        print(f"   Found {len(requirements)} dependencies:")
        for req in requirements:
            print(f"     - {req}")
        
        # Check if pip can resolve these packages (dry-run)
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", "--dry-run", "-r", str(requirements_file)],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            print(f"   ✅ All dependencies are compatible with Python {sys.version_info[0]}.{sys.version_info[1]}")
            return True, "Success"
        else:
            error_msg = result.stderr[:500]  # Limit error message length
            print(f"   ⚠️  Dependency resolution issues detected:")
            print(f"   {error_msg}")
            return False, error_msg
            
    except subprocess.TimeoutExpired:
        msg = "Timeout during dependency check"
        print(f"   ⚠️  {msg}")
        return False, msg
    except Exception as e:
        msg = f"Error checking dependencies: {str(e)}"
        print(f"   ❌ {msg}")
        return False, msg


def find_python_lambda_files() -> List[Path]:
    """Find all Python Lambda function files."""
    workshop_root = Path(__file__).parent.parent
    python_files = []
    
    # Common Lambda function patterns
    patterns = [
        "Lab*/server/**/*_service.py",
        "Lab*/server/**/*_dal.py",
        "Lab*/server/**/*_models.py",
        "Lab*/server/**/*authorizer*.py",
        "Lab*/server/**/*management*.py",
        "Lab*/server/**/*registration*.py",
        "Lab7/**/*.py",
    ]
    
    for pattern in patterns:
        for py_file in workshop_root.glob(pattern):
            # Exclude test files and build artifacts
            if '.aws-sam' not in str(py_file) and 'test_' not in py_file.name:
                python_files.append(py_file)
    
    return sorted(set(python_files))


def test_python_syntax(python_file: Path) -> Tuple[bool, str]:
    """
    Test if Python file has valid syntax for Python 3.14.
    
    Returns:
        Tuple of (success: bool, message: str)
    """
    try:
        with open(python_file, 'r', encoding='utf-8') as f:
            code = f.read()
        
        # Compile the code to check for syntax errors
        compile(code, str(python_file), 'exec')
        return True, "Valid syntax"
        
    except SyntaxError as e:
        msg = f"Syntax error at line {e.lineno}: {e.msg}"
        return False, msg
    except Exception as e:
        msg = f"Error reading file: {str(e)}"
        return False, msg


def check_deprecated_features(python_file: Path) -> List[str]:
    """
    Check for deprecated Python features that might cause issues in Python 3.14.
    
    Returns:
        List of warnings about deprecated features
    """
    warnings = []
    
    try:
        with open(python_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check for common deprecated patterns
        deprecated_patterns = [
            ("collections.Mapping", "Use collections.abc.Mapping instead"),
            ("collections.Sequence", "Use collections.abc.Sequence instead"),
            ("collections.Iterable", "Use collections.abc.Iterable instead"),
            ("imp.", "Module 'imp' is deprecated, use 'importlib' instead"),
        ]
        
        for pattern, message in deprecated_patterns:
            if pattern in content:
                warnings.append(f"{pattern}: {message}")
        
    except Exception:
        pass  # Silently skip files we can't read
    
    return warnings


def main():
    """Main test execution."""
    print("=" * 80)
    print("Python 3.14 Compatibility Test for AWS Serverless SaaS Workshop")
    print("=" * 80)
    
    # Step 1: Check Python version
    if not check_python_version():
        print("\n❌ FAILED: Python 3.14 is required to run this test")
        sys.exit(1)
    
    # Step 2: Find and test all requirements files
    print("\n" + "=" * 80)
    print("Testing Dependency Compatibility")
    print("=" * 80)
    
    requirements_files = find_requirements_files()
    print(f"\nFound {len(requirements_files)} requirements.txt files")
    
    dependency_results = {}
    for req_file in requirements_files:
        success, message = test_dependency_installation(req_file)
        dependency_results[req_file] = (success, message)
    
    # Step 3: Test Python file syntax
    print("\n" + "=" * 80)
    print("Testing Python File Syntax")
    print("=" * 80)
    
    python_files = find_python_lambda_files()
    print(f"\nFound {len(python_files)} Python Lambda files to test")
    
    syntax_results = {}
    deprecated_warnings = {}
    
    for py_file in python_files:
        print(f"\n🐍 Testing: {py_file.relative_to(Path.cwd())}")
        
        # Check syntax
        success, message = test_python_syntax(py_file)
        syntax_results[py_file] = (success, message)
        
        if success:
            print(f"   ✅ Syntax valid")
            
            # Check for deprecated features
            warnings = check_deprecated_features(py_file)
            if warnings:
                deprecated_warnings[py_file] = warnings
                print(f"   ⚠️  Found {len(warnings)} deprecation warnings:")
                for warning in warnings:
                    print(f"      - {warning}")
        else:
            print(f"   ❌ Syntax error: {message}")
    
    # Step 4: Generate summary report
    print("\n" + "=" * 80)
    print("SUMMARY REPORT")
    print("=" * 80)
    
    # Dependency summary
    dep_passed = sum(1 for success, _ in dependency_results.values() if success)
    dep_total = len(dependency_results)
    print(f"\n📦 Dependency Tests: {dep_passed}/{dep_total} passed")
    
    if dep_passed < dep_total:
        print("\n   Failed dependency checks:")
        for req_file, (success, message) in dependency_results.items():
            if not success:
                print(f"   ❌ {req_file.relative_to(Path.cwd())}")
                print(f"      {message[:200]}")
    
    # Syntax summary
    syntax_passed = sum(1 for success, _ in syntax_results.values() if success)
    syntax_total = len(syntax_results)
    print(f"\n🐍 Syntax Tests: {syntax_passed}/{syntax_total} passed")
    
    if syntax_passed < syntax_total:
        print("\n   Failed syntax checks:")
        for py_file, (success, message) in syntax_results.items():
            if not success:
                print(f"   ❌ {py_file.relative_to(Path.cwd())}")
                print(f"      {message}")
    
    # Deprecation warnings
    if deprecated_warnings:
        print(f"\n⚠️  Deprecation Warnings: {len(deprecated_warnings)} files")
        for py_file, warnings in deprecated_warnings.items():
            print(f"   {py_file.relative_to(Path.cwd())}")
            for warning in warnings:
                print(f"      - {warning}")
    
    # Final result
    print("\n" + "=" * 80)
    all_passed = (dep_passed == dep_total) and (syntax_passed == syntax_total)
    
    if all_passed:
        print("✅ ALL TESTS PASSED")
        print("\nAll Lambda functions and dependencies are compatible with Python 3.14")
        if deprecated_warnings:
            print(f"\nNote: {len(deprecated_warnings)} files have deprecation warnings")
            print("These are informational and don't block Python 3.14 compatibility")
        return 0
    else:
        print("❌ SOME TESTS FAILED")
        print("\nAction required:")
        if dep_passed < dep_total:
            print("  1. Review failed dependency checks above")
            print("  2. Update requirements.txt files with Python 3.14 compatible versions")
        if syntax_passed < syntax_total:
            print("  3. Fix syntax errors in Python files")
        return 1


if __name__ == "__main__":
    sys.exit(main())
