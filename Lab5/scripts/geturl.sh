#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# AWS Profile should be passed via --profile parameter

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
SHARED_STACK_NAME="serverless-saas-workshop-shared-lab5"
AWS_PROFILE=""

# Function to build AWS CLI profile argument
# Returns "--profile <profile>" if PROFILE is set, empty string otherwise
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-workshop-shared-lab5)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS CLI profile to use (optional, uses default if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Get URLs with defaults"
    echo "  $0 --region us-east-1                       # Get URLs from specific region"
    echo "  $0 --stack-name my-stack                    # Get URLs from custom stack"
    echo "  $0 --profile serverless-saas-demo           # Use specific AWS profile"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            SHARED_STACK_NAME=$2
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
print_message "$BLUE" "Lab5 Application URLs"
print_message "$BLUE" "=========================================="
echo "Stack Name: $SHARED_STACK_NAME"
echo "AWS Region: $AWS_REGION"
echo ""

# Check for Event Engine pre-provisioned resources
print_message "$YELLOW" "Checking for Event Engine environment..."
PROFILE_ARG=$(get_profile_arg)
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports $PROFILE_ARG --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null || echo "")

if [[ ! -z "$PREPROVISIONED_ADMIN_SITE" ]]; then
  print_message "$GREEN" "✓ Workshop is running in WorkshopStudio/Event Engine"
  echo ""
  
  ADMIN_SITE_URL=$(aws cloudformation list-exports $PROFILE_ARG --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation list-exports $PROFILE_ARG --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
  APP_SITE_URL=$(aws cloudformation list-exports $PROFILE_ARG --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)
else
  print_message "$GREEN" "✓ Running in standard AWS account"
  echo ""
  
  # Verify stack exists
  print_message "$YELLOW" "Retrieving stack outputs..."
  STACK_STATUS=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "")
  
  if [[ -z "$STACK_STATUS" ]]; then
    print_message "$RED" "Error: Stack '$SHARED_STACK_NAME' not found in region '$AWS_REGION'"
    print_message "$YELLOW" "Make sure the stack is deployed first with: ./deployment.sh -s -c"
    exit 1
  fi
  
  if [[ "$STACK_STATUS" != "CREATE_COMPLETE" ]] && [[ "$STACK_STATUS" != "UPDATE_COMPLETE" ]]; then
    print_message "$YELLOW" "Warning: Stack status is '$STACK_STATUS'"
    print_message "$YELLOW" "Stack may not be fully deployed yet"
    echo ""
  fi
  
  ADMIN_SITE_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
  LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  APP_SITE_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  ADMIN_API_URL=$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
fi

# Display URLs
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Application URLs:"
print_message "$GREEN" "=========================================="

if [[ ! -z "$ADMIN_SITE_URL" ]] && [[ "$ADMIN_SITE_URL" != "None" ]]; then
  print_message "$BLUE" "Admin Site:   https://$ADMIN_SITE_URL"
else
  print_message "$YELLOW" "Admin Site:   Not available"
fi

if [[ ! -z "$LANDING_APP_SITE_URL" ]] && [[ "$LANDING_APP_SITE_URL" != "None" ]]; then
  print_message "$BLUE" "Landing Site: https://$LANDING_APP_SITE_URL"
else
  print_message "$YELLOW" "Landing Site: Not available"
fi

if [[ ! -z "$APP_SITE_URL" ]] && [[ "$APP_SITE_URL" != "None" ]]; then
  print_message "$BLUE" "App Site:     https://$APP_SITE_URL"
else
  print_message "$YELLOW" "App Site:     Not available"
fi

if [[ ! -z "$ADMIN_API_URL" ]] && [[ "$ADMIN_API_URL" != "None" ]]; then
  echo ""
  print_message "$BLUE" "Admin API:    $ADMIN_API_URL"
fi

echo ""
print_message "$GREEN" "=========================================="
