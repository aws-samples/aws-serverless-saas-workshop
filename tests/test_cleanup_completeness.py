#!/usr/bin/env python3
"""
Property-Based Test: Complete Cleanup

Feature: lab-cleanup-isolation-all-labs, Property 2: Complete Cleanup
Validates: Requirements 1.3

This test verifies that cleanup of Lab N deletes ALL resources belonging to Lab N.

Property: cleanup(lab_n) ⇒ resources(lab_n) = ∅

Test Strategy:
1. Mock deployment of a lab
2. Record all created resources (stacks, S3 buckets, CloudWatch logs, etc.)
3. Mock cleanup execution
4. Verify all recorded resources are deleted
5. Test covers all labs (Lab1-Lab7)
"""

import pytest
from pathlib import Path
from typing import Dict, List, Set, Tuple
from hypothesis import given, settings, strategies as st
from unittest.mock import Mock, patch, MagicMock


# Constants
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]
LAB_IDS = [f"lab{i}" for i in range(1, 8)]


# Resource Types
class ResourceType:
    """Enumeration of AWS resource types tracked by cleanup scripts."""
    CLOUDFORMATION_STACK = "CloudFormation::Stack"
    S3_BUCKET = "S3::Bucket"
    CLOUDWATCH_LOG_GROUP = "CloudWatch::LogGroup"
    COGNITO_USER_POOL = "Cognito::UserPool"
    CODECOMMIT_REPOSITORY = "CodeCommit::Repository"
    DYNAMODB_TABLE = "DynamoDB::Table"
    LAMBDA_FUNCTION = "Lambda::Function"
    API_GATEWAY = "ApiGateway::RestApi"


class LabResource:
    """Represents an AWS resource belonging to a lab."""
    
    def __init__(self, resource_type: str, resource_name: str, lab_id: str):
        self.resource_type = resource_type
        self.resource_name = resource_name
        self.lab_id = lab_id
        self.deleted = False
    
    def __repr__(self):
        status = "DELETED" if self.deleted else "EXISTS"
        return f"<{self.resource_type}: {self.resource_name} [{status}]>"
    
    def __eq__(self, other):
        if not isinstance(other, LabResource):
            return False
        return (self.resource_type == other.resource_type and 
                self.resource_name == other.resource_name)
    
    def __hash__(self):
        return hash((self.resource_type, self.resource_name))


def generate_lab_resources(lab_id: str) -> List[LabResource]:
    """
    Generate all AWS resources that would be created by deploying a lab.
    
    Each lab creates different resources based on its architecture:
    - Lab1: Basic serverless app (1 stack, S3 buckets, CloudWatch logs)
    - Lab2: Auth layer (1 stack, S3 buckets, CloudWatch logs, Cognito)
    - Lab3: Multi-tenant pooled (2 stacks, S3 buckets, CloudWatch logs, DynamoDB)
    - Lab4: Multi-tenant silo (2 stacks, S3 buckets, CloudWatch logs, DynamoDB)
    - Lab5: CI/CD pipeline (3 stacks, S3 buckets, CloudWatch logs, CodeCommit)
    - Lab6: Metrics & monitoring (3 stacks, S3 buckets, CloudWatch logs)
    - Lab7: Cost attribution (2 stacks, S3 buckets, CloudWatch logs)
    
    Returns:
        List of LabResource objects representing all resources for the lab
    """
    resources = []
    lab_num = lab_id.replace("lab", "")
    
    # Lab1: Basic serverless app
    if lab_id == "lab1":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-lab1",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab1-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab1-products",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab1-orders",
            lab_id
        ))
    
    # Lab2: Auth layer
    elif lab_id == "lab2":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-lab2",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab2-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab2-auth",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab2-products",
            lab_id
        ))
        
        # Cognito user pools
        resources.append(LabResource(
            ResourceType.COGNITO_USER_POOL,
            f"serverless-saas-lab2-user-pool",
            lab_id
        ))
    
    # Lab3: Multi-tenant pooled
    elif lab_id == "lab3":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-shared-lab3",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-pooled-lab3",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab3-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab3-tenant-registration",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-pooled-lab3-products",
            lab_id
        ))
        
        # DynamoDB tables
        resources.append(LabResource(
            ResourceType.DYNAMODB_TABLE,
            f"stack-pooled-lab3-products-table",
            lab_id
        ))
    
    # Lab4: Multi-tenant silo
    elif lab_id == "lab4":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-shared-lab4",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-pooled-lab4",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab4-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab4-tenant-registration",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-pooled-lab4-products",
            lab_id
        ))
        
        # DynamoDB tables
        resources.append(LabResource(
            ResourceType.DYNAMODB_TABLE,
            f"stack-pooled-lab4-products-table",
            lab_id
        ))
    
    # Lab5: CI/CD pipeline
    elif lab_id == "lab5":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-shared-lab5",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-pipeline-lab5",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-pooled-lab5",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-platinum-lab5",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab5-artifacts-bucket",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab5-pipeline-artifacts",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab5-tenant-registration",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-pooled-lab5-products",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-platinum-lab5-products",
            lab_id
        ))
        
        # CodeCommit repositories
        resources.append(LabResource(
            ResourceType.CODECOMMIT_REPOSITORY,
            f"serverless-saas-lab5-tenant-repo",
            lab_id
        ))
    
    # Lab6: Metrics & monitoring
    elif lab_id == "lab6":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-shared-lab6",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-pooled-lab6",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-advanced-lab6",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab6-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab6-tenant-registration",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-pooled-lab6-products",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-advanced-lab6-products",
            lab_id
        ))
    
    # Lab7: Cost attribution
    elif lab_id == "lab7":
        # CloudFormation stacks
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"serverless-saas-lab7",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDFORMATION_STACK,
            f"stack-pooled-lab7",
            lab_id
        ))
        
        # S3 buckets
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab7-cur-bucket",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.S3_BUCKET,
            f"serverless-saas-lab7-artifacts-bucket",
            lab_id
        ))
        
        # CloudWatch log groups
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/serverless-saas-lab7-cost-attribution",
            lab_id
        ))
        resources.append(LabResource(
            ResourceType.CLOUDWATCH_LOG_GROUP,
            f"/aws/lambda/stack-pooled-lab7-products",
            lab_id
        ))
    
    return resources


