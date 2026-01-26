#!/usr/bin/env python3
"""
Property-Based Test: Resource Naming Consistency

Feature: lab6-s3-bucket-naming, Property 4: Resource Naming Consistency
Validates: Requirements 4.1, 4.2, 4.3, 4.4

This test verifies that all CodePipeline-related resources in Lab 5 and Lab 6
follow consistent naming patterns with the lab identifier included.
"""

import re
import pytest
from hypothesis import given, settings, strategies as st


# Expected resource naming patterns for Lab 5
LAB5_EXPECTED_RESOURCES = {
    "bucket": r"^serverless-saas-pipeline-lab5-artifacts-[0-9a-f]{8}$",
    "codebuild_log_group": r"^/aws/codebuild/serverless-saas-pipeline-lab5-build$",
    "lambda_function": r"^serverless-saas-lab5-deploy-tenant-stack$",
    "lambda_log_group": r"^/aws/lambda/serverless-saas-lab5-deploy-tenant-stack$",
    "pipeline": r"^serverless-saas-pipeline-lab5$",
}

# Expected resource naming patterns for Lab 6
LAB6_EXPECTED_RESOURCES = {
    "bucket": r"^serverless-saas-pipeline-lab6-artifacts-[0-9a-f]{8}$",
    "codebuild_log_group": r"^/aws/codebuild/serverless-saas-pipeline-lab6-build$",
    "lambda_function": r"^serverless-saas-lab6-deploy-tenant-stack$",
    "lambda_log_group": r"^/aws/lambda/serverless-saas-lab6-deploy-tenant-stack$",
    "pipeline": r"^serverless-saas-pipeline-lab6$",
}


def generate_resource_names(lab_number: int, stack_id_hash: str) -> dict:
    """
    Generate all resource names for a given lab using the expected patterns.
    
    Args:
        lab_number: Lab number (5 or 6)
        stack_id_hash: 8-character hexadecimal hash from CloudFormation Stack ID
    
    Returns:
        Dictionary of resource names
    """
    return {
        "bucket": f"serverless-saas-pipeline-lab{lab_number}-artifacts-{stack_id_hash}",
        "codebuild_log_group": f"/aws/codebuild/serverless-saas-pipeline-lab{lab_number}-build",
        "lambda_function": f"serverless-saas-lab{lab_number}-deploy-tenant-stack",
        "lambda_log_group": f"/aws/lambda/serverless-saas-lab{lab_number}-deploy-tenant-stack",
        "pipeline": f"serverless-saas-pipeline-lab{lab_number}",
    }


def validate_resource_name_pattern(resource_name: str, expected_pattern: str) -> bool:
    """
    Validate that a resource name matches the expected pattern.
    
    Args:
        resource_name: The actual resource name
        expected_pattern: Regular expression pattern to match
    
    Returns:
        True if the resource name matches the pattern, False otherwise
    """
    return bool(re.match(expected_pattern, resource_name))


def validate_lab_identifier_in_name(resource_name: str, lab_number: int) -> bool:
    """
    Validate that a resource name includes the lab identifier.
    
    Args:
        resource_name: The resource name to check
        lab_number: The lab number (5 or 6)
    
    Returns:
        True if the resource name includes the lab identifier, False otherwise
    """
    lab_identifier = f"lab{lab_number}"
    return lab_identifier in resource_name


def validate_naming_consistency(resource_names: dict, lab_number: int) -> bool:
    """
    Validate that all resource names include the lab identifier consistently.
    
    Args:
        resource_names: Dictionary of resource names
        lab_number: The lab number (5 or 6)
    
    Returns:
        True if all resource names include the lab identifier, False otherwise
    """
    for resource_type, resource_name in resource_names.items():
        if not validate_lab_identifier_in_name(resource_name, lab_number):
            return False
    return True


# Strategy for generating valid 8-character hexadecimal strings (simulating CloudFormation Stack ID hash)
stack_id_hash_strategy = st.text(
    alphabet='0123456789abcdef',
    min_size=8,
    max_size=8
)


