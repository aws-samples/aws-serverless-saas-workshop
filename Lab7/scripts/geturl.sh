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
AWS_PROFILE=""  # Optional, will use default profile if not provided
STACK_NAME="serverless-saas-lab7"

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
    echo "  --profile <profile>       AWS CLI profile name (optional, uses default if not provided)"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab7)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Use default stack name and region"
    echo "  $0 --profile serverless-saas-demo          # Use specific AWS profile"
    echo "  $0 --stack-name my-stack                    # Use custom stack name"
    echo "  $0 --region us-east-1                       # Use custom region"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --stack-name)
            STACK_NAME=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
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

# Build AWS CLI profile argument if profile is provided
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab7 - Cost Attribution Information"
print_message "$BLUE" "=========================================="
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
fi
echo "Stack Name: $STACK_NAME"
echo "AWS Region: $AWS_REGION"
echo ""

# Check if stack exists
print_message "$YELLOW" "Checking CloudFormation stack..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" $PROFILE_ARG &> /dev/null; then
    print_message "$RED" "Error: Stack '$STACK_NAME' not found"
    print_message "$YELLOW" "Deploy the stack first with: ./deployment.sh --stack-name $STACK_NAME --region $AWS_REGION"
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
print_message "$YELLOW" "Retrieving stack outputs..."

CUR_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_ARG \
    --query "Stacks[0].Outputs[?OutputKey=='CURBucketname'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Display results
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab7 Cost Attribution Resources"
print_message "$GREEN" "=========================================="
echo ""

if [[ -n "$CUR_BUCKET" ]] && [[ "$CUR_BUCKET" != "None" ]]; then
    print_message "$BLUE" "CUR S3 Bucket:"
    print_message "$GREEN" "  ${CUR_BUCKET}"
    echo ""
else
    print_message "$YELLOW" "  CUR Bucket: Not available"
    echo ""
fi

print_message "$BLUE" "DynamoDB Attribution Table:"
print_message "$GREEN" "  TenantCostAndUsageAttribution-lab7"
echo ""

print_message "$BLUE" "Cost Attribution Lambda Functions:"
print_message "$GREEN" "  - serverless-saas-lab7-dynamodb-cost"
print_message "$GREEN" "  - serverless-saas-lab7-lambda-cost"
echo ""

print_message "$BLUE" "View attribution data:"
print_message "$YELLOW" "  aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7 --region $AWS_REGION"
echo ""

print_message "$BLUE" "Query specific tenant data:"
print_message "$YELLOW" "  aws dynamodb query --table-name TenantCostAndUsageAttribution-lab7 \\"
print_message "$YELLOW" "    --key-condition-expression \"#d = :date\" \\"
print_message "$YELLOW" "    --expression-attribute-names '{\"#d\":\"Date\"}' \\"
print_message "$YELLOW" "    --expression-attribute-values '{\":date\":{\"N\":\"20221001\"}}' \\"
print_message "$YELLOW" "    --region $AWS_REGION"
echo ""

print_message "$BLUE" "Athena Database:"
print_message "$GREEN" "  costexplorerdb-lab7"
echo ""

print_message "$BLUE" "Glue Crawler:"
print_message "$GREEN" "  AWSCURCrawler-Multi-tenant-lab7"
echo ""

print_message "$GREEN" "=========================================="
print_message "$YELLOW" "Note: Attribution Lambdas run every 5 minutes to collect cost data"
print_message "$GREEN" "=========================================="
