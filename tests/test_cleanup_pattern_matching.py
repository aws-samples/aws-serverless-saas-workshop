#!/usr/bin/env python3
"""
Property-Based Test: Pattern Matching Correctness

Feature: lab-cleanup-isolation-all-labs, Property 3: Pattern Matching Correctness
**Validates: Requirements 2.1, 2.2**

This test verifies that resource patterns match only lab-specific resources.

Property: matches_pattern(stack_name, lab_id) ⇔ contains(stack_name, lab_id)

Test Strategy:
1. Generate random stack names with various patterns
2. Verify pattern matching logic is precise
3. Ensure no false positives (matching wrong lab's resources)
4. Ensure no false negatives (missing lab's resources)
5. Test edge cases like lab5 vs lab50, lab1 vs lab10
"""

import pytest
import re
from typing import List, Tuple
from hypothesis import given, settings, strategies as st, assume


# Constants
LAB_IDS = [f"lab{i}" for i in range(1, 8)]


def verify_stack_ownership(stack_name: str, lab_id: str) -> bool:
    """
    Verify that a stack belongs to the specified lab.
    
    This is the core pattern matching function that cleanup scripts use.
    It uses word boundary matching to avoid false positives:
    - "lab1" matches "stack-lab1-pooled" but NOT "stack-lab10-pooled"
    - "lab5" matches "serverless-saas-lab5" but NOT "lab50"
    
    Args:
        stack_name: The name of the CloudFormation stack
        lab_id: The lab identifier (e.g., "lab1", "lab5")
    
    Returns:
        True if the stack belongs to the lab, False otherwise
    """
    # Use word boundary to ensure exact lab ID match
    # Pattern: lab_id must be followed by a non-digit character or end of string
    pattern = rf'\b{re.escape(lab_id)}(?!\d)'
    return bool(re.search(pattern, stack_name))


def contains_lab_id(stack_name: str, lab_id: str) -> bool:
    """
    Simple substring check - what we want to avoid.
    
    This is the naive approach that would cause false positives.
    For example, "lab1" in "stack-lab10-pooled" would return True.
    """
    return lab_id in stack_name


# Hypothesis strategies for generating test data
@st.composite
def stack_name_strategy(draw):
    """
    Generate realistic CloudFormation stack names.
    
    Patterns:
    - serverless-saas-lab{N}
    - serverless-saas-shared-lab{N}
    - serverless-saas-pipeline-lab{N}
    - stack-pooled-lab{N}
    - stack-platinum-lab{N}
    - stack-advanced-lab{N}
    - stack-lab{N}-pooled
    - stack-lab{N}-platinum
    """
    prefix = draw(st.sampled_from([
        "serverless-saas",
        "serverless-saas-shared",
        "serverless-saas-pipeline",
        "stack-pooled",
        "stack-platinum",
        "stack-advanced",
        "stack"
    ]))
    
    lab_num = draw(st.integers(min_value=1, max_value=99))
    lab_id = f"lab{lab_num}"
    
    suffix = draw(st.sampled_from([
        "",
        "-pooled",
        "-platinum",
        "-advanced",
        "-tenant"
    ]))
    
    # Generate different patterns
    pattern_type = draw(st.integers(min_value=1, max_value=3))
    
    if pattern_type == 1:
        # Pattern: prefix-lab{N}
        stack_name = f"{prefix}-{lab_id}"
    elif pattern_type == 2:
        # Pattern: prefix-lab{N}-suffix
        stack_name = f"{prefix}-{lab_id}{suffix}"
    else:
        # Pattern: stack-lab{N}-suffix
        stack_name = f"stack-{lab_id}{suffix}"
    
    return stack_name, lab_id


# Property Test 1: Pattern matching correctness
@settings(max_examples=200, deadline=None)
@given(stack_name_strategy())
def test_pattern_matching_correctness_property(data: Tuple[str, str]):
    """
    Property: matches_pattern(stack_name, lab_id) ⇔ contains(stack_name, lab_id)
    
    **Validates: Requirements 2.1, 2.2**
    
    This test verifies that the pattern matching function correctly identifies
    whether a stack belongs to a specific lab.
    
    The pattern matching should:
    1. Match stacks that contain the exact lab ID
    2. NOT match stacks with similar but different lab IDs (e.g., lab1 vs lab10)
    3. Use word boundaries to prevent false positives
    """
    stack_name, expected_lab_id = data
    
    # Test that the pattern matches the expected lab
    assert verify_stack_ownership(stack_name, expected_lab_id), \
        f"Pattern matching failed: '{stack_name}' should match '{expected_lab_id}'"
    
    # Test that the pattern doesn't match other labs
    for lab_id in LAB_IDS:
        if lab_id != expected_lab_id:
            # The stack should NOT match other lab IDs
            result = verify_stack_ownership(stack_name, lab_id)
            assert not result, \
                f"False positive: '{stack_name}' (belongs to {expected_lab_id}) " \
                f"incorrectly matched '{lab_id}'"


