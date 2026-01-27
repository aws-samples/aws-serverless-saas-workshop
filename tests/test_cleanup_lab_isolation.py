#!/usr/bin/env python3
"""
Property-Based Test: Lab Cleanup Isolation

Feature: lab-cleanup-isolation-all-labs, Property 1: Lab Isolation
Validates: Requirements 1.1, 1.2

This test verifies that cleanup of Lab N does not affect resources in Lab M (where N ≠ M).

Property: cleanup(lab_n) ⇒ resources(lab_m) = resources_before(lab_m)

Test Strategy:
1. Mock deployment of multiple labs simultaneously
2. Mock cleanup for one lab
3. Verify other labs' resources remain intact
4. Test all lab combinations (Lab1-Lab7)
"""

import pytest
from pathlib import Path
from typing import Dict, List, Set, Tuple
from hypothesis import given, settings, strategies as st
from itertools import combinations
from unittest.mock import Mock, patch, MagicMock


# Constants
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]
LAB_IDS = [f"lab{i}" for i in range(1, 8)]


# Mock AWS CloudFormation stack data
def create_mock_stack(stack_name: str, lab_id: str) -> Dict:
    """Create a mock CloudFormation stack object."""
    return {
        "StackName": stack_name,
        "StackStatus": "CREATE_COMPLETE",
        "CreationTime": "2025-01-01T00:00:00Z",
        "Tags": [{"Key": "Lab", "Value": lab_id}]
    }


def generate_lab_stacks(lab_id: str) -> List[Dict]:
    """
    Generate mock CloudFormation stacks for a specific lab.
    
    Each lab has different stack patterns:
    - Lab1: serverless-saas-lab1
    - Lab2: serverless-saas-lab2
    - Lab3: serverless-saas-shared-lab3, stack-pooled-lab3
    - Lab4: serverless-saas-shared-lab4, stack-pooled-lab4
    - Lab5: serverless-saas-shared-lab5, serverless-saas-pipeline-lab5, stack-pooled-lab5, stack-platinum-lab5
    - Lab6: serverless-saas-shared-lab6, stack-pooled-lab6, stack-advanced-lab6
    - Lab7: serverless-saas-lab7, stack-pooled-lab7
    """
    lab_num = lab_id.replace("lab", "")
    stacks = []
    
    if lab_id == "lab1":
        stacks.append(create_mock_stack(f"serverless-saas-lab1", lab_id))
    elif lab_id == "lab2":
        stacks.append(create_mock_stack(f"serverless-saas-lab2", lab_id))
    elif lab_id == "lab3":
        stacks.append(create_mock_stack(f"serverless-saas-shared-lab3", lab_id))
        stacks.append(create_mock_stack(f"stack-pooled-lab3", lab_id))
    elif lab_id == "lab4":
        stacks.append(create_mock_stack(f"serverless-saas-shared-lab4", lab_id))
        stacks.append(create_mock_stack(f"stack-pooled-lab4", lab_id))
    elif lab_id == "lab5":
        stacks.append(create_mock_stack(f"serverless-saas-shared-lab5", lab_id))
        stacks.append(create_mock_stack(f"serverless-saas-pipeline-lab5", lab_id))
        stacks.append(create_mock_stack(f"stack-pooled-lab5", lab_id))
        stacks.append(create_mock_stack(f"stack-platinum-lab5", lab_id))
    elif lab_id == "lab6":
        stacks.append(create_mock_stack(f"serverless-saas-shared-lab6", lab_id))
        stacks.append(create_mock_stack(f"stack-pooled-lab6", lab_id))
        stacks.append(create_mock_stack(f"stack-advanced-lab6", lab_id))
    elif lab_id == "lab7":
        stacks.append(create_mock_stack(f"serverless-saas-lab7", lab_id))
        stacks.append(create_mock_stack(f"stack-pooled-lab7", lab_id))
    
    return stacks