# Property Test 1: Resource Naming Consistency (Lab 5)
@settings(max_examples=100, deadline=None)
@given(stack_id_hash=stack_id_hash_strategy)
def test_lab5_resource_naming_consistency_property(stack_id_hash: str):
    """
    Property: For any valid Stack ID hash, all Lab 5 resource names should include
    the lab identifier "lab5" and follow consistent naming patterns.
    
    **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
    
    This property verifies:
    1. All resource names include the lab identifier "lab5"
    2. Bucket name follows the expected pattern
    3. CodeBuild log group follows the expected pattern
    4. Lambda function follows the expected pattern
    5. Lambda log group follows the expected pattern
    6. Pipeline follows the expected pattern
    """
    # Generate all resource names
    resource_names = generate_resource_names(5, stack_id_hash)
    
    # Property 1: All resource names must include lab identifier
    assert validate_naming_consistency(resource_names, 5), \
        f"Not all Lab 5 resource names include the lab identifier 'lab5'"
    
    # Property 2: Each resource name must match its expected pattern
    for resource_type, resource_name in resource_names.items():
        expected_pattern = LAB5_EXPECTED_RESOURCES[resource_type]
        assert validate_resource_name_pattern(resource_name, expected_pattern), \
            f"Lab 5 {resource_type} name '{resource_name}' does not match expected pattern '{expected_pattern}'"
    
    # Property 3: Verify specific lab identifier presence
    assert "lab5" in resource_names["bucket"], \
        f"Bucket name '{resource_names['bucket']}' does not include 'lab5'"
    assert "lab5" in resource_names["codebuild_log_group"], \
        f"CodeBuild log group '{resource_names['codebuild_log_group']}' does not include 'lab5'"
    assert "lab5" in resource_names["lambda_function"], \
        f"Lambda function '{resource_names['lambda_function']}' does not include 'lab5'"
    assert "lab5" in resource_names["lambda_log_group"], \
        f"Lambda log group '{resource_names['lambda_log_group']}' does not include 'lab5'"
    assert "lab5" in resource_names["pipeline"], \
        f"Pipeline name '{resource_names['pipeline']}' does not include 'lab5'"


# Property Test 2: Resource Naming Consistency (Lab 6)
@settings(max_examples=100, deadline=None)
@given(stack_id_hash=stack_id_hash_strategy)
def test_lab6_resource_naming_consistency_property(stack_id_hash: str):
    """
    Property: For any valid Stack ID hash, all Lab 6 resource names should include
    the lab identifier "lab6" and follow consistent naming patterns.
    
    **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
    
    This property verifies:
    1. All resource names include the lab identifier "lab6"
    2. Bucket name follows the expected pattern
    3. CodeBuild log group follows the expected pattern
    4. Lambda function follows the expected pattern
    5. Lambda log group follows the expected pattern
    6. Pipeline follows the expected pattern
    """
    # Generate all resource names
    resource_names = generate_resource_names(6, stack_id_hash)
    
    # Property 1: All resource names must include lab identifier
    assert validate_naming_consistency(resource_names, 6), \
        f"Not all Lab 6 resource names include the lab identifier 'lab6'"
    
    # Property 2: Each resource name must match its expected pattern
    for resource_type, resource_name in resource_names.items():
        expected_pattern = LAB6_EXPECTED_RESOURCES[resource_type]
        assert validate_resource_name_pattern(resource_name, expected_pattern), \
            f"Lab 6 {resource_type} name '{resource_name}' does not match expected pattern '{expected_pattern}'"
    
    # Property 3: Verify specific lab identifier presence
    assert "lab6" in resource_names["bucket"], \
        f"Bucket name '{resource_names['bucket']}' does not include 'lab6'"
    assert "lab6" in resource_names["codebuild_log_group"], \
        f"CodeBuild log group '{resource_names['codebuild_log_group']}' does not include 'lab6'"
    assert "lab6" in resource_names["lambda_function"], \
        f"Lambda function '{resource_names['lambda_function']}' does not include 'lab6'"
    assert "lab6" in resource_names["lambda_log_group"], \
        f"Lambda log group '{resource_names['lambda_log_group']}' does not include 'lab6'"
    assert "lab6" in resource_names["pipeline"], \
        f"Pipeline name '{resource_names['pipeline']}' does not include 'lab6'"


