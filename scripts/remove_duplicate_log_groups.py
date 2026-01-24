#!/usr/bin/env python3
"""
Script to remove duplicate log group definitions from templates.
"""

import re
from pathlib import Path

def remove_duplicates(template_path):
    """Remove duplicate log group definitions."""
    
    with open(template_path, 'r') as f:
        content = f.read()
    
    # Find all log group sections
    log_group_pattern = r'  # CloudWatch Log Groups with 60-day retention\n((?:  \w+LogGroup:.*?\n(?:    .*?\n)*?)+)'
    
    matches = list(re.finditer(log_group_pattern, content, re.MULTILINE))
    
    if len(matches) <= 1:
        print(f"  No duplicates found in {template_path.name}")
        return False
    
    print(f"  Found {len(matches)} log group sections in {template_path.name}, removing duplicates...")
    
    # Keep only the first occurrence, remove the rest
    for match in reversed(matches[1:]):
        content = content[:match.start()] + content[match.end():]
    
    with open(template_path, 'w') as f:
        f.write(content)
    
    print(f"  ✓ Cleaned {template_path.name}")
    return True

def main():
    """Main function."""
    
    script_dir = Path(__file__).parent
    workshop_dir = script_dir.parent
    
    templates = [
        workshop_dir / "Lab1/server/template.yaml",
        workshop_dir / "Lab2/server/nested_templates/lambdafunctions.yaml",
        workshop_dir / "Lab3/server/tenant-template.yaml",
        workshop_dir / "Lab4/server/tenant-template.yaml",
        workshop_dir / "Lab5/server/tenant-template.yaml",
        workshop_dir / "Lab6/server/tenant-template.yaml",
        workshop_dir / "Lab7/template.yaml",
    ]
    
    print("Removing duplicate log group definitions...\n")
    
    cleaned = 0
    for template_path in templates:
        if template_path.exists():
            if remove_duplicates(template_path):
                cleaned += 1
    
    print(f"\n✓ Cleaned {cleaned} templates.")

if __name__ == "__main__":
    main()