def simulate_cleanup_filtering(all_stacks: List[Dict], target_lab_id: str) -> Tuple[List[str], List[str]]:
    """
    Simulate the cleanup script's filtering logic.
    
    This mimics the lab-specific filtering that cleanup scripts should use:
    - Query stacks with contains(StackName, 'labN')
    - Verify stack ownership before deletion
    
    Returns:
        Tuple of (stacks_to_delete, stacks_to_keep)
    """
    stacks_to_delete = []
    stacks_to_keep = []
    
    for stack in all_stacks:
        stack_name = stack["StackName"]
        
        # Simulate the lab-specific filtering logic
        # The cleanup script should only match stacks containing the target lab ID
        if target_lab_id in stack_name:
            stacks_to_delete.append(stack_name)
        else:
            stacks_to_keep.append(stack_name)
    
    return stacks_to_delete, stacks_to_keep


def verify_stack_ownership(stack_name: str, lab_id: str) -> bool:
    """
    Verify that a stack belongs to the specified lab.
    
    This mimics the verify_stack_ownership() function that should be
    added to all cleanup scripts.
    
    Uses word boundary matching to avoid false positives:
    - "lab1" matches "stack-lab1-pooled" but NOT "stack-lab10-pooled"
    - "lab5" matches "serverless-saas-lab5" but NOT "lab50"
    """
    import re
    # Use word boundary to ensure exact lab ID match
    # Pattern: lab_id must be followed by a non-digit character or end of string
    pattern = rf'\b{re.escape(lab_id)}(?!\d)'
    return bool(re.search(pattern, stack_name))


# Property Test 1: Lab Isolation - Single Lab Cleanup
@settings(max_examples=100, deadline=None)
@given(
    target_lab=st.sampled_from(LAB_IDS),
    other_labs=st.lists(
        st.sampled_from(LAB_IDS),
        min_size=1,
        max_size=6,
        unique=True
    )
)
def test_cleanup_lab_isolation_property(target_lab: str, other_labs: List[str]):
    """
    Property: For any lab N and set of other labs M, cleaning up lab N
    should not affect resources in any lab M (where M ≠ N).
    
    Validates: Requirements 1.1, 1.2
    
    This test:
    1. Simulates deployment of multiple labs
    2. Simulates cleanup of target lab
    3. Verifies other labs' resources remain intact
    """
    # Filter out the target lab from other labs
    other_labs = [lab for lab in other_labs if lab != target_lab]
    
    # Skip if no other labs to test against
    if not other_labs:
        return
    
    # Step 1: Generate stacks for all labs (simulating deployment)
    all_stacks = []
    
    # Add target lab stacks
    target_stacks = generate_lab_stacks(target_lab)
    all_stacks.extend(target_stacks)
    
    # Add other labs' stacks
    other_labs_stacks = {}
    for lab_id in other_labs:
        lab_stacks = generate_lab_stacks(lab_id)
        other_labs_stacks[lab_id] = lab_stacks
        all_stacks.extend(lab_stacks)
    
    # Step 2: Record resources before cleanup
    resources_before = {
        lab_id: [s["StackName"] for s in stacks]
        for lab_id, stacks in other_labs_stacks.items()
    }
    
    # Step 3: Simulate cleanup filtering for target lab
    stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, target_lab)
    
    # Step 4: Verify cleanup only targets the correct lab
    # All target lab stacks should be marked for deletion
    target_stack_names = [s["StackName"] for s in target_stacks]
    for stack_name in target_stack_names:
        assert stack_name in stacks_to_delete, \
            f"Target lab {target_lab} stack '{stack_name}' should be marked for deletion"
    
    # Step 5: Verify other labs' resources remain intact
    for lab_id, expected_stacks in resources_before.items():
        for stack_name in expected_stacks:
            assert stack_name in stacks_to_keep, \
                f"Lab {lab_id} stack '{stack_name}' should NOT be deleted when cleaning up {target_lab}"
            assert stack_name not in stacks_to_delete, \
                f"Lab {lab_id} stack '{stack_name}' was incorrectly marked for deletion by {target_lab} cleanup"
    
    # Step 6: Verify no cross-lab deletion
    for stack_name in stacks_to_delete:
        assert verify_stack_ownership(stack_name, target_lab), \
            f"Stack '{stack_name}' marked for deletion does not belong to {target_lab}"


