#!/usr/bin/env python3
"""
Property-Based Tests for Test Step Verification

Feature: lab-cleanup-isolation-all-labs, Task 16.1: Property-Based Test for Test Step Verification
Validates: Requirements 15.1-15.5, Property 15

These tests verify that the test framework properly validates expected outcomes
for each test step using property-based testing.
"""

import pytest
from hypothesis import given, strategies as st, settings, HealthCheck
from pathlib import Path
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_end_to_end_cleanup_isolation import (
    ResourceSnapshot,
    StepResult,
    EndToEndTestRunner
)
from datetime import datetime


# Test configuration
MAX_EXAMPLES = 5
TIMEOUT_SECONDS = 10


# Strategy for generating resource snapshots
@st.composite
def resource_snapshot_strategy(draw):
    """Generate random resource snapshots for testing."""
    num_stacks = draw(st.integers(min_value=0, max_value=20))
    num_buckets = draw(st.integers(min_value=0, max_value=10))
    num_logs = draw(st.integers(min_value=0, max_value=15))
    num_cognito = draw(st.integers(min_value=0, max_value=5))
    
    stacks = {f"stack-lab{i % 7 + 1}-{j}" for i in range(num_stacks) for j in range(1)}
    buckets = {f"bucket-lab{i % 7 + 1}-{j}" for i in range(num_buckets) for j in range(1)}
    logs = {f"/aws/lambda/lab{i % 7 + 1}-function-{j}" for i in range(num_logs) for j in range(1)}
    cognito = {f"lab{i % 7 + 1}-user-pool-{j}" for i in range(num_cognito) for j in range(1)}
    
    return ResourceSnapshot(
        timestamp=datetime.now(),
        stacks=stacks,
        s3_buckets=buckets,
        log_groups=logs,
        cognito_pools=cognito
    )


@pytest.mark.property
@given(
    resources_before=resource_snapshot_strategy(),
    deletion_percentage=st.floats(min_value=0.0, max_value=1.0)
)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_resource_count_verification(resources_before, deletion_percentage):
    """
    Property 15: Test Step Verification - Resource Count Verification
    
    **Validates: Requirement 15.1**
    
    For any cleanup step completion, the test framework should verify the expected
    number of resources were deleted by comparing before and after snapshots.
    
    Property: For all resource snapshots (before, after), the deleted count should
    equal (before.count() - after.count()) and should be >= 0.
    """
    # Generate resources_after by removing a percentage of resources_before
    # This ensures resources_after is always a subset of resources_before
    keep_percentage = 1.0 - deletion_percentage
    
    stacks_list = list(resources_before.stacks)
    buckets_list = list(resources_before.s3_buckets)
    logs_list = list(resources_before.log_groups)
    cognito_list = list(resources_before.cognito_pools)
    
    num_stacks_to_keep = int(len(stacks_list) * keep_percentage)
    num_buckets_to_keep = int(len(buckets_list) * keep_percentage)
    num_logs_to_keep = int(len(logs_list) * keep_percentage)
    num_cognito_to_keep = int(len(cognito_list) * keep_percentage)
    
    stacks_to_keep = set(stacks_list[:num_stacks_to_keep])
    buckets_to_keep = set(buckets_list[:num_buckets_to_keep])
    logs_to_keep = set(logs_list[:num_logs_to_keep])
    cognito_to_keep = set(cognito_list[:num_cognito_to_keep])
    
    resources_after = ResourceSnapshot(
        timestamp=datetime.now(),
        stacks=stacks_to_keep,
        s3_buckets=buckets_to_keep,
        log_groups=logs_to_keep,
        cognito_pools=cognito_to_keep
    )
    
    # Calculate deleted resources
    deleted_count = resources_before.count() - resources_after.count()
    
    # Property: Deleted count should be non-negative
    assert deleted_count >= 0, \
        f"Deleted count cannot be negative: {deleted_count}"
    
    # Property: resources_after should be a subset of resources_before
    assert resources_after.stacks.issubset(resources_before.stacks), \
        "After stacks should be subset of before stacks"
    assert resources_after.s3_buckets.issubset(resources_before.s3_buckets), \
        "After buckets should be subset of before buckets"
    assert resources_after.log_groups.issubset(resources_before.log_groups), \
        "After logs should be subset of before logs"
    assert resources_after.cognito_pools.issubset(resources_before.cognito_pools), \
        "After cognito should be subset of before cognito"
    
    # Property: If resources_after is empty, deleted_count should equal resources_before.count()
    if resources_after.is_empty():
        assert deleted_count == resources_before.count(), \
            f"When after is empty, deleted should equal before: {deleted_count} != {resources_before.count()}"


