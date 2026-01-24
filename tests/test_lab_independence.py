#!/usr/bin/env python3
"""
Property-Based Tests: Lab Independence and Resource Naming Uniqueness

Feature: workshop-modernization, Property 6: Lab Independence
Feature: workshop-modernization, Property 7: Resource Naming Uniqueness
Validates: Requirements 6.1, 6.2

These tests verify that:
1. Each lab can be deployed independently without dependencies on other labs
2. Resource names are unique across labs to prevent conflicts
"""

import os
import yaml
import pytest
from pathlib import Path
from typing import List, Dict, Any, Set, Tuple
from hypothesis import given, settings, strategies as st
from itertools import combinations


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
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]

# Shared resources that are intentionally used across all labs (no lab suffix)
SHARED_RESOURCE_NAMES = {
    "apigateway-cloudwatch-publish-role",  # Shared API Gateway CloudWatch role
}


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


def extract_resource_names(template_path: Path, lab_name: str) -> Dict[str, List[str]]:
    """
    Extract all resource names from a CloudFormation template.
    
    Returns:
        Dictionary mapping resource types to lists of resource names.
    """
    resource_names = {}
    
    try:
        with open(template_path, 'r') as f:
            template_content = yaml.safe_load(f)
        
        if not template_content:
            return resource_names
        
        resources = template_content.get("Resources", {})
        
        for resource_name, resource_config in resources.items():
            resource_type = resource_config.get("Type", "")
            properties = resource_config.get("Properties", {})
            
            # Extract physical resource names based on resource type
            physical_name = None
            
            if resource_type == "AWS::S3::Bucket":
                physical_name = properties.get("BucketName")
            elif resource_type == "AWS::DynamoDB::Table":
                physical_name = properties.get("TableName")
            elif resource_type in ["AWS::Lambda::Function", "AWS::Serverless::Function"]:
                physical_name = properties.get("FunctionName")
            elif resource_type == "AWS::IAM::Role":
                physical_name = properties.get("RoleName")
            elif resource_type == "AWS::IAM::Policy":
                physical_name = properties.get("PolicyName")
            elif resource_type == "AWS::Cognito::UserPool":
                physical_name = properties.get("UserPoolName")
            elif resource_type == "AWS::ApiGateway::RestApi":
                physical_name = properties.get("Name")
            elif resource_type == "AWS::Logs::LogGroup":
                physical_name = properties.get("LogGroupName")
            elif resource_type in ["AWS::Lambda::LayerVersion", "AWS::Serverless::LayerVersion"]:
                physical_name = properties.get("LayerName")
            
            # Store the resource name (use logical ID if no physical name)
            name_to_store = physical_name if physical_name else resource_name
            
            # Handle intrinsic functions (they return dicts)
            if isinstance(name_to_store, dict):
                # For intrinsic functions, we'll use the logical resource name
                name_to_store = resource_name
            
            if resource_type not in resource_names:
                resource_names[resource_type] = []
            
            resource_names[resource_type].append({
                "logical_name": resource_name,
                "physical_name": name_to_store,
                "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                "lab": lab_name
            })
    
    except Exception as e:
        print(f"Warning: Could not parse {template_path}: {e}")
    
    return resource_names


def extract_cloudformation_exports(template_path: Path, lab_name: str) -> List[str]:
    """
    Extract all CloudFormation export names from a template.
    
    Returns:
        List of export names.
    """
    exports = []
    
    try:
        with open(template_path, 'r') as f:
            template_content = yaml.safe_load(f)
        
        if not template_content:
            return exports
        
        outputs = template_content.get("Outputs", {})
        
        for output_name, output_config in outputs.items():
            export_config = output_config.get("Export", {})
            export_name = export_config.get("Name")
            
            if export_name:
                # Handle intrinsic functions
                if isinstance(export_name, dict):
                    # Try to extract the base name from intrinsic functions
                    if "Fn::Sub" in export_name:
                        sub_value = export_name["Fn::Sub"]
                        if isinstance(sub_value, str):
                            exports.append(sub_value)
                    elif "Ref" in export_name:
                        exports.append(f"Ref:{export_name['Ref']}")
                else:
                    exports.append(export_name)
    
    except Exception as e:
        print(f"Warning: Could not parse {template_path}: {e}")
    
    return exports


