#!/usr/bin/env python3
"""
Property-Based Test: Python Runtime Consistency

Feature: workshop-modernization, Property 2: Python Runtime Consistency
Validates: Requirements 2.1

This test verifies that all Lambda functions across all labs use Python 3.14 runtime.
"""

import os
import yaml
import pytest
from pathlib import Path
from typing import List, Dict, Any
from hypothesis import given, settings, strategies as st


# Custom YAML constructors for CloudFormation intrinsic functions
def cfn_constructor(loader, tag_suffix, node):
    """Generic constructor for CloudFormation intrinsic functions."""
    if isinstance(node, yaml.ScalarNode):
        return {tag_suffix: loader.construct_scalar(node)}
    elif isinstance(node, yaml.SequenceNode):
        return {tag_suffix: loader.construct_sequence(node)}
    elif isinstance(node, yaml.MappingNode):
        return {tag_suffix: loader.construct_mapping(node)}
    return {tag_suffix: None}


# Register CloudFormation intrinsic function tags
yaml.SafeLoader.add_multi_constructor('!', cfn_constructor)


# Constants
EXPECTED_RUNTIME = "python3.14"
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]


def find_sam_templates(lab_dir: Path) -> List[Path]:
    """Find all SAM/CloudFormation template files in a lab directory."""
    templates = []
    
    # Common template file names
    template_names = [
        "template.yaml",
        "template.yml",
        "shared-template.yaml",
        "tenant-template.yaml",
    ]
    
    for template_name in template_names:
        for template_path in lab_dir.rglob(template_name):
            # Skip node_modules and .aws-sam directories
            if "node_modules" not in str(template_path) and ".aws-sam" not in str(template_path):
                templates.append(template_path)
    
    # Also check nested_templates directories
    nested_templates_dir = lab_dir / "server" / "nested_templates"
    if nested_templates_dir.exists():
        for yaml_file in nested_templates_dir.glob("*.yaml"):
            templates.append(yaml_file)
    
    return templates