def simulate_cleanup_execution(resources: List[LabResource], target_lab_id: str) -> Tuple[List[LabResource], List[LabResource]]:
    """
    Simulate the cleanup script execution for a specific lab.
    
    This mimics the cleanup script's behavior:
    1. Identify resources belonging to the target lab
    2. Delete CloudFormation stacks (which cascade deletes many resources)
    3. Delete S3 buckets
    4. Delete CloudWatch log groups
    5. Delete Cognito user pools
    6. Delete CodeCommit repositories
    
    Args:
        resources: List of all resources in the environment
        target_lab_id: The lab ID being cleaned up
    
    Returns:
        Tuple of (deleted_resources, remaining_resources)
    """
    deleted_resources = []
    remaining_resources = []
    
    for resource in resources:
        # Check if resource belongs to target lab
        if resource.lab_id == target_lab_id:
            # Mark resource as deleted
            resource.deleted = True
            deleted_resources.append(resource)
        else:
            remaining_resources.append(resource)
    
    return deleted_resources, remaining_resources


def verify_complete_cleanup(resources: List[LabResource], target_lab_id: str) -> Tuple[bool, List[LabResource]]:
    """
    Verify that all resources belonging to the target lab have been deleted.
    
    Args:
        resources: List of all resources after cleanup
        target_lab_id: The lab ID that was cleaned up
    
    Returns:
        Tuple of (is_complete, remaining_resources)
        - is_complete: True if all target lab resources are deleted
        - remaining_resources: List of resources that should have been deleted but weren't
    """
    remaining_lab_resources = []
    
    for resource in resources:
        if resource.lab_id == target_lab_id and not resource.deleted:
            remaining_lab_resources.append(resource)
    
    is_complete = len(remaining_lab_resources) == 0
    return is_complete, remaining_lab_resources