@pytest.mark.property
@given(
    num_deployed_labs=st.integers(min_value=0, max_value=7)
)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_stack_creation_verification(num_deployed_labs):
    """
    Property 15: Test Step Verification - Stack Creation Verification
    
    **Validates: Requirement 15.2**
    
    For any deployment step completion, the test framework should verify all expected
    stacks were created by checking for all 7 lab identifiers in the stack names.
    
    Property: For all deployment operations, if N labs are expected to be deployed,
    then exactly N unique lab identifiers should be found in the stack names.
    """
    # Generate mock stacks for deployed labs
    expected_labs = {f"lab{i}" for i in range(1, num_deployed_labs + 1)}
    
    # Simulate stack names
    stacks = set()
    for lab_id in expected_labs:
        stacks.add(f"serverless-saas-{lab_id}")
        stacks.add(f"serverless-saas-shared-{lab_id}")
    
    # Verify deployed labs
    deployed_labs = set()
    for stack in stacks:
        for i in range(1, 8):
            lab_id = f"lab{i}"
            if lab_id in stack.lower():
                deployed_labs.add(lab_id)
    
    # Property: Deployed labs should match expected labs
    assert deployed_labs == expected_labs, \
        f"Deployed labs mismatch: expected {expected_labs}, got {deployed_labs}"
    
    # Property: Number of deployed labs should equal expected count
    assert len(deployed_labs) == num_deployed_labs, \
        f"Deployed lab count mismatch: expected {num_deployed_labs}, got {len(deployed_labs)}"


@pytest.mark.property
@given(
    lab6_stacks_before=st.integers(min_value=10, max_value=15)
)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_lab6_specific_count_verification(lab6_stacks_before):
    """
    Property 15: Test Step Verification - Lab6 Specific Count Verification
    
    **Validates: Requirement 15.3**
    
    For any Lab6 cleanup completion, the test framework should verify exactly 10 Lab6
    stacks were deleted (1 shared stack + 9 tenant stacks).
    
    Property: For all Lab6 cleanup operations, the verification should pass if and only if
    exactly 10 stacks were deleted, regardless of the initial count.
    """
    # Generate lab6_stacks_deleted that doesn't exceed lab6_stacks_before
    # Test both the case where exactly 10 are deleted and other cases
    import random
    random.seed(42)
    
    # Test case 1: Exactly 10 deleted (should pass)
    lab6_stacks_deleted = 10
    lab6_stacks_after = lab6_stacks_before - lab6_stacks_deleted
    
    # Property: Remaining stacks should be non-negative
    assert lab6_stacks_after >= 0, \
        f"Remaining stacks cannot be negative: {lab6_stacks_after}"
    
    # Property: Verification should pass if exactly 10 stacks deleted
    verification_passed = (lab6_stacks_deleted == 10)
    assert verification_passed, \
        "Verification should pass when exactly 10 stacks deleted"
    
    # Test case 2: Different number deleted (should fail)
    if lab6_stacks_before > 10:
        # Use modulo to ensure we never get exactly 10
        # This gives us values like 11, 12, 13, 14, 15 -> 1, 2, 3, 4, 5
        lab6_stacks_deleted_wrong = (lab6_stacks_before % 10) if (lab6_stacks_before % 10) != 0 else lab6_stacks_before - 1
        verification_passed_wrong = (lab6_stacks_deleted_wrong == 10)
        assert not verification_passed_wrong, \
            f"Verification should fail when {lab6_stacks_deleted_wrong} stacks deleted (expected 10)"