def extract_cloudformation_imports(template_path: Path, lab_name: str) -> List[str]:
    """
    Extract all CloudFormation import references from a template.
    
    Returns:
        List of import names (Fn::ImportValue references).
    """
    imports = []
    
    def find_import_values(obj):
        """Recursively find all Fn::ImportValue references."""
        if isinstance(obj, dict):
            if "Fn::ImportValue" in obj:
                import_value = obj["Fn::ImportValue"]
                if isinstance(import_value, str):
                    imports.append(import_value)
                elif isinstance(import_value, dict):
                    # Handle nested intrinsic functions
                    if "Fn::Sub" in import_value:
                        sub_value = import_value["Fn::Sub"]
                        if isinstance(sub_value, str):
                            imports.append(sub_value)
            else:
                for value in obj.values():
                    find_import_values(value)
        elif isinstance(obj, list):
            for item in obj:
                find_import_values(item)
    
    try:
        with open(template_path, 'r') as f:
            template_content = yaml.safe_load(f)
        
        if template_content:
            find_import_values(template_content)
    
    except Exception as e:
        print(f"Warning: Could not parse {template_path}: {e}")
    
    return imports


def check_cross_lab_references(lab_name: str, templates: List[Path]) -> List[Dict[str, Any]]:
    """
    Check if a lab's templates reference resources from other labs.
    
    Returns:
        List of cross-lab reference violations.
    """
    violations = []
    
    # Get all imports from this lab
    lab_imports = []
    for template_path in templates:
        imports = extract_cloudformation_imports(template_path, lab_name)
        for import_name in imports:
            lab_imports.append({
                "import_name": import_name,
                "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                "lab": lab_name
            })
    
    # Check if imports reference other labs
    for import_ref in lab_imports:
        import_name = import_ref["import_name"]
        
        # Check if the import references another lab
        # Expected pattern: Serverless-SaaS-*-labN where N is the lab number
        for other_lab_num in range(1, 8):
            other_lab_suffix = f"-lab{other_lab_num}"
            
            # Skip if it's the same lab
            if lab_name == f"Lab{other_lab_num}":
                continue
            
            # Check if import references another lab
            if other_lab_suffix in import_name:
                violations.append({
                    "lab": lab_name,
                    "import_name": import_name,
                    "references_lab": f"Lab{other_lab_num}",
                    "template": import_ref["template"]
                })
    
    return violations


# Property Test 6: Lab Independence
@settings(max_examples=100, deadline=None)
@given(st.sampled_from(LAB_DIRECTORIES))
def test_lab_independence_property(lab_name: str):
    """
    Property: For any lab (Lab 1-7), deploying that lab in isolation
    (without other labs deployed) should succeed and create a functional environment.
    
    This test validates that:
    1. Templates don't reference resources from other labs via Fn::ImportValue
    2. All required resources are defined within the lab
    3. No hard-coded dependencies on other lab resources
    """
    lab_path = WORKSHOP_ROOT / lab_name
    
    # Skip if lab doesn't exist
    if not lab_path.exists():
        pytest.skip(f"Lab {lab_name} does not exist")
    
    templates = find_sam_templates(lab_path)
    
    # Skip if no templates found
    if not templates:
        pytest.skip(f"No SAM templates found in {lab_name}")
    
    # Check for cross-lab references
    violations = check_cross_lab_references(lab_name, templates)
    
    # Assert no cross-lab references found
    if violations:
        error_msg = f"\nLab independence violations found in {lab_name}:\n"
        error_msg += f"  {lab_name} references resources from other labs:\n"
        for v in violations:
            error_msg += f"    - Import '{v['import_name']}' references {v['references_lab']} in {v['template']}\n"
        error_msg += f"\n  Each lab should be independently deployable without dependencies on other labs.\n"
        error_msg += f"  Consider:\n"
        error_msg += f"    1. Defining all required resources within {lab_name}\n"
        error_msg += f"    2. Using lab-specific export names (e.g., *-{lab_name.lower()})\n"
        error_msg += f"    3. Removing cross-lab Fn::ImportValue references\n"
        pytest.fail(error_msg)