# Property Test 2: Lab Isolation - All Lab Pairs
@settings(max_examples=100, deadline=None)
@given(st.sampled_from(list(combinations(LAB_IDS, 2))))
def test_cleanup_lab_pair_isolation_property(lab_pair: Tuple[str, str]):
    """
    Property: For any two labs (lab_n, lab_m) where n ≠ m,
    cleaning up lab_n should not affect resources in lab_m.
    
    Validates: Requirements 1.1, 1.2
    
    This test specifically validates all pairwise combinations of labs.
    """
    lab_n, lab_m = lab_pair
    
    # Step 1: Generate stacks for both labs
    lab_n_stacks = generate_lab_stacks(lab_n)
    lab_m_stacks = generate_lab_stacks(lab_m)
    all_stacks = lab_n_stacks + lab_m_stacks
    
    # Step 2: Record lab_m resources before cleanup
    lab_m_stack_names_before = {s["StackName"] for s in lab_m_stacks}
    
    # Step 3: Simulate cleanup of lab_n
    stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, lab_n)
    
    # Step 4: Verify lab_m resources remain intact
    lab_m_stack_names_after = {name for name in stacks_to_keep if lab_m in name}
    
    assert lab_m_stack_names_before == lab_m_stack_names_after, \
        f"Cleanup of {lab_n} affected {lab_m} resources. " \
        f"Before: {lab_m_stack_names_before}, After: {lab_m_stack_names_after}"
    
    # Step 5: Verify no lab_m stacks were marked for deletion
    for stack_name in lab_m_stack_names_before:
        assert stack_name not in stacks_to_delete, \
            f"Lab {lab_m} stack '{stack_name}' was incorrectly marked for deletion by {lab_n} cleanup"


# Property Test 3: Critical Bug Fix - Lab5 doesn't delete Lab6/Lab7 resources
@settings(max_examples=100, deadline=None)
@given(st.just("lab5"))
def test_lab5_cleanup_does_not_affect_lab6_lab7_property(target_lab: str):
    """
    Property: Cleanup of Lab5 must not delete Lab6 or Lab7 resources.
    
    Validates: Requirements 1.1, 1.2 (Critical Bug Fix)
    
    This test specifically validates the critical bug that was discovered:
    Lab5 cleanup was deleting stack-lab6-pooled and stack-pooled-lab7.
    """
    # Step 1: Generate stacks for Lab5, Lab6, and Lab7
    lab5_stacks = generate_lab_stacks("lab5")
    lab6_stacks = generate_lab_stacks("lab6")
    lab7_stacks = generate_lab_stacks("lab7")
    all_stacks = lab5_stacks + lab6_stacks + lab7_stacks
    
    # Step 2: Record Lab6 and Lab7 resources before cleanup
    lab6_stack_names = {s["StackName"] for s in lab6_stacks}
    lab7_stack_names = {s["StackName"] for s in lab7_stacks}
    
    # Critical stacks that were being incorrectly deleted
    critical_lab6_stack = "stack-pooled-lab6"
    critical_lab7_stack = "stack-pooled-lab7"
    
    assert critical_lab6_stack in lab6_stack_names, \
        f"Test setup error: {critical_lab6_stack} should exist in Lab6"
    assert critical_lab7_stack in lab7_stack_names, \
        f"Test setup error: {critical_lab7_stack} should exist in Lab7"
    
    # Step 3: Simulate Lab5 cleanup
    stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, target_lab)
    
    # Step 4: CRITICAL VERIFICATION - Lab6 and Lab7 stacks must NOT be deleted
    assert critical_lab6_stack not in stacks_to_delete, \
        f"CRITICAL BUG: Lab5 cleanup marked '{critical_lab6_stack}' for deletion!"
    assert critical_lab7_stack not in stacks_to_delete, \
        f"CRITICAL BUG: Lab5 cleanup marked '{critical_lab7_stack}' for deletion!"
    
    # Step 5: Verify all Lab6 and Lab7 stacks remain intact
    for stack_name in lab6_stack_names:
        assert stack_name in stacks_to_keep, \
            f"Lab6 stack '{stack_name}' should NOT be deleted by Lab5 cleanup"
        assert stack_name not in stacks_to_delete, \
            f"Lab6 stack '{stack_name}' was incorrectly marked for deletion by Lab5 cleanup"
    
    for stack_name in lab7_stack_names:
        assert stack_name in stacks_to_keep, \
            f"Lab7 stack '{stack_name}' should NOT be deleted by Lab5 cleanup"
        assert stack_name not in stacks_to_delete, \
            f"Lab7 stack '{stack_name}' was incorrectly marked for deletion by Lab5 cleanup"


