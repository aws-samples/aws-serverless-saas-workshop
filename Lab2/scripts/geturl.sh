#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-west-2"
STACK_NAME="serverless-saas-lab2"
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to build AWS CLI profile argument
# Returns "--profile <profile>" if AWS_PROFILE is set, empty string otherwise
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab2)"
    echo "  --region <region>         AWS region (default: us-west-2)"
    echo "  --profile <profile>       AWS CLI profile name (optional, uses default profile if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Use default stack name and region"
    echo "  $0 --stack-name my-stack                        # Use custom stack name"
    echo "  $0 --region us-east-1                           # Use custom region"
    echo "  $0 --profile my-profile                         # Use custom AWS profile"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            print_message "$RED" "Unknown parameter: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab2 Application URLs"
print_message "$BLUE" "=========================================="
echo "Stack Name: $STACK_NAME"
echo "AWS Region: $AWS_REGION"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using machine's default profile)"
fi
echo ""

# Build profile argument
PROFILE_ARG=$(get_profile_arg)

# Check if running in Event Engine
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports $PROFILE_ARG --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null || echo "")

if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  print_message "$YELLOW" "Workshop is running in WorkshopStudio"
  ADMIN_SITE_URL=$(aws cloudformation list-exports $PROFILE_ARG --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation list-exports $PROFILE_ARG --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
else
  # Query CloudFormation stack outputs
  ADMIN_SITE_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
  LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
fi

# Display URLs
if [[ -z "$ADMIN_SITE_URL" ]] || [[ "$ADMIN_SITE_URL" == "None" ]]; then
  print_message "$RED" "Error: Could not retrieve application URLs"
  print_message "$YELLOW" "Make sure the stack '$STACK_NAME' is deployed in region '$AWS_REGION'"
  exit 1
fi

print_message "$GREEN" "Application URLs:"
print_message "$GREEN" "  Admin Site: https://${ADMIN_SITE_URL}"
print_message "$GREEN" "  Landing Site: https://${LANDING_APP_SITE_URL}"
echo ""
print_message "$YELLOW" "Note: Use these URLs to access the Lab2 applications"