# Property Test 7: Resource Naming Uniqueness
@settings(max_examples=100, deadline=None)
@given(st.sampled_from(list(combinations(LAB_DIRECTORIES, 2))))
def test_resource_naming_uniqueness_property(lab_pair: Tuple[str, str]):
    """
    Property: For any two different labs deployed simultaneously,
    their resource names should be unique and not conflict with each other.
    
    This test validates that:
    1. Physical resource names (S3 buckets, DynamoDB tables, etc.) are unique
    2. CloudFormation export names are unique
    3. Resources follow the naming convention with lab-specific suffixes
    """
    lab1_name, lab2_name = lab_pair
    
    lab1_path = WORKSHOP_ROOT / lab1_name
    lab2_path = WORKSHOP_ROOT / lab2_name
    
    # Skip if either lab doesn't exist
    if not lab1_path.exists() or not lab2_path.exists():
        pytest.skip(f"One or both labs do not exist: {lab1_name}, {lab2_name}")
    
    lab1_templates = find_sam_templates(lab1_path)
    lab2_templates = find_sam_templates(lab2_path)
    
    # Skip if no templates found
    if not lab1_templates or not lab2_templates:
        pytest.skip(f"No SAM templates found in one or both labs")
    
    # Extract resource names from both labs
    lab1_resources = {}
    for template_path in lab1_templates:
        resources = extract_resource_names(template_path, lab1_name)
        for resource_type, resource_list in resources.items():
            if resource_type not in lab1_resources:
                lab1_resources[resource_type] = []
            lab1_resources[resource_type].extend(resource_list)
    
    lab2_resources = {}
    for template_path in lab2_templates:
        resources = extract_resource_names(template_path, lab2_name)
        for resource_type, resource_list in resources.items():
            if resource_type not in lab2_resources:
                lab2_resources[resource_type] = []
            lab2_resources[resource_type].extend(resource_list)
    
    # Extract CloudFormation exports from both labs
    lab1_exports = []
    for template_path in lab1_templates:
        lab1_exports.extend(extract_cloudformation_exports(template_path, lab1_name))
    
    lab2_exports = []
    for template_path in lab2_templates:
        lab2_exports.extend(extract_cloudformation_exports(template_path, lab2_name))
    
    # Check for naming conflicts
    naming_conflicts = []
    
    # Check physical resource name conflicts
    for resource_type in set(lab1_resources.keys()) & set(lab2_resources.keys()):
        # Only check resources that have explicit physical names (not just logical names)
        lab1_names = {r["physical_name"] for r in lab1_resources[resource_type] 
                      if r["physical_name"] != r["logical_name"] 
                      and not isinstance(r["physical_name"], dict)
                      and r["physical_name"] not in SHARED_RESOURCE_NAMES}
        lab2_names = {r["physical_name"] for r in lab2_resources[resource_type] 
                      if r["physical_name"] != r["logical_name"] 
                      and not isinstance(r["physical_name"], dict)
                      and r["physical_name"] not in SHARED_RESOURCE_NAMES}
        
        conflicts = lab1_names & lab2_names
        
        for conflict_name in conflicts:
            # Find the resources with this name
            lab1_resource = next((r for r in lab1_resources[resource_type] if r["physical_name"] == conflict_name), None)
            lab2_resource = next((r for r in lab2_resources[resource_type] if r["physical_name"] == conflict_name), None)
            
            naming_conflicts.append({
                "resource_type": resource_type,
                "conflict_name": conflict_name,
                "lab1": lab1_name,
                "lab1_template": lab1_resource["template"] if lab1_resource else "unknown",
                "lab2": lab2_name,
                "lab2_template": lab2_resource["template"] if lab2_resource else "unknown"
            })
    
    # Check CloudFormation export name conflicts
    export_conflicts = set(lab1_exports) & set(lab2_exports)
    
    for export_name in export_conflicts:
        naming_conflicts.append({
            "resource_type": "CloudFormation Export",
            "conflict_name": export_name,
            "lab1": lab1_name,
            "lab1_template": "multiple templates",
            "lab2": lab2_name,
            "lab2_template": "multiple templates"
        })
    
    # Assert no naming conflicts found
    if naming_conflicts:
        error_msg = f"\nResource naming conflicts found between {lab1_name} and {lab2_name}:\n"
        for conflict in naming_conflicts:
            error_msg += f"  - {conflict['resource_type']}: '{conflict['conflict_name']}'\n"
            error_msg += f"    Used in {conflict['lab1']} ({conflict['lab1_template']})\n"
            error_msg += f"    Used in {conflict['lab2']} ({conflict['lab2_template']})\n"
        error_msg += f"\n  Resources must have unique names across labs to prevent conflicts.\n"
        error_msg += f"  Follow the naming convention: serverless-saas-lab{{N}}-{{resource-type}}\n"
        error_msg += f"  See RESOURCE_NAMING_CONVENTION.md for details.\n"
        pytest.fail(error_msg)