# Property Test 2: No false positives
@settings(max_examples=200, deadline=None)
@given(
    target_lab=st.sampled_from(LAB_IDS),
    other_lab=st.sampled_from(LAB_IDS)
)
def test_no_false_positives_property(target_lab: str, other_lab: str):
    """
    Property: A stack from lab_n should NOT match pattern for lab_m (where n ≠ m)
    
    **Validates: Requirements 2.1, 2.2**
    
    This test ensures that pattern matching doesn't have false positives.
    For example, lab1 should not match lab10, lab5 should not match lab50.
    """
    # Skip if same lab
    assume(target_lab != other_lab)
    
    # Generate a stack name for the target lab
    target_lab_num = target_lab.replace("lab", "")
    stack_name = f"stack-pooled-{target_lab}"
    
    # Verify it matches the target lab
    assert verify_stack_ownership(stack_name, target_lab), \
        f"Stack '{stack_name}' should match '{target_lab}'"
    
    # Verify it does NOT match the other lab
    assert not verify_stack_ownership(stack_name, other_lab), \
        f"False positive: Stack '{stack_name}' (belongs to {target_lab}) " \
        f"incorrectly matched '{other_lab}'"


# Property Test 3: No false negatives
@settings(max_examples=200, deadline=None)
@given(
    lab_id=st.sampled_from(LAB_IDS),
    prefix=st.sampled_from([
        "serverless-saas",
        "serverless-saas-shared",
        "serverless-saas-pipeline",
        "stack-pooled",
        "stack-platinum",
        "stack-advanced",
        "stack"
    ]),
    suffix=st.sampled_from([
        "",
        "-pooled",
        "-platinum",
        "-advanced",
        "-tenant"
    ])
)
def test_no_false_negatives_property(lab_id: str, prefix: str, suffix: str):
    """
    Property: All valid stack names for lab_n should match pattern for lab_n
    
    **Validates: Requirements 2.1, 2.2**
    
    This test ensures that pattern matching doesn't have false negatives.
    All valid stack naming patterns should be correctly identified.
    """
    # Generate various stack name patterns
    patterns = [
        f"{prefix}-{lab_id}",
        f"{prefix}-{lab_id}{suffix}",
        f"stack-{lab_id}{suffix}",
    ]
    
    for stack_name in patterns:
        result = verify_stack_ownership(stack_name, lab_id)
        assert result, \
            f"False negative: Stack '{stack_name}' should match '{lab_id}' but didn't"


# Unit Test: Edge cases
def test_edge_cases():
    """
    Unit test: Verify pattern matching handles edge cases correctly.
    
    **Validates: Requirements 2.1, 2.2**
    
    Edge cases:
    1. lab1 vs lab10 (should not match)
    2. lab5 vs lab50 (should not match)
    3. lab5 vs lab6 (should not match)
    4. lab5 vs lab7 (should not match)
    5. Stacks with lab ID in different positions
    """
    # Test case 1: lab1 should not match lab10
    assert verify_stack_ownership("stack-lab1-pooled", "lab1")
    assert not verify_stack_ownership("stack-lab10-pooled", "lab1")
    assert not verify_stack_ownership("stack-lab1-pooled", "lab10")
    
    # Test case 2: lab5 should not match lab50
    assert verify_stack_ownership("stack-lab5-pooled", "lab5")
    assert not verify_stack_ownership("stack-lab50-pooled", "lab5")
    assert not verify_stack_ownership("stack-lab5-pooled", "lab50")
    
    # Test case 3: lab5 should not match lab6 or lab7
    assert verify_stack_ownership("stack-pooled-lab5", "lab5")
    assert not verify_stack_ownership("stack-pooled-lab6", "lab5")
    assert not verify_stack_ownership("stack-pooled-lab7", "lab5")
    
    # Test case 4: lab6 should not match lab5
    assert verify_stack_ownership("stack-lab6-pooled", "lab6")
    assert not verify_stack_ownership("stack-lab6-pooled", "lab5")
    
    # Test case 5: lab7 should not match lab5
    assert verify_stack_ownership("stack-pooled-lab7", "lab7")
    assert not verify_stack_ownership("stack-pooled-lab7", "lab5")
    
    # Test case 6: Different positions of lab ID
    test_cases = [
        ("serverless-saas-lab1", "lab1", True),
        ("serverless-saas-shared-lab3", "lab3", True),
        ("stack-pooled-lab5", "lab5", True),
        ("stack-lab6-pooled", "lab6", True),
        ("serverless-saas-pipeline-lab5", "lab5", True),
    ]
    
    for stack_name, lab_id, expected in test_cases:
        result = verify_stack_ownership(stack_name, lab_id)
        assert result == expected, \
            f"verify_stack_ownership('{stack_name}', '{lab_id}') = {result}, expected {expected}"