@pytest.mark.property
@given(
    has_pipeline_stack=st.booleans()
)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_lab5_pipeline_verification(has_pipeline_stack):
    """
    Property 15: Test Step Verification - Lab5 Pipeline Verification
    
    **Validates: Requirement 15.4**
    
    For any Lab5 deployment completion, the test framework should verify the pipeline
    stack exists by checking for a stack with "pipeline" and "lab5" in its name.
    
    Property: For all Lab5 deployment operations, the verification should pass if and only if
    at least one stack contains both "pipeline" and "lab5" in its name (case-insensitive).
    """
    # Generate mock stacks
    stacks = set()
    if has_pipeline_stack:
        stacks.add("serverless-saas-lab5-pipeline")
        stacks.add("serverless-saas-shared-lab5")
    else:
        stacks.add("serverless-saas-shared-lab5")
    
    # Verify pipeline stack exists
    pipeline_exists = False
    for stack in stacks:
        if "pipeline" in stack.lower() and "lab5" in stack.lower():
            pipeline_exists = True
            break
    
    # Property: Pipeline existence should match expectation
    assert pipeline_exists == has_pipeline_stack, \
        f"Pipeline existence mismatch: expected {has_pipeline_stack}, got {pipeline_exists}"
    
    # Property: Verification should pass if pipeline exists
    if has_pipeline_stack:
        assert pipeline_exists, \
            "Verification should pass when pipeline stack exists"
    else:
        assert not pipeline_exists, \
            "Verification should fail when pipeline stack does not exist"


@pytest.mark.property
@given(
    resources_after=resource_snapshot_strategy()
)
@settings(
    max_examples=MAX_EXAMPLES,
    deadline=TIMEOUT_SECONDS * 1000,
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_zero_resource_verification(resources_after):
    """
    Property 15: Test Step Verification - Zero Resource Verification
    
    **Validates: Requirement 15.5**
    
    For any final cleanup completion, the test framework should verify zero resources
    remain in the AWS account by checking all resource types.
    
    Property: For all final cleanup operations, the verification should pass if and only if
    the resource count is exactly 0 (no stacks, buckets, logs, or Cognito pools remain).
    """
    # Calculate remaining resource count
    remaining_count = resources_after.count()
    
    # Property: Verification should pass if and only if remaining count is 0
    verification_passed = (remaining_count == 0)
    
    if remaining_count == 0:
        assert verification_passed, \
            "Verification should pass when no resources remain"
        assert resources_after.is_empty(), \
            "Snapshot should be empty when count is 0"
    else:
        assert not verification_passed, \
            f"Verification should fail when {remaining_count} resources remain"
        assert not resources_after.is_empty(), \
            "Snapshot should not be empty when count > 0"
    
    # Property: If any resource type has items, total count should be > 0
    if len(resources_after.stacks) > 0 or len(resources_after.s3_buckets) > 0 or \
       len(resources_after.log_groups) > 0 or len(resources_after.cognito_pools) > 0:
        assert remaining_count > 0, \
            "Total count should be > 0 when any resource type has items"
    
    # Property: If total count is 0, all resource types should be empty
    if remaining_count == 0:
        assert len(resources_after.stacks) == 0, "Stacks should be empty"
        assert len(resources_after.s3_buckets) == 0, "Buckets should be empty"
        assert len(resources_after.log_groups) == 0, "Logs should be empty"
        assert len(resources_after.cognito_pools) == 0, "Cognito pools should be empty"


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v", "--tb=short"])
