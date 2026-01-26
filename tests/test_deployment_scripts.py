#!/usr/bin/env python3
"""
Property-Based Tests: Deployment Script Success and Cleanup Script Completeness

Feature: workshop-modernization, Property 4: Deployment Script Success
Feature: workshop-modernization, Property 5: Cleanup Script Completeness
Validates: Requirements 4.1, 4.2, 4.4, 9.1

These tests verify that:
1. Deployment scripts complete successfully and create all required resources
2. Cleanup scripts remove all lab-specific resources without affecting other labs
"""

import os
import subprocess
import pytest
from pathlib import Path
from typing import List, Dict, Any, Set
from hypothesis import given, settings, strategies as st
import time


# Constants
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]

# AWS Profile for testing (can be overridden via environment variable)
AWS_PROFILE = os.environ.get("AWS_PROFILE", "serverless-saas-demo")
AWS_REGION = os.environ.get("AWS_REGION", "us-west-2")


def get_deployment_script(lab_dir: Path) -> Path:
    """Get the deployment script path for a lab."""
    script_path = lab_dir / "scripts" / "deployment.sh"
    return script_path if script_path.exists() else None


def get_cleanup_script(lab_dir: Path) -> Path:
    """Get the cleanup script path for a lab."""
    script_path = lab_dir / "scripts" / "cleanup.sh"
    return script_path if script_path.exists() else None


def check_script_has_profile_support(script_path: Path) -> bool:
    """Check if a script supports the --profile parameter."""
    if not script_path.exists():
        return False
    
    with open(script_path, 'r') as f:
        content = f.read()
        # Check for --profile parameter in the script
        return '--profile' in content and 'PROFILE=' in content


def check_script_has_region_support(script_path: Path) -> bool:
    """Check if a script supports the --region parameter."""
    if not script_path.exists():
        return False
    
    with open(script_path, 'r') as f:
        content = f.read()
        # Check for --region parameter in the script
        return '--region' in content and 'AWS_REGION=' in content


