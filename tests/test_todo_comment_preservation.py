"""
Property-based tests for TODO comment preservation in workshop modernization.

Feature: workshop-modernization, Property 9: TODO Comment Preservation
Validates: Requirements 8.1, 8.2

This test suite ensures that TODO comments in source code files are preserved
after modernization updates. TODO comments are intentionally left for workshop
participants to complete as part of the learning experience.
"""

import os
import re
from pathlib import Path
from typing import Dict, List, Tuple

import pytest
from hypothesis import given, strategies as st, settings


# Expected TODO comments in workshop labs (baseline from manual inspection)
# Note: Paths are relative to workshop root (not including "workshop/" prefix)
EXPECTED_TODOS = {
    "Lab2/server/TenantManagementService/tenant-management.py": [
        "#TODO: Implement the below method"
    ],
    "Lab2/server/TenantManagementService/tenant-registration.py": [
        "#TODO: Implement this method"
    ],
    "Lab2/server/TenantManagementService/user-management.py": [
        "#TODO: Implement the below method"
    ],
    "Lab3/server/ProductService/product_service_dal.py": [
        "#TODO: Implement this method"
    ],
    "Lab3/server/ProductService/product_service.py": [
        "#TODO: Capture metrics to denote that one product was created by tenant"
    ],
    "Lab3/server/layers/metrics_manager.py": [
        "#TODO: Implement the below method"
    ],
    "Lab3/server/Resources/tenant_authorizer.py": [
        "# TODO: Add tenant context to authResponse"
    ],
    "Lab3/server/Resources/shared_service_authorizer.py": [
        "#TODO: Add policy so that only tenant and SaaS admins can add/modify tenant information"
    ],
    "Lab4/server/Resources/tenant_authorizer.py": [
        "#TODO : Add code for Fine-Grained-Access-Control"
    ],
    "Lab4/server/OrderService/order_service_dal.py": [
        "#TODO: Implement this method"
    ],
    "Lab5/server/TenantManagementService/tenant-management.py": [
        "#TODO: read table names from env vars",
        "#TODO: read table names from env vars",
        "#TODO: read table names from env vars"
    ],
    "Lab6/server/Resources/tenant_authorizer.py": [
        "#TODO: Get API Key from tenant management table",
        "#TODO: Assign API Key to authorizer response"
    ],
    "Lab6/server/TenantManagementService/tenant-management.py": [
        "#TODO: read table names from env vars",
        "#TODO: Save API Key inside the table**",
        "#TODO: read table names from env vars",
        "#TODO: read table names from env vars"
    ],
    "Lab6/server/TenantManagementService/tenant-registration.py": [
        "#TODO: Pass relevant apikey to tenant_details object based upon tenant tier"
    ],
    "Lab7/TenantUsageAndCost/tenant_usage_and_cost.py": [
        "#TODO: Get total cost of DynamoDB for the current date",
        "#TODO: Write the query to get the DynamoDB WCU and RCUs consumption grouped by TenantId",
        "#TODO: Write the query to get the Total DynamoDB WCU and RCUs consumption across all tenants",
        "#TODO: Save the tenant attribution data inside a dynamodb table",
        "#TODO: Write the below query to get the total lambda invocations grouped by tenants",
        "#TODO: Write the below query to get the total lambda invocations across all tenants"
    ]
}


def get_workshop_root() -> Path:
    """Get the workshop root directory."""
    current_dir = Path(__file__).resolve().parent
    return current_dir.parent


def find_python_files_in_labs() -> List[Path]:
    """
    Find all Python source files in Lab directories.
    
    Excludes:
    - Test files
    - Virtual environments
    - Node modules
    - AWS SAM build artifacts
    - __pycache__ directories
    """
    workshop_root = get_workshop_root()
    python_files = []
    
    # Search in Lab directories
    for lab_dir in workshop_root.glob("Lab*"):
        if lab_dir.is_dir():
            for py_file in lab_dir.rglob("*.py"):
                # Exclude test files, venv, node_modules, build artifacts
                path_str = str(py_file)
                if any(exclude in path_str for exclude in [
                    "__pycache__",
                    "venv",
                    "node_modules",
                    ".aws-sam",
                    "/tests/",
                    "test_"
                ]):
                    continue
                python_files.append(py_file)
    
    return python_files


