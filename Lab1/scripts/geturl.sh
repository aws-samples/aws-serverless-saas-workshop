#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# AWS Profile should be passed via --profile parameter

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-west-2"
STACK_NAME="serverless-saas-lab1"

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
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab1)"
    echo "  --region <region>         AWS region (default: us-west-2)"
    echo "  --profile <profile>       AWS profile (optional, uses machine's default if not provided)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Use default stack name and region with default AWS profile"
    echo "  $0 --stack-name my-stack                    # Use custom stack name"
    echo "  $0 --region us-east-1                       # Use custom region"
    echo "  $0 --profile my-profile                     # Use specific AWS profile"
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
print_message "$BLUE" "Lab1 - Retrieve Application URLs"
print_message "$BLUE" "=========================================="
echo "Stack Name: $STACK_NAME"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using machine's default)"
fi
echo "AWS Region: $AWS_REGION"
echo ""

# Build AWS CLI profile argument if profile is specified
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Check if stack exists
print_message "$YELLOW" "Checking CloudFormation stack..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG &> /dev/null; then
    print_message "$RED" "Error: Stack '$STACK_NAME' not found"
    print_message "$YELLOW" "Deploy the stack first with: ./deployment.sh -s -c --stack-name $STACK_NAME"
    exit 1
fi

# Get stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "Stacks[0].StackStatus" \
    --output text)

if [[ "$STACK_STATUS" != "CREATE_COMPLETE" ]] && [[ "$STACK_STATUS" != "UPDATE_COMPLETE" ]]; then
    print_message "$YELLOW" "Warning: Stack status is $STACK_STATUS"
fi

print_message "$GREEN" "✓ Stack found"
echo ""

# Retrieve CloudFormation outputs
print_message "$YELLOW" "Retrieving application URLs..."

APP_SITE_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" \
    --output text 2>/dev/null || echo "")

API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "Stacks[0].Outputs[?OutputKey=='APIGatewayURL'].OutputValue" \
    --output text 2>/dev/null || echo "")

APP_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Display results
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab1 Application URLs"
print_message "$GREEN" "=========================================="
echo ""

if [[ -n "$APP_SITE_URL" ]] && [[ "$APP_SITE_URL" != "None" ]]; then
    print_message "$BLUE" "Application Site:"
    print_message "$GREEN" "  https://${APP_SITE_URL}"
    echo ""
else
    print_message "$YELLOW" "  Application Site: Not deployed yet"
    print_message "$YELLOW" "  Deploy client with: ./deployment.sh -c --stack-name $STACK_NAME"
    echo ""
fi

if [[ -n "$API_GATEWAY_URL" ]] && [[ "$API_GATEWAY_URL" != "None" ]]; then
    print_message "$BLUE" "API Gateway URL:"
    print_message "$GREEN" "  ${API_GATEWAY_URL}"
    echo ""
else
    print_message "$YELLOW" "  API Gateway URL: Not available"
fi

if [[ -n "$APP_BUCKET" ]] && [[ "$APP_BUCKET" != "None" ]]; then
    print_message "$BLUE" "S3 Bucket:"
    print_message "$GREEN" "  ${APP_BUCKET}"
    echo ""
fi

print_message "$GREEN" "=========================================="