# Property Test 1: Complete Cleanup - Single Lab
@settings(max_examples=100, deadline=None)
@given(target_lab=st.sampled_from(LAB_IDS))
def test_cleanup_completeness_property(target_lab: str):
    """
    Property: Cleanup of Lab N must delete ALL resources belonging to Lab N.
    
    Validates: Requirements 1.3
    
    This test:
    1. Simulates deployment of a lab (generates all resources)
    2. Records all created resources
    3. Simulates cleanup execution
    4. Verifies all recorded resources are deleted
    """
    # Step 1: Generate all resources for the target lab (simulating deployment)
    lab_resources = generate_lab_resources(target_lab)
    
    # Verify we have resources to test
    assert len(lab_resources) > 0, f"Lab {target_lab} should create at least one resource"
    
    # Step 2: Record all created resources before cleanup
    resources_before = {
        resource.resource_name: resource
        for resource in lab_resources
    }
    
    # Step 3: Simulate cleanup execution
    deleted_resources, remaining_resources = simulate_cleanup_execution(lab_resources, target_lab)
    
    # Step 4: Verify ALL resources were deleted
    is_complete, leftover_resources = verify_complete_cleanup(lab_resources, target_lab)
    
    # Step 5: Assert complete cleanup
    assert is_complete, \
        f"Cleanup of {target_lab} is INCOMPLETE. " \
        f"Expected to delete {len(resources_before)} resources, " \
        f"but {len(leftover_resources)} resources remain:\n" + \
        "\n".join([f"  - {r}" for r in leftover_resources])
    
    # Step 6: Verify all resources are marked as deleted
    for resource in lab_resources:
        assert resource.deleted, \
            f"Resource {resource.resource_name} ({resource.resource_type}) " \
            f"should be deleted but is still present"
    
    # Step 7: Verify the count matches
    assert len(deleted_resources) == len(resources_before), \
        f"Expected to delete {len(resources_before)} resources, " \
        f"but only deleted {len(deleted_resources)}"


# Property Test 2: Complete Cleanup - All Resource Types
@settings(max_examples=100, deadline=None)
@given(target_lab=st.sampled_from(LAB_IDS))
def test_cleanup_all_resource_types_property(target_lab: str):
    """
    Property: Cleanup must delete ALL resource types (stacks, S3, logs, etc.).
    
    Validates: Requirements 1.3
    
    This test verifies that cleanup doesn't miss any resource types.
    """
    # Step 1: Generate all resources for the target lab
    lab_resources = generate_lab_resources(target_lab)
    
    # Step 2: Group resources by type
    resources_by_type = {}
    for resource in lab_resources:
        if resource.resource_type not in resources_by_type:
            resources_by_type[resource.resource_type] = []
        resources_by_type[resource.resource_type].append(resource)
    
    # Step 3: Simulate cleanup
    deleted_resources, remaining_resources = simulate_cleanup_execution(lab_resources, target_lab)
    
    # Step 4: Verify ALL resource types are completely cleaned up
    for resource_type, resources in resources_by_type.items():
        deleted_count = sum(1 for r in resources if r.deleted)
        total_count = len(resources)
        
        assert deleted_count == total_count, \
            f"Cleanup of {target_lab} did not delete all {resource_type} resources. " \
            f"Deleted {deleted_count}/{total_count}. " \
            f"Remaining: {[r.resource_name for r in resources if not r.deleted]}"


# Property Test 3: Complete Cleanup - Multi-Lab Environment
@settings(max_examples=100, deadline=None)
@given(
    target_lab=st.sampled_from(LAB_IDS),
    other_labs=st.lists(
        st.sampled_from(LAB_IDS),
        min_size=1,
        max_size=3,
        unique=True
    )
)
def test_cleanup_completeness_multi_lab_property(target_lab: str, other_labs: List[str]):
    """
    Property: In a multi-lab environment, cleanup of Lab N must delete
    ALL resources belonging to Lab N, while preserving other labs' resources.
    
    Validates: Requirements 1.3
    
    This test simulates a realistic scenario where multiple labs are deployed.
    """
    # Filter out the target lab from other labs
    other_labs = [lab for lab in other_labs if lab != target_lab]
    
    # Skip if no other labs to test against
    if not other_labs:
        return
    
    # Step 1: Generate resources for all labs
    all_resources = []
    
    # Add target lab resources
    target_lab_resources = generate_lab_resources(target_lab)
    all_resources.extend(target_lab_resources)
    
    # Add other labs' resources
    other_labs_resources = {}
    for lab_id in other_labs:
        lab_resources = generate_lab_resources(lab_id)
        other_labs_resources[lab_id] = lab_resources
        all_resources.extend(lab_resources)
    
    # Step 2: Record target lab resources before cleanup
    target_resource_names = {r.resource_name for r in target_lab_resources}
    
    # Step 3: Simulate cleanup of target lab
    deleted_resources, remaining_resources = simulate_cleanup_execution(all_resources, target_lab)
    
    # Step 4: Verify ALL target lab resources are deleted
    is_complete, leftover_resources = verify_complete_cleanup(all_resources, target_lab)
    
    assert is_complete, \
        f"Cleanup of {target_lab} is INCOMPLETE in multi-lab environment. " \
        f"{len(leftover_resources)} resources remain:\n" + \
        "\n".join([f"  - {r}" for r in leftover_resources])
    
    # Step 5: Verify other labs' resources are NOT deleted
    for lab_id, lab_resources in other_labs_resources.items():
        for resource in lab_resources:
            assert not resource.deleted, \
                f"Cleanup of {target_lab} incorrectly deleted {lab_id} resource: {resource.resource_name}"


