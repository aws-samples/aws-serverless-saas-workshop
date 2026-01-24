#!/usr/bin/env python3
"""Add tags to CloudFront distributions in YAML templates."""

import sys
import re

def add_cloudfront_tags(filepath, lab_number):
    """Add tags to CloudFront distributions in a YAML file."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Pattern to find PriceClass line in CloudFront distributions
    # We'll add tags right after PriceClass
    pattern = r"(        PriceClass: '[^']+')(\s*\n)"
    
    tags_block = f"""\\1
      Tags:
        - Key: Application
          Value: serverless-saas-workshop
        - Key: Lab
          Value: {lab_number}
        - Key: Environment
          Value: !Ref Environment
        - Key: Owner
          Value: !Ref Owner
        - Key: CostCenter
          Value: !Ref CostCenter\\2"""
    
    # Replace all occurrences
    new_content = re.sub(pattern, tags_block, content)
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    
    print(f"Updated {filepath}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python add_cloudfront_tags.py <filepath> <lab_number>")
        sys.exit(1)
    
    add_cloudfront_tags(sys.argv[1], sys.argv[2])
