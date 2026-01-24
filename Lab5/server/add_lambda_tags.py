#!/usr/bin/env python3
"""
Script to add tags to all Lambda functions in lambdafunctions.yaml
"""

import re

# Read the file
with open('nested_templates/lambdafunctions.yaml', 'r') as f:
    content = f.read()

# Tag template to add
tags_template = """      Tags:
        Application: serverless-saas-workshop
        Lab: lab5
        Environment: !Ref Environment
        Owner: !Ref Owner
        CostCenter: !Ref CostCenter
"""

# Find all Lambda functions that don't have tags
# Pattern: Find Lambda function definitions followed by Environment section but no Tags section
pattern = r'(  \w+Function:\n    Type: AWS::Serverless::Function\n.*?Environment:\n        Variables:.*?\n(?:          \w+:.*?\n)*)(  \n  #|\n  \w+Function:|\nOutputs:)'

def add_tags_if_missing(match):
    function_block = match.group(1)
    next_section = match.group(2)
    
    # Check if this function already has tags
    if 'Tags:' in function_block:
        return match.group(0)  # Return unchanged
    
    # Add tags before the next section
    return function_block + tags_template + next_section

# Apply the replacement
new_content = re.sub(pattern, add_tags_if_missing, content, flags=re.DOTALL)

# Write back
with open('nested_templates/lambdafunctions.yaml', 'w') as f:
    f.write(new_content)

print("Tags added to Lambda functions successfully!")