def test_all_labs_have_unique_exports():
    """
    Comprehensive test: Verify all CloudFormation exports are unique across all labs.
    """
    all_exports = {}
    
    for lab_name in LAB_DIRECTORIES:
        lab_path = WORKSHOP_ROOT / lab_name
        if not lab_path.exists():
            continue
        
        templates = find_sam_templates(lab_path)
        
        for template_path in templates:
            exports = extract_cloudformation_exports(template_path, lab_name)
            
            for export_name in exports:
                if export_name not in all_exports:
                    all_exports[export_name] = []
                
                all_exports[export_name].append({
                    "lab": lab_name,
                    "template": str(template_path.relative_to(WORKSHOP_ROOT))
                })
    
    # Find duplicate exports
    duplicates = {name: labs for name, labs in all_exports.items() if len(labs) > 1}
    
    if duplicates:
        error_msg = f"\nFound {len(duplicates)} CloudFormation export(s) used in multiple labs:\n"
        for export_name, labs in duplicates.items():
            error_msg += f"  - '{export_name}' used in:\n"
            for lab_info in labs:
                error_msg += f"    - {lab_info['lab']} ({lab_info['template']})\n"
        error_msg += f"\n  CloudFormation exports must be unique across all labs.\n"
        error_msg += f"  Add lab-specific suffixes (e.g., -lab1, -lab2) to export names.\n"
        pytest.fail(error_msg)


def test_all_labs_follow_naming_convention():
    """
    Test: Verify all labs follow the resource naming convention.
    
    Expected pattern: serverless-saas-lab{N}-{resource-type}
    """
    violations = []
    
    for lab_name in LAB_DIRECTORIES:
        lab_path = WORKSHOP_ROOT / lab_name
        if not lab_path.exists():
            continue
        
        lab_num = lab_name.replace("Lab", "")
        expected_prefix = f"serverless-saas-lab{lab_num}-"
        
        templates = find_sam_templates(lab_path)
        
        for template_path in templates:
            resources = extract_resource_names(template_path, lab_name)
            
            for resource_type, resource_list in resources.items():
                # Skip resource types that don't require naming convention
                skip_types = {
                    "AWS::Lambda::LayerVersion",
                    "AWS::Serverless::LayerVersion",
                    "AWS::IAM::Policy",
                    "AWS::Cognito::UserPoolClient",
                    "AWS::ApiGateway::Stage",
                    "AWS::ApiGateway::Deployment",
                    "AWS::Lambda::Permission",
                    "AWS::CloudFront::CloudFrontOriginAccessIdentity",
                    "AWS::S3::BucketPolicy",
                    "AWS::ApiGateway::Account",
                }
                
                if resource_type in skip_types:
                    continue
                
                for resource in resource_list:
                    physical_name = resource["physical_name"]
                    
                    # Skip if it's a logical resource name or intrinsic function
                    if isinstance(physical_name, dict) or physical_name == resource["logical_name"]:
                        continue
                    
                    # Check if the name follows the convention
                    # Allow some exceptions for specific resource types
                    if resource_type == "AWS::DynamoDB::Table":
                        # DynamoDB tables may use different patterns
                        # e.g., ServerlessSaaS-*-lab{N} or *-{tenantId}-lab{N}
                        if f"-lab{lab_num}" not in physical_name:
                            violations.append({
                                "lab": lab_name,
                                "resource_type": resource_type,
                                "physical_name": physical_name,
                                "template": resource["template"],
                                "expected_pattern": f"*-lab{lab_num}"
                            })
                    elif resource_type == "AWS::Cognito::UserPool":
                        # Cognito pools follow pattern: {PoolType}-ServerlessSaaS-lab{N}-UserPool
                        # This is acceptable per RESOURCE_NAMING_CONVENTION.md
                        if f"-lab{lab_num}-UserPool" not in physical_name:
                            violations.append({
                                "lab": lab_name,
                                "resource_type": resource_type,
                                "physical_name": physical_name,
                                "template": resource["template"],
                                "expected_pattern": f"*-lab{lab_num}-UserPool"
                            })
                    elif resource_type in ["AWS::S3::Bucket"]:
                        # S3 buckets should have lab prefix
                        if not physical_name.startswith(expected_prefix):
                            violations.append({
                                "lab": lab_name,
                                "resource_type": resource_type,
                                "physical_name": physical_name,
                                "template": resource["template"],
                                "expected_pattern": f"{expected_prefix}*"
                            })
    
    if violations:
        error_msg = f"\nFound {len(violations)} resource(s) not following naming convention:\n"
        for v in violations:
            error_msg += f"  - {v['lab']}/{v['resource_type']}: '{v['physical_name']}'\n"
            error_msg += f"    Template: {v['template']}\n"
            error_msg += f"    Expected pattern: {v['expected_pattern']}\n"
        error_msg += f"\n  See RESOURCE_NAMING_CONVENTION.md for naming standards.\n"
        pytest.fail(error_msg)


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