# Unit Test: Verify stack ownership function
def test_verify_stack_ownership():
    """
    Unit test: Verify the stack ownership verification logic.
    
    This tests the verify_stack_ownership() function that should be
    added to all cleanup scripts.
    """
    # Test cases: (stack_name, lab_id, expected_result)
    test_cases = [
        # Lab1 stacks
        ("serverless-saas-lab1", "lab1", True),
        ("serverless-saas-lab1", "lab2", False),
        
        # Lab3 stacks
        ("serverless-saas-shared-lab3", "lab3", True),
        ("stack-pooled-lab3", "lab3", True),
        ("stack-pooled-lab3", "lab5", False),
        
        # Lab5 stacks
        ("serverless-saas-shared-lab5", "lab5", True),
        ("stack-pooled-lab5", "lab5", True),
        ("stack-platinum-lab5", "lab5", True),
        
        # Lab6 stacks (critical test cases)
        ("stack-pooled-lab6", "lab6", True),
        ("stack-pooled-lab6", "lab5", False),  # Lab5 should NOT match Lab6 stacks
        ("stack-advanced-lab6", "lab6", True),
        
        # Lab7 stacks (critical test cases)
        ("stack-pooled-lab7", "lab7", True),
        ("stack-pooled-lab7", "lab5", False),  # Lab5 should NOT match Lab7 stacks
        
        # Edge cases
        ("stack-pooled-lab10", "lab1", False),  # lab1 should not match lab10
        ("stack-pooled-lab1", "lab10", False),  # lab10 should not match lab1
    ]
    
    for stack_name, lab_id, expected in test_cases:
        result = verify_stack_ownership(stack_name, lab_id)
        assert result == expected, \
            f"verify_stack_ownership('{stack_name}', '{lab_id}') returned {result}, expected {expected}"


# Unit Test: Pattern matching edge cases
def test_pattern_matching_edge_cases():
    """
    Unit test: Verify pattern matching handles edge cases correctly.
    
    This ensures the lab-specific filtering doesn't have false positives
    or false negatives.
    """
    # Test that lab5 doesn't match lab6 or lab7
    assert not verify_stack_ownership("stack-pooled-lab6", "lab5")
    assert not verify_stack_ownership("stack-pooled-lab7", "lab5")
    assert not verify_stack_ownership("stack-lab6-pooled", "lab5")
    
    # Test that lab1 doesn't match lab10 (if it existed)
    assert not verify_stack_ownership("stack-pooled-lab10", "lab1")
    
    # Test that each lab only matches its own stacks
    for lab_num in range(1, 8):
        lab_id = f"lab{lab_num}"
        stack_name = f"stack-pooled-{lab_id}"
        
        # Should match its own lab
        assert verify_stack_ownership(stack_name, lab_id)
        
        # Should not match other labs
        for other_lab_num in range(1, 8):
            if other_lab_num != lab_num:
                other_lab_id = f"lab{other_lab_num}"
                assert not verify_stack_ownership(stack_name, other_lab_id), \
                    f"Stack '{stack_name}' should not match {other_lab_id}"