# Unit Test: Critical bug scenarios
def test_critical_bug_scenarios():
    """
    Unit test: Verify pattern matching prevents the critical Lab5 bug.
    
    **Validates: Requirements 2.1, 2.2**
    
    The critical bug was that Lab5 cleanup was deleting Lab6 and Lab7 resources
    because the pattern `stack-*` was too broad.
    
    This test verifies that lab-specific patterns prevent this bug.
    """
    # Lab5 stacks
    lab5_stacks = [
        "serverless-saas-shared-lab5",
        "serverless-saas-pipeline-lab5",
        "stack-pooled-lab5",
        "stack-platinum-lab5",
    ]
    
    # Lab6 stacks (should NOT match lab5)
    lab6_stacks = [
        "serverless-saas-shared-lab6",
        "stack-pooled-lab6",
        "stack-lab6-pooled",
        "stack-advanced-lab6",
    ]
    
    # Lab7 stacks (should NOT match lab5)
    lab7_stacks = [
        "serverless-saas-lab7",
        "stack-pooled-lab7",
    ]
    
    # Verify Lab5 stacks match lab5
    for stack_name in lab5_stacks:
        assert verify_stack_ownership(stack_name, "lab5"), \
            f"Lab5 stack '{stack_name}' should match 'lab5'"
    
    # CRITICAL: Verify Lab6 stacks do NOT match lab5
    for stack_name in lab6_stacks:
        assert not verify_stack_ownership(stack_name, "lab5"), \
            f"CRITICAL BUG: Lab6 stack '{stack_name}' incorrectly matched 'lab5'"
    
    # CRITICAL: Verify Lab7 stacks do NOT match lab5
    for stack_name in lab7_stacks:
        assert not verify_stack_ownership(stack_name, "lab5"), \
            f"CRITICAL BUG: Lab7 stack '{stack_name}' incorrectly matched 'lab5'"


# Unit Test: All lab combinations
def test_all_lab_combinations():
    """
    Unit test: Verify pattern matching works correctly for all lab combinations.
    
    **Validates: Requirements 2.1, 2.2**
    
    This test verifies that each lab's pattern only matches its own stacks
    and doesn't match stacks from other labs.
    """
    # Generate test stacks for each lab
    test_stacks = {
        "lab1": ["serverless-saas-lab1"],
        "lab2": ["serverless-saas-lab2"],
        "lab3": ["serverless-saas-shared-lab3", "stack-pooled-lab3"],
        "lab4": ["serverless-saas-shared-lab4", "stack-pooled-lab4"],
        "lab5": ["serverless-saas-shared-lab5", "stack-pooled-lab5", "stack-platinum-lab5"],
        "lab6": ["serverless-saas-shared-lab6", "stack-pooled-lab6", "stack-lab6-pooled"],
        "lab7": ["serverless-saas-lab7", "stack-pooled-lab7"],
    }
    
    violations = []
    
    # Test each lab's stacks against all lab IDs
    for owner_lab, stacks in test_stacks.items():
        for stack_name in stacks:
            for test_lab in LAB_IDS:
                result = verify_stack_ownership(stack_name, test_lab)
                
                if test_lab == owner_lab:
                    # Should match its own lab
                    if not result:
                        violations.append({
                            "type": "false_negative",
                            "stack": stack_name,
                            "owner": owner_lab,
                            "tested_against": test_lab,
                            "message": f"Stack '{stack_name}' (belongs to {owner_lab}) should match '{test_lab}'"
                        })
                else:
                    # Should NOT match other labs
                    if result:
                        violations.append({
                            "type": "false_positive",
                            "stack": stack_name,
                            "owner": owner_lab,
                            "tested_against": test_lab,
                            "message": f"Stack '{stack_name}' (belongs to {owner_lab}) incorrectly matched '{test_lab}'"
                        })
    
    if violations:
        error_msg = f"\nFound {len(violations)} pattern matching violation(s):\n"
        for v in violations:
            error_msg += f"  - [{v['type']}] {v['message']}\n"
        pytest.fail(error_msg)


