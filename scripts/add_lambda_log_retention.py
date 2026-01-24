#!/usr/bin/env python3
"""
Script to add CloudWatch Log Groups with 60-day retention for all Lambda functions
across Labs 1-7 in the Serverless SaaS Workshop.
"""

import re
import sys
from pathlib import Path

def add_log_groups_to_template(template_path, lab_name):
    """Add log groups with 60-day retention for Lambda functions in a template."""
    
    with open(template_path, 'r') as f:
        content = f.read()
    
    # Find all Lambda function logical IDs
    function_pattern = r'^  (\w+Function):\s*\n\s+Type:\s+AWS::Serverless::Function'
    functions = re.findall(function_pattern, content, re.MULTILINE)
    
    if not functions:
        print(f"  No Lambda functions found in {template_path}")
        return False
    
    print(f"  Found {len(functions)} Lambda functions: {', '.join(functions)}")
    
    # Check if log groups already exist
    existing_log_groups = re.findall(r'(\w+)LogGroup:', content)
    
    # Build log group definitions
    log_groups_section = "\n  # CloudWatch Log Groups with 60-day retention\n"
    
    for func_name in functions:
        log_group_name = f"{func_name}LogGroup"
        
        if log_group_name in existing_log_groups:
            print(f"    Skipping {log_group_name} - already exists")
            continue
        
        log_groups_section += f"""  {log_group_name}:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub /aws/lambda/${{AWS::StackName}}-{func_name}
      RetentionInDays: 60
      Tags:
        - Key: Application
          Value: serverless-saas-workshop
        - Key: Lab
          Value: {lab_name}

"""
    
    # Find the Resources section and add log groups after it
    resources_match = re.search(r'^Resources:\s*\n', content, re.MULTILINE)
    if not resources_match:
        print(f"  ERROR: Could not find Resources section in {template_path}")
        return False
    
    # Insert log groups right after Resources:
    insert_pos = resources_match.end()
    new_content = content[:insert_pos] + log_groups_section + content[insert_pos:]
    
    # Add DependsOn to each Lambda function
    for func_name in functions:
        log_group_name = f"{func_name}LogGroup"
        
        # Find the function definition
        func_pattern = rf'^  {func_name}:\s*\n(\s+Type:\s+AWS::Serverless::Function\s*\n)'
        func_match = re.search(func_pattern, new_content, re.MULTILINE)
        
        if func_match:
            # Check if DependsOn already exists
            depends_on_pattern = rf'^  {func_name}:.*?\n\s+DependsOn:'
            if re.search(depends_on_pattern, new_content, re.MULTILINE | re.DOTALL):
                # DependsOn exists, need to convert to list or add to existing list
                # For simplicity, we'll skip this case
                print(f"    Note: {func_name} already has DependsOn, skipping dependency addition")
            else:
                # Add DependsOn before Type
                replacement = f"  {func_name}:\n    DependsOn: {log_group_name}\n{func_match.group(1)}"
                new_content = re.sub(func_pattern, replacement, new_content, count=1, flags=re.MULTILINE)
    
    # Write back
    with open(template_path, 'w') as f:
        f.write(new_content)
    
    print(f"  ✓ Updated {template_path}")
    return True

def main():
    """Main function to process all lab templates."""
    
    script_dir = Path(__file__).parent
    workshop_dir = script_dir.parent
    
    templates_to_process = [
        (workshop_dir / "Lab1/server/template.yaml", "lab1"),
        (workshop_dir / "Lab2/server/nested_templates/lambdafunctions.yaml", "lab2"),
        (workshop_dir / "Lab3/server/tenant-template.yaml", "lab3"),
        (workshop_dir / "Lab4/server/tenant-template.yaml", "lab4"),
        (workshop_dir / "Lab5/server/tenant-template.yaml", "lab5"),
        (workshop_dir / "Lab6/server/tenant-template.yaml", "lab6"),
        (workshop_dir / "Lab7/template.yaml", "lab7"),
    ]
    
    print("Adding CloudWatch Log Groups with 60-day retention to Lambda functions...\n")
    
    updated_count = 0
    for template_path, lab_name in templates_to_process:
        if not template_path.exists():
            print(f"⚠ Skipping {template_path} - file not found")
            continue
        
        print(f"Processing {template_path}...")
        if add_log_groups_to_template(template_path, lab_name):
            updated_count += 1
    
    print(f"\n✓ Complete! Updated {updated_count} templates.")

if __name__ == "__main__":
    main()