def extract_todo_comments(file_path: Path) -> List[Tuple[int, str]]:
    """
    Extract TODO comments from a Python file.
    
    Returns:
        List of tuples (line_number, todo_text)
    """
    todos = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, start=1):
                # Match TODO comments (case-insensitive, with or without space after #)
                if re.search(r'#\s*TODO', line, re.IGNORECASE):
                    # Extract the TODO comment text
                    todo_match = re.search(r'#\s*TODO[:\s]*(.*)', line, re.IGNORECASE)
                    if todo_match:
                        todo_text = todo_match.group(0).strip()
                        todos.append((line_num, todo_text))
    except Exception as e:
        pytest.fail(f"Failed to read file {file_path}: {e}")
    
    return todos


def normalize_todo_text(todo: str) -> str:
    """
    Normalize TODO comment text for comparison.
    
    Handles variations in:
    - Whitespace after #
    - Case (TODO vs todo)
    - Colon after TODO
    """
    # Remove leading/trailing whitespace
    todo = todo.strip()
    # Normalize whitespace after #
    todo = re.sub(r'#\s*', '#', todo)
    # Normalize TODO case
    todo = re.sub(r'#TODO', '#TODO', todo, flags=re.IGNORECASE)
    # Normalize colon after TODO
    todo = re.sub(r'#TODO\s*:', '#TODO:', todo)
    return todo


# Unit Tests

def test_all_expected_files_exist():
    """Verify that all files with expected TODOs exist."""
    workshop_root = get_workshop_root()
    
    for file_path in EXPECTED_TODOS.keys():
        full_path = workshop_root / file_path
        assert full_path.exists(), f"Expected file not found: {file_path}"


def test_all_expected_todos_present():
    """Verify that all expected TODO comments are present in their files."""
    workshop_root = get_workshop_root()
    
    for file_path, expected_todos in EXPECTED_TODOS.items():
        full_path = workshop_root / file_path
        actual_todos = extract_todo_comments(full_path)
        actual_todo_texts = [normalize_todo_text(todo[1]) for todo in actual_todos]
        
        for expected_todo in expected_todos:
            normalized_expected = normalize_todo_text(expected_todo)
            assert normalized_expected in actual_todo_texts, (
                f"Expected TODO not found in {file_path}:\n"
                f"  Expected: {expected_todo}\n"
                f"  Found TODOs: {actual_todo_texts}"
            )


def test_no_unexpected_todo_removal():
    """
    Verify that no TODO comments have been removed from files.
    
    This test ensures that the number of TODOs in each file matches
    or exceeds the expected count (in case new TODOs are added).
    """
    workshop_root = get_workshop_root()
    
    for file_path, expected_todos in EXPECTED_TODOS.items():
        full_path = workshop_root / file_path
        actual_todos = extract_todo_comments(full_path)
        
        assert len(actual_todos) >= len(expected_todos), (
            f"TODO comments may have been removed from {file_path}:\n"
            f"  Expected at least: {len(expected_todos)} TODOs\n"
            f"  Found: {len(actual_todos)} TODOs\n"
            f"  Expected TODOs: {expected_todos}\n"
            f"  Found TODOs: {[todo[1] for todo in actual_todos]}"
        )


def test_todo_comments_comprehensive():
    """
    Comprehensive test that verifies TODO preservation across all files.
    
    This test:
    1. Finds all Python files in Lab directories
    2. Extracts TODO comments from each file
    3. Verifies that files with expected TODOs have them
    4. Reports any files with unexpected TODOs (for awareness)
    """
    workshop_root = get_workshop_root()
    python_files = find_python_files_in_labs()
    
    files_with_todos: Dict[str, List[Tuple[int, str]]] = {}
    
    for py_file in python_files:
        todos = extract_todo_comments(py_file)
        if todos:
            relative_path = str(py_file.relative_to(workshop_root))
            files_with_todos[relative_path] = todos
    
    # Verify all expected files have TODOs
    for expected_file in EXPECTED_TODOS.keys():
        assert expected_file in files_with_todos, (
            f"Expected file has no TODOs: {expected_file}"
        )
    
    # Report files with TODOs (for awareness, not failure)
    print("\n=== Files with TODO comments ===")
    for file_path, todos in sorted(files_with_todos.items()):
        print(f"\n{file_path}:")
        for line_num, todo_text in todos:
            print(f"  Line {line_num}: {todo_text}")