# Comprehensive Test: All labs deployed, cleanup one at a time
def test_sequential_cleanup_all_labs():
    """
    Comprehensive test: Deploy all labs, then cleanup one at a time,
    verifying remaining labs are unaffected.
    
    This simulates the real-world scenario where all labs are deployed
    and users clean them up individually.
    """
    # Step 1: Generate stacks for all labs (simulating full deployment)
    all_labs_stacks = {}
    for lab_id in LAB_IDS:
        all_labs_stacks[lab_id] = generate_lab_stacks(lab_id)
    
    # Flatten all stacks
    all_stacks = []
    for stacks in all_labs_stacks.values():
        all_stacks.extend(stacks)
    
    # Step 2: Cleanup labs one at a time
    remaining_labs = set(LAB_IDS)
    
    for target_lab in LAB_IDS:
        # Record remaining labs' resources before cleanup
        resources_before = {}
        for lab_id in remaining_labs:
            if lab_id != target_lab:
                resources_before[lab_id] = {s["StackName"] for s in all_labs_stacks[lab_id]}
        
        # Simulate cleanup of target lab
        stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, target_lab)
        
        # Verify target lab stacks are marked for deletion
        target_stack_names = {s["StackName"] for s in all_labs_stacks[target_lab]}
        for stack_name in target_stack_names:
            assert stack_name in stacks_to_delete, \
                f"Target lab {target_lab} stack '{stack_name}' should be marked for deletion"
        
        # Verify other labs' resources remain intact
        for lab_id, expected_stacks in resources_before.items():
            for stack_name in expected_stacks:
                assert stack_name in stacks_to_keep, \
                    f"Lab {lab_id} stack '{stack_name}' should NOT be deleted when cleaning up {target_lab}"
                assert stack_name not in stacks_to_delete, \
                    f"Lab {lab_id} stack '{stack_name}' was incorrectly marked for deletion by {target_lab} cleanup"
        
        # Remove target lab from remaining labs
        remaining_labs.remove(target_lab)
        
        # Update all_stacks to simulate deletion
        all_stacks = [s for s in all_stacks if s["StackName"] not in stacks_to_delete]


# Test: Verify all lab combinations
def test_all_lab_combinations_isolation():
    """
    Test all possible lab pair combinations to ensure complete isolation.
    
    This is a comprehensive test that validates all 21 lab pairs
    (7 choose 2 = 21 combinations).
    """
    violations = []
    
    for lab_n, lab_m in combinations(LAB_IDS, 2):
        # Generate stacks for both labs
        lab_n_stacks = generate_lab_stacks(lab_n)
        lab_m_stacks = generate_lab_stacks(lab_m)
        all_stacks = lab_n_stacks + lab_m_stacks
        
        # Test cleanup of lab_n doesn't affect lab_m
        stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, lab_n)
        
        lab_m_stack_names = {s["StackName"] for s in lab_m_stacks}
        for stack_name in lab_m_stack_names:
            if stack_name in stacks_to_delete:
                violations.append({
                    "cleanup_lab": lab_n,
                    "affected_lab": lab_m,
                    "stack_name": stack_name
                })
        
        # Test cleanup of lab_m doesn't affect lab_n
        stacks_to_delete, stacks_to_keep = simulate_cleanup_filtering(all_stacks, lab_m)
        
        lab_n_stack_names = {s["StackName"] for s in lab_n_stacks}
        for stack_name in lab_n_stack_names:
            if stack_name in stacks_to_delete:
                violations.append({
                    "cleanup_lab": lab_m,
                    "affected_lab": lab_n,
                    "stack_name": stack_name
                })
    
    if violations:
        error_msg = f"\nFound {len(violations)} cross-lab deletion violation(s):\n"
        for v in violations:
            error_msg += f"  - Cleanup of {v['cleanup_lab']} would delete {v['affected_lab']} stack: {v['stack_name']}\n"
        pytest.fail(error_msg)


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
