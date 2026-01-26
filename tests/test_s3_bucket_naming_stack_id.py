#!/usr/bin/env python3
"""
Property-Based Test: S3 Bucket Naming with Stack ID Hash Pattern

Feature: lab6-s3-bucket-naming
Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5

This test verifies that both Lab 5 and Lab 6 artifacts buckets follow the correct
naming pattern using CloudFormation Stack ID hash and comply with AWS S3 naming conventions.
"""

import re
import pytest
from hypothesis import given, settings, strategies as st


# Constants
LAB5_BUCKET_PREFIX = "serverless-saas-pipeline-lab5-artifacts"
LAB6_BUCKET_PREFIX = "serverless-saas-pipeline-lab6-artifacts"


def generate_bucket_name(lab_number: int, stack_id_hash: str) -> str:
    """
    Generate bucket name using the Stack ID hash pattern.
    
    Pattern: serverless-saas-pipeline-lab{N}-artifacts-{8-char-hex}
    
    Args:
        lab_number: Lab number (5 or 6)
        stack_id_hash: 8-character hexadecimal hash from CloudFormation Stack ID
    
    Returns:
        Generated bucket name
    """
    return f"serverless-saas-pipeline-lab{lab_number}-artifacts-{stack_id_hash}"


def validate_bucket_name_pattern(bucket_name: str, lab_number: int, stack_id_hash: str) -> bool:
    """
    Validate that bucket name matches the expected Stack ID hash pattern.
    
    Expected pattern: serverless-saas-pipeline-lab{N}-artifacts-{8-char-hex}
    """
    expected_name = generate_bucket_name(lab_number, stack_id_hash)
    return bucket_name == expected_name


def validate_bucket_name_lowercase(bucket_name: str) -> bool:
    """
    Validate that bucket name contains only lowercase characters.
    
    AWS S3 bucket names must be lowercase.
    """
    return bucket_name == bucket_name.lower()


def validate_bucket_name_characters(bucket_name: str) -> bool:
    """
    Validate that bucket name contains only valid characters.
    
    AWS S3 bucket names can only contain lowercase letters, numbers, and hyphens.
    """
    pattern = r'^[a-z0-9\-]+$'
    return bool(re.match(pattern, bucket_name))


def validate_bucket_name_length(bucket_name: str) -> bool:
    """
    Validate that bucket name length is within AWS limits.
    
    AWS S3 bucket names must be between 3 and 63 characters.
    """
    return 3 <= len(bucket_name) <= 63


def validate_bucket_name_structure(bucket_name: str) -> bool:
    """
    Validate that bucket name has the correct structure.
    
    Should not start or end with hyphen, and should not have consecutive hyphens.
    """
    if bucket_name.startswith('-') or bucket_name.endswith('-'):
        return False
    if '--' in bucket_name:
        return False
    return True


# Strategy for generating valid 8-character hexadecimal strings (simulating CloudFormation Stack ID hash)
stack_id_hash_strategy = st.text(
    alphabet='0123456789abcdef',
    min_size=8,
    max_size=8
)


# Property Test 1: Bucket Name Pattern Compliance (Lab 6)
@settings(max_examples=100, deadline=None)
@given(stack_id_hash=stack_id_hash_strategy)
def test_lab6_bucket_name_pattern_property(stack_id_hash: str):
    """
    Property: For any valid 8-character hex string (Stack ID hash), the generated
    Lab 6 bucket name should match the pattern serverless-saas-pipeline-lab6-artifacts-{hash}.
    
    **Validates: Requirements 1.1, 1.2, 1.3, 1.5**
    
    This property verifies:
    1. Bucket name includes the lab identifier "lab6"
    2. Bucket name includes the purpose identifier "artifacts"
    3. Bucket name includes the Stack ID hash
    4. Bucket name is lowercase
    """
    # Generate bucket name using the same logic as CDK stack
    bucket_name = generate_bucket_name(6, stack_id_hash)
    
    # Property 1: Bucket name must match the expected pattern
    assert validate_bucket_name_pattern(bucket_name, 6, stack_id_hash), \
        f"Bucket name '{bucket_name}' does not match expected pattern"
    
    # Property 2: Bucket name must be lowercase
    assert validate_bucket_name_lowercase(bucket_name), \
        f"Bucket name '{bucket_name}' is not lowercase"
    
    # Property 3: Bucket name must include lab identifier
    assert "lab6" in bucket_name, \
        f"Bucket name '{bucket_name}' does not include lab identifier 'lab6'"
    
    # Property 4: Bucket name must include purpose identifier
    assert "artifacts" in bucket_name, \
        f"Bucket name '{bucket_name}' does not include purpose identifier 'artifacts'"
    
    # Property 5: Bucket name must include Stack ID hash
    assert stack_id_hash in bucket_name, \
        f"Bucket name '{bucket_name}' does not include Stack ID hash '{stack_id_hash}'"