# Property-Based Tests

@settings(max_examples=100)
@given(st.sampled_from(list(EXPECTED_TODOS.keys())))
def test_property_todo_preservation_in_file(file_path: str):
    """
    Property: For any file with expected TODOs, all expected TODOs should be present.
    
    This property-based test randomly samples files from the expected TODO list
    and verifies that all expected TODOs are present in each file.
    
    Feature: workshop-modernization, Property 9: TODO Comment Preservation
    """
    workshop_root = get_workshop_root()
    full_path = workshop_root / file_path
    
    # Extract actual TODOs from the file
    actual_todos = extract_todo_comments(full_path)
    actual_todo_texts = [normalize_todo_text(todo[1]) for todo in actual_todos]
    
    # Get expected TODOs for this file
    expected_todos = EXPECTED_TODOS[file_path]
    
    # Verify each expected TODO is present
    for expected_todo in expected_todos:
        normalized_expected = normalize_todo_text(expected_todo)
        assert normalized_expected in actual_todo_texts, (
            f"TODO comment missing or modified in {file_path}:\n"
            f"  Expected: {expected_todo}\n"
            f"  Found: {actual_todo_texts}"
        )


@settings(max_examples=100)
@given(st.sampled_from(list(EXPECTED_TODOS.keys())))
def test_property_todo_count_not_decreased(file_path: str):
    """
    Property: For any file with expected TODOs, the number of TODOs should not decrease.
    
    This property ensures that TODO comments are not removed during modernization.
    The count can increase (new TODOs added) but should never decrease.
    
    Feature: workshop-modernization, Property 9: TODO Comment Preservation
    """
    workshop_root = get_workshop_root()
    full_path = workshop_root / file_path
    
    # Extract actual TODOs from the file
    actual_todos = extract_todo_comments(full_path)
    expected_count = len(EXPECTED_TODOS[file_path])
    actual_count = len(actual_todos)
    
    assert actual_count >= expected_count, (
        f"TODO count decreased in {file_path}:\n"
        f"  Expected at least: {expected_count} TODOs\n"
        f"  Found: {actual_count} TODOs\n"
        f"  This suggests TODOs may have been removed during modernization."
    )


@settings(max_examples=100)
@given(st.sampled_from(find_python_files_in_labs()))
def test_property_todo_format_consistency(py_file: Path):
    """
    Property: For any Python file with TODOs, all TODOs should follow consistent format.
    
    This property verifies that TODO comments follow the expected format:
    - Start with # (comment marker)
    - Followed by TODO (case-insensitive)
    - Optionally followed by : or whitespace
    - Followed by descriptive text
    
    Feature: workshop-modernization, Property 9: TODO Comment Preservation
    """
    todos = extract_todo_comments(py_file)
    
    for line_num, todo_text in todos:
        # Verify TODO format
        assert re.match(r'#\s*TODO[:\s]', todo_text, re.IGNORECASE), (
            f"TODO comment has incorrect format in {py_file}:{line_num}\n"
            f"  Found: {todo_text}\n"
            f"  Expected format: #TODO: <description> or #TODO <description>"
        )
        
        # Verify TODO has descriptive text (not just "#TODO")
        todo_content = re.sub(r'#\s*TODO[:\s]*', '', todo_text, flags=re.IGNORECASE).strip()
        assert len(todo_content) > 0, (
            f"TODO comment lacks description in {py_file}:{line_num}\n"
            f"  Found: {todo_text}\n"
            f"  TODOs should include descriptive text for workshop participants."
        )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
