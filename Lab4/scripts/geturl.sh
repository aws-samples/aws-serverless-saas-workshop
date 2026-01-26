#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# AWS Profile should be passed via --profile parameter

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified
STACK_NAME_PREFIX="serverless-saas-lab4"  # Default prefix for stack names
SHARED_STACK_NAME=""  # Will be set based on stack name prefix

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
    echo "  --stack-name <name>       Stack name prefix (default: serverless-saas-lab4)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS profile to use (optional, uses machine's default if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Get URLs with default settings"
    echo "  $0 --stack-name serverless-saas-lab4            # Get URLs for specific lab"
    echo "  $0 --region us-east-1                           # Get URLs from specific region"
    echo "  $0 --profile my-profile                         # Get URLs with specific AWS profile"
    echo "  $0 --stack-name my-lab --profile my-profile     # Get URLs with custom stack name and profile"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME_PREFIX=$2
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

# Set shared stack name based on prefix
SHARED_STACK_NAME="serverless-saas-shared-${STACK_NAME_PREFIX##*-}"

# If the prefix already contains "serverless-saas-shared", use it as-is
if [[ "$STACK_NAME_PREFIX" == serverless-saas-shared-* ]]; then
    SHARED_STACK_NAME="$STACK_NAME_PREFIX"
fi

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab4 Application URLs"
print_message "$BLUE" "=========================================="

PROFILE_ARG=$(get_profile_arg)
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || echo "")
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  print_message "$YELLOW" "Workshop is running in WorkshopStudio"
  ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || echo "")
  LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || echo "")
  APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text --region "$AWS_REGION" $PROFILE_ARG 2>/dev/null || echo "")

else
  # Check if stack exists before querying
  if aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG &>/dev/null; then
    ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
    APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  else
    print_message "$RED" "Error: Stack $SHARED_STACK_NAME not found in region $AWS_REGION"
    print_message "$YELLOW" "Make sure Lab4 is deployed first with: ./deployment.sh -s"
    exit 1
  fi
fi

if [ ! -z "$ADMIN_SITE_URL" ]; then
  print_message "$GREEN" "Admin site URL: https://$ADMIN_SITE_URL"
else
  print_message "$YELLOW" "Admin site URL: Not available"
fi

if [ ! -z "$LANDING_APP_SITE_URL" ]; then
  print_message "$GREEN" "Landing site URL: https://$LANDING_APP_SITE_URL"
else
  print_message "$YELLOW" "Landing site URL: Not available"
fi

if [ ! -z "$APP_SITE_URL" ]; then
  print_message "$GREEN" "App site URL: https://$APP_SITE_URL"
else
  print_message "$YELLOW" "App site URL: Not available"
fi

echo ""
