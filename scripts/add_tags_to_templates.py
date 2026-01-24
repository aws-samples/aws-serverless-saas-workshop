#!/usr/bin/env python3
"""
Script to add resource tags to CloudFormation templates for Labs 2-7.
This script adds Parameters section and Tags to all AWS resources.
"""

import yaml
import sys
from pathlib import Path
from typing import Dict, Any, List

# Tag format mappings by resource type
KEY_VALUE_FORMAT = [
    'AWS::Serverless::Function',
    'AWS::Lambda::Function',
    'AWS::Serverless::Api',
    'AWS::ApiGateway::RestApi',
]

KEY_VALUE_ARRAY_FORMAT = [
    'AWS::DynamoDB::Table',
    'AWS::S3::Bucket',
    'AWS::IAM::Role',
    'AWS::Logs::LogGroup',
    'AWS::Events::Rule',
    'AWS::CodePipeline::Pipeline',
    'AWS::CodeCommit::Repository',
    'AWS::SQS::Queue',
    'AWS::SNS::Topic',
]

USERPOOL_TAGS_FORMAT = ['AWS::Cognito::UserPool']

NO_TAGS_SUPPORT = [
    'AWS::Lambda::LayerVersion',
    'AWS::Serverless::LayerVersion',
    'AWS::IAM::Policy',
    'AWS::Cognito::UserPoolClient',
    'AWS::ApiGateway::Stage',
    'AWS::ApiGateway::Deployment',
    'AWS::Lambda::Permission',
    'AWS::CloudFront::CloudFrontOriginAccessIdentity',
    'AWS::CloudFront::Distribution',
    'AWS::S3::BucketPolicy',
    'AWS::ApiGateway::Account',
    'AWS::Serverless::Application',  # Nested stacks - tags passed via parameters
]

def get_lab_number(file_path: Path) -> str:
    """Extract lab number from file path."""
    parts = file_path.parts
    for part in parts:
        if part.startswith('Lab'):
            return part.lower()
    return 'unknown'

def create_key_value_tags(lab: str) -> Dict[str, str]:
    """Create tags in key-value format."""
    return {
        'Application': 'serverless-saas-workshop',
        'Lab': lab,
        'Environment': '!Ref Environment',
        'Owner': '!Ref Owner',
        'CostCenter': '!Ref CostCenter',
    }

def create_key_value_array_tags(lab: str) -> List[Dict[str, str]]:
    """Create tags in key-value array format."""
    return [
        {'Key': 'Application', 'Value': 'serverless-saas-workshop'},
        {'Key': 'Lab', 'Value': lab},
        {'Key': 'Environment', 'Value': '!Ref Environment'},
        {'Key': 'Owner', 'Value': '!Ref Owner'},
        {'Key': 'CostCenter', 'Value': '!Ref CostCenter'},
    ]

def add_tags_to_resource(resource: Dict[str, Any], resource_type: str, lab: str) -> bool:
    """Add tags to a resource based on its type. Returns True if tags were added."""
    if resource_type in NO_TAGS_SUPPORT:
        return False
    
    properties = resource.get('Properties', {})
    
    # Check if tags already exist
    if 'Tags' in properties or 'UserPoolTags' in properties:
        return False
    
    if resource_type in KEY_VALUE_FORMAT:
        properties['Tags'] = create_key_value_tags(lab)
        return True
    elif resource_type in KEY_VALUE_ARRAY_FORMAT:
        properties['Tags'] = create_key_value_array_tags(lab)
        return True
    elif resource_type in USERPOOL_TAGS_FORMAT:
        properties['UserPoolTags'] = create_key_value_tags(lab)
        return True
    
    return False

def add_parameters_to_template(template: Dict[str, Any]) -> bool:
    """Add tagging parameters to template if not present. Returns True if added."""
    if 'Parameters' not in template:
        template['Parameters'] = {}
    
    params = template['Parameters']
    added = False
    
    if 'Environment' not in params:
        params['Environment'] = {
            'Type': 'String',
            'Default': 'dev',
            'AllowedValues': ['dev', 'staging', 'prod'],
            'Description': 'Deployment environment for the workshop'
        }
        added = True
    
    if 'Owner' not in params:
        params['Owner'] = {
            'Type': 'String',
            'Default': 'workshop-participant',
            'Description': 'Owner identifier for resource tracking'
        }
        added = True
    
    if 'CostCenter' not in params:
        params['CostCenter'] = {
            'Type': 'String',
            'Default': 'serverless-saas-workshop',
            'Description': 'Cost center for billing allocation'
        }
        added = True
    
    return added

def process_template(file_path: Path) -> Dict[str, int]:
    """Process a single template file and add tags."""
    stats = {'resources_tagged': 0, 'resources_skipped': 0, 'parameters_added': 0}
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Parse YAML
        template = yaml.safe_load(content)
        
        if not template or 'Resources' not in template:
            return stats
        
        # Add parameters
        if add_parameters_to_template(template):
            stats['parameters_added'] = 1
        
        # Get lab number
        lab = get_lab_number(file_path)
        
        # Process resources
        for resource_name, resource in template.get('Resources', {}).items():
            resource_type = resource.get('Type', '')
            if add_tags_to_resource(resource, resource_type, lab):
                stats['resources_tagged'] += 1
            elif resource_type in NO_TAGS_SUPPORT:
                stats['resources_skipped'] += 1
        
        # Write back
        with open(file_path, 'w') as f:
            yaml.dump(template, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        
        return stats
    
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
        return stats

def main():
    """Main function to process all templates."""
    workshop_dir = Path(__file__).parent.parent
    
    # Process Labs 2-7
    total_stats = {'resources_tagged': 0, 'resources_skipped': 0, 'parameters_added': 0, 'files_processed': 0}
    
    for lab_num in range(2, 8):
        lab_dir = workshop_dir / f'Lab{lab_num}' / 'server'
        
        if not lab_dir.exists():
            continue
        
        # Process main template
        main_template = lab_dir / 'template.yaml'
        if main_template.exists():
            print(f"Processing {main_template}")
            stats = process_template(main_template)
            for key in stats:
                total_stats[key] += stats[key]
            total_stats['files_processed'] += 1
        
        # Process nested templates
        nested_dir = lab_dir / 'nested_templates'
        if nested_dir.exists():
            for nested_template in nested_dir.glob('*.yaml'):
                print(f"Processing {nested_template}")
                stats = process_template(nested_template)
                for key in stats:
                    total_stats[key] += stats[key]
                total_stats['files_processed'] += 1
    
    print("\n=== Summary ===")
    print(f"Files processed: {total_stats['files_processed']}")
    print(f"Resources tagged: {total_stats['resources_tagged']}")
    print(f"Resources skipped (no tag support): {total_stats['resources_skipped']}")
    print(f"Templates with parameters added: {total_stats['parameters_added']}")

if __name__ == '__main__':
    main()