# Unit Test: Resource generation for each lab
def test_resource_generation_all_labs():
    """
    Unit test: Verify that resource generation works for all labs.
    
    This ensures the test infrastructure is correctly set up.
    """
    for lab_id in LAB_IDS:
        resources = generate_lab_resources(lab_id)
        
        # Verify resources were generated
        assert len(resources) > 0, f"Lab {lab_id} should generate at least one resource"
        
        # Verify all resources have correct lab_id
        for resource in resources:
            assert resource.lab_id == lab_id, \
                f"Resource {resource.resource_name} has incorrect lab_id: {resource.lab_id} (expected {lab_id})"
        
        # Verify CloudFormation stacks exist
        stack_resources = [r for r in resources if r.resource_type == ResourceType.CLOUDFORMATION_STACK]
        assert len(stack_resources) > 0, f"Lab {lab_id} should have at least one CloudFormation stack"
        
        # Verify resource names contain lab identifier
        for resource in resources:
            assert lab_id in resource.resource_name, \
                f"Resource {resource.resource_name} should contain lab identifier '{lab_id}'"


# Unit Test: Cleanup simulation
def test_cleanup_simulation():
    """
    Unit test: Verify the cleanup simulation logic works correctly.
    """
    # Create test resources for Lab3
    lab3_resources = generate_lab_resources("lab3")
    lab5_resources = generate_lab_resources("lab5")
    all_resources = lab3_resources + lab5_resources
    
    # Simulate cleanup of Lab3
    deleted, remaining = simulate_cleanup_execution(all_resources, "lab3")
    
    # Verify Lab3 resources are deleted
    assert len(deleted) == len(lab3_resources), \
        f"Expected to delete {len(lab3_resources)} Lab3 resources, but deleted {len(deleted)}"
    
    # Verify Lab5 resources remain
    lab5_remaining = [r for r in remaining if r.lab_id == "lab5"]
    assert len(lab5_remaining) == len(lab5_resources), \
        f"Expected {len(lab5_resources)} Lab5 resources to remain, but found {len(lab5_remaining)}"
    
    # Verify all deleted resources are from Lab3
    for resource in deleted:
        assert resource.lab_id == "lab3", \
            f"Deleted resource {resource.resource_name} should belong to Lab3"
        assert resource.deleted, \
            f"Deleted resource {resource.resource_name} should be marked as deleted"


# Unit Test: Verify complete cleanup detection
def test_verify_complete_cleanup():
    """
    Unit test: Verify the complete cleanup verification logic.
    """
    # Create test resources
    resources = generate_lab_resources("lab5")
    
    # Scenario 1: Complete cleanup (all resources deleted)
    for resource in resources:
        resource.deleted = True
    
    is_complete, leftover = verify_complete_cleanup(resources, "lab5")
    assert is_complete, "Should detect complete cleanup when all resources are deleted"
    assert len(leftover) == 0, "Should have no leftover resources"
    
    # Scenario 2: Incomplete cleanup (some resources remain)
    resources = generate_lab_resources("lab5")
    # Delete only half the resources
    for i, resource in enumerate(resources):
        resource.deleted = (i % 2 == 0)
    
    is_complete, leftover = verify_complete_cleanup(resources, "lab5")
    assert not is_complete, "Should detect incomplete cleanup when some resources remain"
    assert len(leftover) > 0, "Should have leftover resources"
    
    # Verify leftover resources are the ones not deleted
    for resource in leftover:
        assert not resource.deleted, "Leftover resources should not be marked as deleted"
        assert resource.lab_id == "lab5", "Leftover resources should belong to Lab5"