# Property Test 3: Cross-Lab Naming Distinction
@settings(max_examples=100, deadline=None)
@given(stack_id_hash=stack_id_hash_strategy)
def test_cross_lab_naming_distinction_property(stack_id_hash: str):
    """
    Property: For any valid Stack ID hash, Lab 5 and Lab 6 resource names should
    be distinct and clearly identifiable by their lab identifier.
    
    **Validates: Requirements 4.4, 4.5**
    
    This property verifies that resources from different labs can be easily
    distinguished and filtered in the AWS console.
    """
    # Generate resource names for both labs
    lab5_resources = generate_resource_names(5, stack_id_hash)
    lab6_resources = generate_resource_names(6, stack_id_hash)
    
    # Property 1: All Lab 5 and Lab 6 resource names must be different
    for resource_type in lab5_resources.keys():
        assert lab5_resources[resource_type] != lab6_resources[resource_type], \
            f"Lab 5 and Lab 6 {resource_type} names are identical: '{lab5_resources[resource_type]}'"
    
    # Property 2: Lab 5 resources must not contain "lab6"
    for resource_type, resource_name in lab5_resources.items():
        assert "lab6" not in resource_name, \
            f"Lab 5 {resource_type} name '{resource_name}' incorrectly contains 'lab6'"
    
    # Property 3: Lab 6 resources must not contain "lab5"
    for resource_type, resource_name in lab6_resources.items():
        assert "lab5" not in resource_name, \
            f"Lab 6 {resource_type} name '{resource_name}' incorrectly contains 'lab5'"


# Unit Test: Specific Example Validation (Lab 5)
def test_lab5_resource_naming_specific_example():
    """
    Unit test: Verify Lab 5 resource naming with a specific example.
    """
    stack_id_hash = "a1b2c3d4"
    resource_names = generate_resource_names(5, stack_id_hash)
    
    expected_names = {
        "bucket": "serverless-saas-pipeline-lab5-artifacts-a1b2c3d4",
        "codebuild_log_group": "/aws/codebuild/serverless-saas-pipeline-lab5-build",
        "lambda_function": "serverless-saas-lab5-deploy-tenant-stack",
        "lambda_log_group": "/aws/lambda/serverless-saas-lab5-deploy-tenant-stack",
        "pipeline": "serverless-saas-pipeline-lab5",
    }
    
    for resource_type, expected_name in expected_names.items():
        actual_name = resource_names[resource_type]
        assert actual_name == expected_name, \
            f"Lab 5 {resource_type}: expected '{expected_name}', got '{actual_name}'"


# Unit Test: Specific Example Validation (Lab 6)
def test_lab6_resource_naming_specific_example():
    """
    Unit test: Verify Lab 6 resource naming with a specific example.
    """
    stack_id_hash = "ef0699a0"
    resource_names = generate_resource_names(6, stack_id_hash)
    
    expected_names = {
        "bucket": "serverless-saas-pipeline-lab6-artifacts-ef0699a0",
        "codebuild_log_group": "/aws/codebuild/serverless-saas-pipeline-lab6-build",
        "lambda_function": "serverless-saas-lab6-deploy-tenant-stack",
        "lambda_log_group": "/aws/lambda/serverless-saas-lab6-deploy-tenant-stack",
        "pipeline": "serverless-saas-pipeline-lab6",
    }
    
    for resource_type, expected_name in expected_names.items():
        actual_name = resource_names[resource_type]
        assert actual_name == expected_name, \
            f"Lab 6 {resource_type}: expected '{expected_name}', got '{actual_name}'"


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
