#!/bin/bash
# Simple script to add tagging parameters and tags to CloudFormation templates
# This script uses text manipulation to add tags without parsing YAML

# Parse command line arguments
AWS_PROFILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --profile PROFILE    AWS profile to use (optional, uses default if not specified)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Adding tags to Lab 2-7 templates..."
echo "Note: This script adds parameters and basic tag structures."
echo "Manual verification recommended after running."

# Function to add parameters to a template if not present
add_parameters() {
    local file=$1
    
    # Check if Environment parameter already exists
    if ! grep -q "Environment:" "$file"; then
        # Find the Parameters section or create it
        if grep -q "^Parameters:" "$file"; then
            # Add after existing Parameters section
            sed -i '' '/^Parameters:/a\
\  Environment:\
\    Type: String\
\    Default: dev\
\    AllowedValues:\
\      - dev\
\      - staging\
\      - prod\
\    Description: Deployment environment for the workshop\
\\
\  Owner:\
\    Type: String\
\    Default: workshop-participant\
\    Description: Owner identifier for resource tracking\
\\
\  CostCenter:\
\    Type: String\
\    Default: serverless-saas-workshop\
\    Description: Cost center for billing allocation\
' "$file"
        fi
    fi
}

# Process each lab
for lab in 2 3 4 5 6 7; do
    echo "Processing Lab${lab}..."
    
    # Process nested templates
    if [ -d "workshop/Lab${lab}/server/nested_templates" ]; then
        for template in workshop/Lab${lab}/server/nested_templates/*.yaml; do
            if [ -f "$template" ]; then
                echo "  - $(basename $template)"
                add_parameters "$template"
            fi
        done
    fi
done

echo "Done! Please review the changes and manually add Tags sections to resources."
echo "Use the tagging template at workshop/.kiro/tagging-template.yaml as reference."