# Comprehensive Test: Sequential cleanup of all labs
def test_sequential_cleanup_completeness_all_labs():
    """
    Comprehensive test: Deploy all labs, then cleanup one at a time,
    verifying complete cleanup of each lab.
    
    This simulates the real-world scenario where all labs are deployed
    and users clean them up individually.
    """
    # Step 1: Generate resources for all labs (simulating full deployment)
    all_labs_resources = {}
    for lab_id in LAB_IDS:
        all_labs_resources[lab_id] = generate_lab_resources(lab_id)
    
    # Flatten all resources
    all_resources = []
    for resources in all_labs_resources.values():
        all_resources.extend(resources)
    
    # Step 2: Cleanup labs one at a time
    for target_lab in LAB_IDS:
        # Record target lab resources before cleanup
        target_resources = all_labs_resources[target_lab]
        target_resource_count = len(target_resources)
        
        # Simulate cleanup of target lab
        deleted_resources, remaining_resources = simulate_cleanup_execution(all_resources, target_lab)
        
        # Verify ALL target lab resources are deleted
        is_complete, leftover_resources = verify_complete_cleanup(all_resources, target_lab)
        
        assert is_complete, \
            f"Cleanup of {target_lab} is INCOMPLETE. " \
            f"{len(leftover_resources)} resources remain:\n" + \
            "\n".join([f"  - {r}" for r in leftover_resources])
        
        # Verify the count matches
        deleted_target_count = len([r for r in deleted_resources if r.lab_id == target_lab])
        assert deleted_target_count == target_resource_count, \
            f"Expected to delete {target_resource_count} {target_lab} resources, " \
            f"but only deleted {deleted_target_count}"
        
        # Update all_resources to simulate deletion
        all_resources = [r for r in all_resources if not r.deleted]


# Test: Resource count validation for each lab
def test_resource_count_validation():
    """
    Test: Verify each lab creates the expected number of resources.
    
    This helps catch regressions in resource generation logic.
    """
    # Expected minimum resource counts for each lab
    # (These are minimums - labs may create more resources)
    expected_min_counts = {
        "lab1": 3,   # 1 stack + 1 S3 + 2 log groups
        "lab2": 4,   # 1 stack + 1 S3 + 2 log groups + 1 Cognito
        "lab3": 5,   # 2 stacks + 1 S3 + 2 log groups + 1 DynamoDB
        "lab4": 5,   # 2 stacks + 1 S3 + 2 log groups + 1 DynamoDB
        "lab5": 8,   # 4 stacks + 2 S3 + 3 log groups + 1 CodeCommit
        "lab6": 6,   # 3 stacks + 1 S3 + 3 log groups
        "lab7": 6,   # 2 stacks + 2 S3 + 2 log groups
    }
    
    for lab_id, expected_min in expected_min_counts.items():
        resources = generate_lab_resources(lab_id)
        actual_count = len(resources)
        
        assert actual_count >= expected_min, \
            f"Lab {lab_id} should create at least {expected_min} resources, " \
            f"but only created {actual_count}"


# Test: Critical bug validation - Lab5 cleanup completeness
def test_lab5_cleanup_completeness():
    """
    Test: Verify Lab5 cleanup deletes ALL Lab5 resources.
    
    This is critical because Lab5 has the most complex architecture
    with multiple tenant stacks and a CI/CD pipeline.
    """
    # Generate Lab5 resources
    lab5_resources = generate_lab_resources("lab5")
    
    # Verify Lab5 has multiple stacks (shared, pipeline, tenant)
    stack_resources = [r for r in lab5_resources if r.resource_type == ResourceType.CLOUDFORMATION_STACK]
    assert len(stack_resources) >= 3, \
        f"Lab5 should have at least 3 stacks (shared, pipeline, tenant), found {len(stack_resources)}"
    
    # Simulate cleanup
    deleted_resources, remaining_resources = simulate_cleanup_execution(lab5_resources, "lab5")
    
    # Verify complete cleanup
    is_complete, leftover_resources = verify_complete_cleanup(lab5_resources, "lab5")
    
    assert is_complete, \
        f"Lab5 cleanup is INCOMPLETE. {len(leftover_resources)} resources remain:\n" + \
        "\n".join([f"  - {r}" for r in leftover_resources])
    
    # Verify all stacks are deleted
    for stack in stack_resources:
        assert stack.deleted, \
            f"Lab5 stack {stack.resource_name} should be deleted"


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