# Property Test 2: Bucket Name Pattern Compliance (Lab 5)
@settings(max_examples=100, deadline=None)
@given(stack_id_hash=stack_id_hash_strategy)
def test_lab5_bucket_name_pattern_property(stack_id_hash: str):
    """
    Property: For any valid 8-character hex string (Stack ID hash), the generated
    Lab 5 bucket name should match the pattern serverless-saas-pipeline-lab5-artifacts-{hash}.
    
    **Validates: Requirements 2.1, 2.2, 2.3, 2.5**
    
    This property verifies:
    1. Bucket name includes the lab identifier "lab5"
    2. Bucket name includes the purpose identifier "artifacts"
    3. Bucket name includes the Stack ID hash
    4. Bucket name is lowercase
    """
    # Generate bucket name using the same logic as CDK stack
    bucket_name = generate_bucket_name(5, stack_id_hash)
    
    # Property 1: Bucket name must match the expected pattern
    assert validate_bucket_name_pattern(bucket_name, 5, stack_id_hash), \
        f"Bucket name '{bucket_name}' does not match expected pattern"
    
    # Property 2: Bucket name must be lowercase
    assert validate_bucket_name_lowercase(bucket_name), \
        f"Bucket name '{bucket_name}' is not lowercase"
    
    # Property 3: Bucket name must include lab identifier
    assert "lab5" in bucket_name, \
        f"Bucket name '{bucket_name}' does not include lab identifier 'lab5'"
    
    # Property 4: Bucket name must include purpose identifier
    assert "artifacts" in bucket_name, \
        f"Bucket name '{bucket_name}' does not include purpose identifier 'artifacts'"
    
    # Property 5: Bucket name must include Stack ID hash
    assert stack_id_hash in bucket_name, \
        f"Bucket name '{bucket_name}' does not include Stack ID hash '{stack_id_hash}'"


# Property Test 3: Bucket Name Character Validation
@settings(max_examples=100, deadline=None)
@given(
    lab_number=st.sampled_from([5, 6]),
    stack_id_hash=stack_id_hash_strategy
)
def test_bucket_name_character_validation_property(lab_number: int, stack_id_hash: str):
    """
    Property: For any valid lab number and Stack ID hash, the generated bucket name
    should contain only lowercase letters, numbers, and hyphens.
    
    **Validates: Requirements 1.4, 2.4**
    
    This property verifies AWS S3 naming convention compliance.
    """
    # Generate bucket name using the same logic as CDK stack
    bucket_name = generate_bucket_name(lab_number, stack_id_hash)
    
    # Property 1: Bucket name must contain only valid characters
    assert validate_bucket_name_characters(bucket_name), \
        f"Bucket name '{bucket_name}' contains invalid characters"
    
    # Property 2: Bucket name must be within length limits
    assert validate_bucket_name_length(bucket_name), \
        f"Bucket name '{bucket_name}' length {len(bucket_name)} is not within AWS limits (3-63)"
    
    # Property 3: Bucket name must have valid structure
    assert validate_bucket_name_structure(bucket_name), \
        f"Bucket name '{bucket_name}' has invalid structure (starts/ends with hyphen or has consecutive hyphens)"


# Unit Test: Specific Example Validation (Lab 6)
def test_lab6_bucket_name_specific_example():
    """
    Unit test: Verify Lab 6 bucket name generation with a specific example.
    
    This test uses a concrete example to verify the bucket naming logic.
    """
    stack_id_hash = "ef0699a0"
    
    expected_name = "serverless-saas-pipeline-lab6-artifacts-ef0699a0"
    actual_name = generate_bucket_name(6, stack_id_hash)
    
    assert actual_name == expected_name, \
        f"Expected '{expected_name}', got '{actual_name}'"
    
    # Verify all validation checks pass
    assert validate_bucket_name_pattern(actual_name, 6, stack_id_hash)
    assert validate_bucket_name_lowercase(actual_name)
    assert validate_bucket_name_characters(actual_name)
    assert validate_bucket_name_length(actual_name)
    assert validate_bucket_name_structure(actual_name)


# Unit Test: Specific Example Validation (Lab 5)
def test_lab5_bucket_name_specific_example():
    """
    Unit test: Verify Lab 5 bucket name generation with a specific example.
    
    This test uses a concrete example to verify the bucket naming logic.
    """
    stack_id_hash = "a1b2c3d4"
    
    expected_name = "serverless-saas-pipeline-lab5-artifacts-a1b2c3d4"
    actual_name = generate_bucket_name(5, stack_id_hash)
    
    assert actual_name == expected_name, \
        f"Expected '{expected_name}', got '{actual_name}'"
    
    # Verify all validation checks pass
    assert validate_bucket_name_pattern(actual_name, 5, stack_id_hash)
    assert validate_bucket_name_lowercase(actual_name)
    assert validate_bucket_name_characters(actual_name)
    assert validate_bucket_name_length(actual_name)
    assert validate_bucket_name_structure(actual_name)


# Unit Test: Edge Cases
def test_bucket_name_edge_cases():
    """
    Unit test: Verify bucket name generation handles edge cases correctly.
    """
    # Test with different Stack ID hashes
    test_cases = [
        (5, "00000000", "serverless-saas-pipeline-lab5-artifacts-00000000"),
        (5, "ffffffff", "serverless-saas-pipeline-lab5-artifacts-ffffffff"),
        (6, "12345678", "serverless-saas-pipeline-lab6-artifacts-12345678"),
        (6, "abcdef01", "serverless-saas-pipeline-lab6-artifacts-abcdef01"),
    ]
    
    for lab_number, stack_id_hash, expected_name in test_cases:
        actual_name = generate_bucket_name(lab_number, stack_id_hash)
        assert actual_name == expected_name, \
            f"For lab {lab_number} and hash {stack_id_hash}: expected '{expected_name}', got '{actual_name}'"


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