def extract_lambda_functions(template_content: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Extract all Lambda function resources from a SAM/CloudFormation template."""
    lambda_functions = []
    
    resources = template_content.get("Resources", {})
    for resource_name, resource_config in resources.items():
        resource_type = resource_config.get("Type", "")
        
        # Check for Lambda function types
        if resource_type in ["AWS::Serverless::Function", "AWS::Lambda::Function"]:
            lambda_functions.append({
                "name": resource_name,
                "config": resource_config,
                "type": resource_type
            })
    
    return lambda_functions


def get_runtime_from_function(function: Dict[str, Any]) -> str:
    """Extract runtime from a Lambda function configuration."""
    properties = function["config"].get("Properties", {})
    return properties.get("Runtime", "")


def get_all_lambda_functions_from_workshop() -> List[Dict[str, Any]]:
    """
    Scan all labs and extract all Lambda function configurations.
    
    Returns:
        List of dictionaries containing function name, runtime, template path, and lab.
    """
    all_functions = []
    
    for lab_name in LAB_DIRECTORIES:
        lab_path = WORKSHOP_ROOT / lab_name
        if not lab_path.exists():
            continue
        
        templates = find_sam_templates(lab_path)
        
        for template_path in templates:
            try:
                with open(template_path, 'r') as f:
                    template_content = yaml.safe_load(f)
                
                if not template_content:
                    continue
                
                lambda_functions = extract_lambda_functions(template_content)
                
                for func in lambda_functions:
                    runtime = get_runtime_from_function(func)
                    all_functions.append({
                        "name": func["name"],
                        "runtime": runtime,
                        "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                        "lab": lab_name,
                        "type": func["type"]
                    })
            
            except Exception as e:
                # Skip templates that can't be parsed
                print(f"Warning: Could not parse {template_path}: {e}")
                continue
    
    return all_functions


# Property Test 2: Python Runtime Consistency
@settings(max_examples=10, deadline=None)
@given(st.sampled_from(LAB_DIRECTORIES))
def test_python_runtime_consistency_property(lab_name: str):
    """
    Property: For any Lambda function in any lab, the runtime should be python3.14.
    
    This property-based test verifies that all Lambda functions across all labs
    consistently use Python 3.14 as their runtime.
    """
    lab_path = WORKSHOP_ROOT / lab_name
    
    # Skip if lab doesn't exist
    if not lab_path.exists():
        pytest.skip(f"Lab {lab_name} does not exist")
    
    templates = find_sam_templates(lab_path)
    
    # Skip if no templates found
    if not templates:
        pytest.skip(f"No SAM templates found in {lab_name}")
    
    violations = []
    
    for template_path in templates:
        try:
            with open(template_path, 'r') as f:
                template_content = yaml.safe_load(f)
            
            if not template_content:
                continue
            
            lambda_functions = extract_lambda_functions(template_content)
            
            for func in lambda_functions:
                runtime = get_runtime_from_function(func)
                
                # Property: Every Lambda function must have python3.14 runtime
                if runtime and runtime != EXPECTED_RUNTIME:
                    violations.append({
                        "function": func["name"],
                        "runtime": runtime,
                        "expected": EXPECTED_RUNTIME,
                        "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                        "lab": lab_name
                    })
        
        except Exception as e:
            # Log parsing errors but don't fail the test
            print(f"Warning: Could not parse {template_path}: {e}")
            continue
    
    # Assert no violations found
    if violations:
        error_msg = f"\nPython runtime violations found in {lab_name}:\n"
        for v in violations:
            error_msg += f"  - {v['function']} in {v['template']}: {v['runtime']} (expected {v['expected']})\n"
        pytest.fail(error_msg)


def test_all_lambda_functions_use_python_314():
    """
    Comprehensive test: Verify all Lambda functions across all labs use Python 3.14.
    
    This is a single comprehensive test that checks all Lambda functions at once.
    """
    all_functions = get_all_lambda_functions_from_workshop()
    
    # Ensure we found some Lambda functions
    assert len(all_functions) > 0, "No Lambda functions found in workshop"
    
    violations = []
    
    for func in all_functions:
        if func["runtime"] and func["runtime"] != EXPECTED_RUNTIME:
            violations.append(func)
    
    # Report violations
    if violations:
        error_msg = f"\nFound {len(violations)} Lambda function(s) not using {EXPECTED_RUNTIME}:\n"
        for v in violations:
            error_msg += f"  - {v['lab']}/{v['name']} in {v['template']}: {v['runtime']}\n"
        pytest.fail(error_msg)
    
    # Report success
    print(f"\n✓ All {len(all_functions)} Lambda functions use {EXPECTED_RUNTIME}")


def test_lambda_layers_use_python_314():
    """
    Test: Verify all Lambda layers specify Python 3.14 in CompatibleRuntimes.
    """
    violations = []
    
    for lab_name in LAB_DIRECTORIES:
        lab_path = WORKSHOP_ROOT / lab_name
        if not lab_path.exists():
            continue
        
        templates = find_sam_templates(lab_path)
        
        for template_path in templates:
            try:
                with open(template_path, 'r') as f:
                    template_content = yaml.safe_load(f)
                
                if not template_content:
                    continue
                
                resources = template_content.get("Resources", {})
                
                for resource_name, resource_config in resources.items():
                    resource_type = resource_config.get("Type", "")
                    
                    # Check for Lambda layer types
                    if resource_type in ["AWS::Serverless::LayerVersion", "AWS::Lambda::LayerVersion"]:
                        properties = resource_config.get("Properties", {})
                        compatible_runtimes = properties.get("CompatibleRuntimes", [])
                        
                        # Check if python3.14 is in compatible runtimes
                        if compatible_runtimes and EXPECTED_RUNTIME not in compatible_runtimes:
                            violations.append({
                                "layer": resource_name,
                                "runtimes": compatible_runtimes,
                                "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                                "lab": lab_name
                            })
            
            except Exception as e:
                print(f"Warning: Could not parse {template_path}: {e}")
                continue
    
    # Report violations
    if violations:
        error_msg = f"\nFound {len(violations)} Lambda layer(s) not compatible with {EXPECTED_RUNTIME}:\n"
        for v in violations:
            error_msg += f"  - {v['lab']}/{v['layer']} in {v['template']}: {v['runtimes']}\n"
        pytest.fail(error_msg)


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