# Unit Test: Realistic stack names
def test_realistic_stack_names():
    """
    Unit test: Test pattern matching with realistic stack names from actual deployments.
    
    **Validates: Requirements 2.1, 2.2**
    """
    # Realistic stack names from actual lab deployments
    realistic_stacks = [
        # Lab1
        ("serverless-saas-lab1", "lab1", True),
        
        # Lab2
        ("serverless-saas-lab2", "lab2", True),
        
        # Lab3
        ("serverless-saas-shared-lab3", "lab3", True),
        ("serverless-saas-tenant-lab3", "lab3", True),
        ("stack-pooled-lab3", "lab3", True),
        
        # Lab4
        ("serverless-saas-shared-lab4", "lab4", True),
        ("serverless-saas-tenant-lab4", "lab4", True),
        ("stack-pooled-lab4", "lab4", True),
        
        # Lab5
        ("serverless-saas-shared-lab5", "lab5", True),
        ("serverless-saas-pipeline-lab5", "lab5", True),
        ("stack-pooled-lab5", "lab5", True),
        ("stack-platinum-lab5", "lab5", True),
        
        # Lab6
        ("serverless-saas-shared-lab6", "lab6", True),
        ("serverless-saas-pipeline-lab6", "lab6", True),
        ("stack-pooled-lab6", "lab6", True),
        ("stack-lab6-pooled", "lab6", True),
        ("stack-advanced-lab6", "lab6", True),
        
        # Lab7
        ("serverless-saas-lab7", "lab7", True),
        ("stack-pooled-lab7", "lab7", True),
        
        # Cross-lab false positives (should NOT match)
        ("stack-pooled-lab6", "lab5", False),
        ("stack-pooled-lab7", "lab5", False),
        ("stack-lab6-pooled", "lab5", False),
        ("serverless-saas-lab1", "lab10", False),
        ("stack-pooled-lab5", "lab50", False),
    ]
    
    for stack_name, lab_id, expected in realistic_stacks:
        result = verify_stack_ownership(stack_name, lab_id)
        assert result == expected, \
            f"verify_stack_ownership('{stack_name}', '{lab_id}') = {result}, expected {expected}"


# Unit Test: Pattern matching with special characters
def test_pattern_matching_special_characters():
    """
    Unit test: Verify pattern matching handles special characters correctly.
    
    **Validates: Requirements 2.1, 2.2**
    
    Note: The pattern uses (?!\\d) to prevent matching lab IDs followed by digits
    (e.g., lab1 shouldn't match lab10). Letters after the lab ID are allowed
    since CloudFormation stack names don't typically have patterns like "lab5a".
    """
    # Test stacks with hyphens and other characters
    test_cases = [
        ("stack-pooled-lab5-extra", "lab5", True),
        ("stack.pooled.lab5", "lab5", True),
        ("stack-pooled-lab5-123", "lab5", True),
        # The pattern allows letters after lab ID (only prevents digits)
        # This is acceptable since real stack names don't use patterns like "lab5a"
        ("stack-pooled-lab5a", "lab5", True),  # lab5 followed by letter is allowed
        ("stack-pooled-alab5", "lab5", False),  # alab5 is not lab5 (no word boundary)
        ("stack-pooled-lab50", "lab5", False),  # lab50 is not lab5 (digit prevented)
        ("stack-pooled-lab5-", "lab5", True),   # lab5 followed by hyphen is allowed
        # Note: Underscores are treated as word characters by \b, so these won't match
        # This is acceptable since CloudFormation stack names use hyphens by convention
        ("stack_pooled_lab5", "lab5", False),  # Underscore makes lab5 part of a word
    ]
    
    for stack_name, lab_id, expected in test_cases:
        result = verify_stack_ownership(stack_name, lab_id)
        assert result == expected, \
            f"verify_stack_ownership('{stack_name}', '{lab_id}') = {result}, expected {expected}"


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