def get_cloudformation_stacks(profile: str, region: str) -> List[str]:
    """Get list of CloudFormation stacks in the account."""
    try:
        cmd = [
            "aws", "cloudformation", "list-stacks",
            "--stack-status-filter", "CREATE_COMPLETE", "UPDATE_COMPLETE",
            "--profile", profile,
            "--region", region,
            "--query", "StackSummaries[].StackName",
            "--output", "text"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout.strip().split() if result.stdout.strip() else []
        return []
    except Exception:
        return []


def get_lab_stack_name(lab_number: int) -> str:
    """Get the expected stack name for a lab."""
    if lab_number <= 2:
        return f"serverless-saas-lab{lab_number}"
    elif lab_number <= 6:
        return f"serverless-saas-shared-lab{lab_number}"
    else:  # Lab 7
        return "serverless-saas-lab7"


# ============================================================================
# Property 4: Deployment Script Success
# ============================================================================

@pytest.mark.property
@pytest.mark.slow
@given(lab_number=st.integers(min_value=1, max_value=7))
@settings(max_examples=7, deadline=None)
def test_deployment_script_success_property(lab_number: int):
    """
    Property 4: Deployment Script Success
    
    For any lab deployment script executed with valid AWS credentials and profile,
    the script should complete successfully and create all required resources.
    
    NOTE: This is a DRY RUN test that validates script structure and parameters.
    Actual deployment testing is done manually in tasks 28.1-28.8 due to:
    - Long deployment times (10-20 minutes per lab)
    - AWS resource costs
    - Complex inter-lab dependencies
    - Need for manual verification of deployed resources
    
    This test validates:
    1. Deployment script exists and is executable
    2. Script supports --profile parameter
    3. Script supports --region parameter
    4. Script has proper help text
    5. Script validates prerequisites
    """
    lab_dir = WORKSHOP_ROOT / f"Lab{lab_number}"
    deployment_script = get_deployment_script(lab_dir)
    
    # Verify deployment script exists
    assert deployment_script is not None, f"Lab{lab_number} deployment script not found"
    assert deployment_script.exists(), f"Lab{lab_number} deployment script does not exist"
    
    # Verify script is executable
    assert os.access(deployment_script, os.X_OK), f"Lab{lab_number} deployment script is not executable"
    
    # Verify script supports --profile parameter
    assert check_script_has_profile_support(deployment_script), \
        f"Lab{lab_number} deployment script does not support --profile parameter"
    
    # Verify script supports --region parameter
    assert check_script_has_region_support(deployment_script), \
        f"Lab{lab_number} deployment script does not support --region parameter"
    
    # Verify script has help text
    try:
        result = subprocess.run(
            [str(deployment_script), "--help"],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=deployment_script.parent
        )
        assert result.returncode == 0, f"Lab{lab_number} deployment script --help failed"
        assert "Usage:" in result.stdout or "usage:" in result.stdout.lower(), \
            f"Lab{lab_number} deployment script missing usage information"
    except subprocess.TimeoutExpired:
        pytest.fail(f"Lab{lab_number} deployment script --help timed out")


@pytest.mark.property
def test_all_labs_have_deployment_scripts():
    """
    Verify that all labs have deployment scripts with proper structure.
    
    This test ensures:
    1. All labs (1-7) have deployment scripts
    2. All scripts are executable
    3. All scripts support --profile and --region parameters
    4. All scripts have help text
    """
    for lab_number in range(1, 8):
        lab_dir = WORKSHOP_ROOT / f"Lab{lab_number}"
        deployment_script = get_deployment_script(lab_dir)
        
        # Check script exists
        assert deployment_script is not None, f"Lab{lab_number} missing deployment script"
        assert deployment_script.exists(), f"Lab{lab_number} deployment script does not exist"
        
        # Check script is executable
        assert os.access(deployment_script, os.X_OK), \
            f"Lab{lab_number} deployment script is not executable"
        
        # Check profile support
        assert check_script_has_profile_support(deployment_script), \
            f"Lab{lab_number} deployment script missing --profile support"
        
        # Check region support
        assert check_script_has_region_support(deployment_script), \
            f"Lab{lab_number} deployment script missing --region support"


# ============================================================================
# Property 5: Cleanup Script Completeness
# ============================================================================

@pytest.mark.property
@pytest.mark.slow
@given(lab_number=st.integers(min_value=1, max_value=7))
@settings(max_examples=7, deadline=None)
def test_cleanup_script_completeness_property(lab_number: int):
    """
    Property 5: Cleanup Script Completeness
    
    For any lab cleanup script executed after a successful deployment,
    the script should remove all lab-specific resources without affecting
    resources from other labs.
    
    NOTE: This is a DRY RUN test that validates script structure and parameters.
    Actual cleanup testing is done manually in tasks 28.1-28.8 due to:
    - Need for deployed resources to clean up
    - Long cleanup times (5-15 minutes per lab)
    - Risk of accidentally deleting resources from other labs
    - Need for manual verification of complete cleanup
    
    This test validates:
    1. Cleanup script exists and is executable
    2. Script supports --profile parameter
    3. Script supports --region parameter
    4. Script has proper help text
    5. Script has confirmation prompts (safety feature)
    """
    lab_dir = WORKSHOP_ROOT / f"Lab{lab_number}"
    cleanup_script = get_cleanup_script(lab_dir)
    
    # Verify cleanup script exists
    assert cleanup_script is not None, f"Lab{lab_number} cleanup script not found"
    assert cleanup_script.exists(), f"Lab{lab_number} cleanup script does not exist"
    
    # Verify script is executable
    assert os.access(cleanup_script, os.X_OK), f"Lab{lab_number} cleanup script is not executable"
    
    # Verify script supports --profile parameter
    assert check_script_has_profile_support(cleanup_script), \
        f"Lab{lab_number} cleanup script does not support --profile parameter"
    
    # Verify script supports --region parameter
    assert check_script_has_region_support(cleanup_script), \
        f"Lab{lab_number} cleanup script does not support --region parameter"
    
    # Verify script has help text
    try:
        result = subprocess.run(
            [str(cleanup_script), "--help"],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=cleanup_script.parent
        )
        assert result.returncode == 0, f"Lab{lab_number} cleanup script --help failed"
        assert "Usage:" in result.stdout or "usage:" in result.stdout.lower(), \
            f"Lab{lab_number} cleanup script missing usage information"
    except subprocess.TimeoutExpired:
        pytest.fail(f"Lab{lab_number} cleanup script --help timed out")
    
    # Verify script has confirmation prompts (safety feature)
    with open(cleanup_script, 'r') as f:
        content = f.read()
        # Check for confirmation prompts or -y/--yes flag
        has_confirmation = any(keyword in content for keyword in [
            'read -p', 'read -r', 'confirm', 'Are you sure', '-y', '--yes'
        ])
        assert has_confirmation, \
            f"Lab{lab_number} cleanup script missing confirmation prompts or -y/--yes flag"


@pytest.mark.property
def test_all_labs_have_cleanup_scripts():
    """
    Verify that all labs have cleanup scripts with proper structure.
    
    This test ensures:
    1. All labs (1-7) have cleanup scripts
    2. All scripts are executable
    3. All scripts support --profile and --region parameters
    4. All scripts have help text
    5. All scripts have confirmation prompts for safety
    """
    for lab_number in range(1, 8):
        lab_dir = WORKSHOP_ROOT / f"Lab{lab_number}"
        cleanup_script = get_cleanup_script(lab_dir)
        
        # Check script exists
        assert cleanup_script is not None, f"Lab{lab_number} missing cleanup script"
        assert cleanup_script.exists(), f"Lab{lab_number} cleanup script does not exist"
        
        # Check script is executable
        assert os.access(cleanup_script, os.X_OK), \
            f"Lab{lab_number} cleanup script is not executable"
        
        # Check profile support
        assert check_script_has_profile_support(cleanup_script), \
            f"Lab{lab_number} cleanup script missing --profile support"
        
        # Check region support
        assert check_script_has_region_support(cleanup_script), \
            f"Lab{lab_number} cleanup script missing --region support"
        
        # Check confirmation prompts
        with open(cleanup_script, 'r') as f:
            content = f.read()
            has_confirmation = any(keyword in content for keyword in [
                'read -p', 'read -r', 'confirm', 'Are you sure', '-y', '--yes'
            ])
            assert has_confirmation, \
                f"Lab{lab_number} cleanup script missing confirmation prompts"


@pytest.mark.property
def test_cleanup_scripts_target_correct_stacks():
    """
    Verify that cleanup scripts target the correct CloudFormation stacks.
    
    This test ensures:
    1. Each cleanup script references the correct stack name for its lab
    2. Stack names follow the naming convention
    3. Scripts don't accidentally target stacks from other labs
    """
    expected_stack_patterns = {
        1: ["serverless-saas-lab1"],
        2: ["serverless-saas-lab2"],
        3: ["serverless-saas-shared-lab3", "serverless-saas-tenant-lab3"],
        4: ["serverless-saas-shared-lab4", "serverless-saas-tenant-lab4"],
        5: ["serverless-saas-shared-lab5", "serverless-saas-pipeline-lab5"],
        6: ["serverless-saas-shared-lab6", "serverless-saas-pipeline-lab6"],
        7: ["serverless-saas-lab7", "stack-pooled-lab7"],
    }
    
    for lab_number in range(1, 8):
        lab_dir = WORKSHOP_ROOT / f"Lab{lab_number}"
        cleanup_script = get_cleanup_script(lab_dir)
        
        assert cleanup_script is not None, f"Lab{lab_number} cleanup script not found"
        
        with open(cleanup_script, 'r') as f:
            content = f.read()
        
        # Check that the script references the correct stack names
        expected_stacks = expected_stack_patterns[lab_number]
        for stack_name in expected_stacks:
            assert stack_name in content, \
                f"Lab{lab_number} cleanup script missing reference to stack '{stack_name}'"
        
        # Check that the script doesn't reference stacks from other labs
        for other_lab in range(1, 8):
            if other_lab != lab_number:
                other_stacks = expected_stack_patterns[other_lab]
                for other_stack in other_stacks:
                    # Allow generic patterns like "serverless-saas" but not specific other lab stacks
                    if f"lab{other_lab}" in other_stack.lower():
                        assert other_stack not in content, \
                            f"Lab{lab_number} cleanup script incorrectly references Lab{other_lab} stack '{other_stack}'"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-m", "property"])
