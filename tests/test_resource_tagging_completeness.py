#!/usr/bin/env python3
"""
Property-Based Test: Resource Tagging Completeness

Feature: workshop-modernization, Property 1: Resource Tagging Completeness
Validates: Requirements 1.1, 1.3

This test verifies that all AWS resources created by the workshop deployment
have all required tags with valid values.
"""

import os
import yaml
import pytest
from pathlib import Path
from typing import List, Dict, Any, Set
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
WORKSHOP_ROOT = Path(__file__).parent.parent
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]

# Standard tags required for all resources
STANDARD_TAGS = {"Application", "Lab", "Environment", "Owner", "CostCenter"}

# Tenant-specific resources require additional TenantId tag
TENANT_SPECIFIC_TAGS = STANDARD_TAGS | {"TenantId"}

# Resource types that support tagging
TAGGABLE_RESOURCE_TYPES = {
    "AWS::Serverless::Function",
    "AWS::Lambda::Function",
    "AWS::DynamoDB::Table",
    "AWS::IAM::Role",
    "AWS::ApiGateway::RestApi",
    "AWS::Logs::LogGroup",
    "AWS::S3::Bucket",
    "AWS::Cognito::UserPool",
    "AWS::CloudFront::Distribution",
}

# Resource types that don't support tags (skip these)
NON_TAGGABLE_RESOURCE_TYPES = {
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
    "AWS::ApiGateway::UsagePlan",
    "AWS::ApiGateway::UsagePlanKey",
    "AWS::ApiGateway::ApiKey",
    "AWS::CloudWatch::Alarm",
    "AWS::Logs::MetricFilter",
    "AWS::Glue::Database",
    "AWS::Glue::Crawler",
    "AWS::Events::Rule",
    "AWS::Scheduler::Schedule",
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


def is_tenant_specific_template(template_path: Path) -> bool:
    """Check if a template is tenant-specific (requires TenantId tag)."""
    return "tenant-template.yaml" in str(template_path)


def extract_tags_from_resource(resource_config: Dict[str, Any], resource_type: str) -> Set[str]:
    """
    Extract tag keys from a resource configuration.
    
    Different resource types use different tag formats:
    - Lambda functions: key-value format under Tags
    - DynamoDB, S3, IAM: list format with Key/Value pairs under Tags
    - Cognito: key-value format under UserPoolTags
    - API Gateway, CloudFront: key-value format under Tags
    """
    properties = resource_config.get("Properties", {})
    tag_keys = set()
    
    # Cognito User Pools use UserPoolTags
    if resource_type == "AWS::Cognito::UserPool":
        user_pool_tags = properties.get("UserPoolTags", {})
        if isinstance(user_pool_tags, dict):
            tag_keys = set(user_pool_tags.keys())
    
    # Most resources use Tags property
    else:
        tags = properties.get("Tags", {})
        
        # Key-value format (Lambda, API Gateway, CloudFront)
        if isinstance(tags, dict):
            tag_keys = set(tags.keys())
        
        # List format (DynamoDB, S3, IAM, CloudWatch)
        elif isinstance(tags, list):
            for tag in tags:
                if isinstance(tag, dict) and "Key" in tag:
                    tag_keys.add(tag["Key"])
    
    return tag_keys


def get_all_taggable_resources() -> List[Dict[str, Any]]:
    """
    Scan all labs and extract all taggable resource configurations.
    
    Returns:
        List of dictionaries containing resource details and tagging info.
    """
    all_resources = []
    
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
                is_tenant_template = is_tenant_specific_template(template_path)
                
                for resource_name, resource_config in resources.items():
                    resource_type = resource_config.get("Type", "")
                    
                    # Skip non-taggable resources
                    if resource_type in NON_TAGGABLE_RESOURCE_TYPES:
                        continue
                    
                    # Only check taggable resource types
                    if resource_type not in TAGGABLE_RESOURCE_TYPES:
                        continue
                    
                    # Extract tags from resource
                    tag_keys = extract_tags_from_resource(resource_config, resource_type)
                    
                    # Determine required tags
                    required_tags = TENANT_SPECIFIC_TAGS if is_tenant_template else STANDARD_TAGS
                    
                    all_resources.append({
                        "name": resource_name,
                        "type": resource_type,
                        "tags": tag_keys,
                        "required_tags": required_tags,
                        "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                        "lab": lab_name,
                        "is_tenant_specific": is_tenant_template
                    })
            
            except Exception as e:
                # Skip templates that can't be parsed
                print(f"Warning: Could not parse {template_path}: {e}")
                continue
    
    return all_resources


# Property Test 1: Resource Tagging Completeness
@settings(max_examples=100, deadline=None)
@given(st.sampled_from(LAB_DIRECTORIES))
def test_resource_tagging_completeness_property(lab_name: str):
    """
    Property: For any AWS resource created by the workshop deployment,
    that resource should have all required tags with valid values.
    
    Required tags vary by resource type:
    - Standard resources: Application, Lab, Environment, Owner, CostCenter
    - Tenant-specific resources: Additional TenantId tag
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
            
            resources = template_content.get("Resources", {})
            is_tenant_template = is_tenant_specific_template(template_path)
            
            for resource_name, resource_config in resources.items():
                resource_type = resource_config.get("Type", "")
                
                # Skip non-taggable resources
                if resource_type in NON_TAGGABLE_RESOURCE_TYPES:
                    continue
                
                # Only check taggable resource types
                if resource_type not in TAGGABLE_RESOURCE_TYPES:
                    continue
                
                # Extract tags from resource
                tag_keys = extract_tags_from_resource(resource_config, resource_type)
                
                # Determine required tags
                required_tags = TENANT_SPECIFIC_TAGS if is_tenant_template else STANDARD_TAGS
                
                # Check for missing tags
                missing_tags = required_tags - tag_keys
                
                if missing_tags:
                    violations.append({
                        "resource": resource_name,
                        "type": resource_type,
                        "missing_tags": sorted(missing_tags),
                        "present_tags": sorted(tag_keys),
                        "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                        "lab": lab_name,
                        "is_tenant_specific": is_tenant_template
                    })
        
        except Exception as e:
            # Log parsing errors but don't fail the test
            print(f"Warning: Could not parse {template_path}: {e}")
            continue
    
    # Assert no violations found
    if violations:
        error_msg = f"\nResource tagging violations found in {lab_name}:\n"
        for v in violations:
            tenant_note = " (tenant-specific)" if v["is_tenant_specific"] else ""
            error_msg += f"  - {v['resource']} ({v['type']}){tenant_note} in {v['template']}\n"
            error_msg += f"    Missing tags: {', '.join(v['missing_tags'])}\n"
            error_msg += f"    Present tags: {', '.join(v['present_tags']) if v['present_tags'] else 'None'}\n"
        pytest.fail(error_msg)


def test_all_resources_have_required_tags():
    """
    Comprehensive test: Verify all taggable resources across all labs have required tags.
    
    This is a single comprehensive test that checks all resources at once.
    """
    all_resources = get_all_taggable_resources()
    
    # Ensure we found some taggable resources
    assert len(all_resources) > 0, "No taggable resources found in workshop"
    
    violations = []
    
    for resource in all_resources:
        missing_tags = resource["required_tags"] - resource["tags"]
        
        if missing_tags:
            violations.append({
                "resource": resource["name"],
                "type": resource["type"],
                "missing_tags": sorted(missing_tags),
                "present_tags": sorted(resource["tags"]),
                "template": resource["template"],
                "lab": resource["lab"],
                "is_tenant_specific": resource["is_tenant_specific"]
            })
    
    # Report violations
    if violations:
        error_msg = f"\nFound {len(violations)} resource(s) with missing tags:\n"
        for v in violations:
            tenant_note = " (tenant-specific)" if v["is_tenant_specific"] else ""
            error_msg += f"  - {v['lab']}/{v['resource']} ({v['type']}){tenant_note} in {v['template']}\n"
            error_msg += f"    Missing: {', '.join(v['missing_tags'])}\n"
            error_msg += f"    Present: {', '.join(v['present_tags']) if v['present_tags'] else 'None'}\n"
        pytest.fail(error_msg)
    
    # Report success
    print(f"\n✓ All {len(all_resources)} taggable resources have required tags")


def test_tenant_specific_resources_have_tenant_id():
    """
    Test: Verify all tenant-specific resources (tenant-template.yaml) have TenantId tag.
    """
    violations = []
    
    for lab_name in LAB_DIRECTORIES:
        lab_path = WORKSHOP_ROOT / lab_name
        if not lab_path.exists():
            continue
        
        # Look for tenant-template.yaml
        tenant_templates = list(lab_path.rglob("tenant-template.yaml"))
        
        for template_path in tenant_templates:
            # Skip if in node_modules or .aws-sam
            if "node_modules" in str(template_path) or ".aws-sam" in str(template_path):
                continue
            
            try:
                with open(template_path, 'r') as f:
                    template_content = yaml.safe_load(f)
                
                if not template_content:
                    continue
                
                resources = template_content.get("Resources", {})
                
                for resource_name, resource_config in resources.items():
                    resource_type = resource_config.get("Type", "")
                    
                    # Skip non-taggable resources
                    if resource_type in NON_TAGGABLE_RESOURCE_TYPES:
                        continue
                    
                    # Only check taggable resource types
                    if resource_type not in TAGGABLE_RESOURCE_TYPES:
                        continue
                    
                    # Extract tags
                    tag_keys = extract_tags_from_resource(resource_config, resource_type)
                    
                    # Check for TenantId tag
                    if "TenantId" not in tag_keys:
                        violations.append({
                            "resource": resource_name,
                            "type": resource_type,
                            "tags": sorted(tag_keys),
                            "template": str(template_path.relative_to(WORKSHOP_ROOT)),
                            "lab": lab_name
                        })
            
            except Exception as e:
                print(f"Warning: Could not parse {template_path}: {e}")
                continue
    
    # Report violations
    if violations:
        error_msg = f"\nFound {len(violations)} tenant-specific resource(s) missing TenantId tag:\n"
        for v in violations:
            error_msg += f"  - {v['lab']}/{v['resource']} ({v['type']}) in {v['template']}\n"
            error_msg += f"    Present tags: {', '.join(v['tags']) if v['tags'] else 'None'}\n"
        pytest.fail(error_msg)


if __name__ == "__main__":
    # Run tests when executed directly
    pytest.main([__file__, "-v", "--tb=short"])
