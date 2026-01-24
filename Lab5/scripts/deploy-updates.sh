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
AWS_REGION="us-west-2"
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
    echo "  --region <region>         AWS region (default: us-west-2)"
    echo "  --profile <profile>       AWS CLI profile to use (optional, uses default if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Description:"
    echo "  This script deploys code changes to the shared services after initial setup."
    echo "  It validates Python code, syncs Lambda function changes, and displays URLs."
    echo ""
    echo "Examples:"
    echo "  $0                                          # Deploy updates with defaults"
    echo "  $0 --region us-east-1                       # Deploy to specific region"
    echo "  $0 --stack-name my-stack                    # Deploy to custom stack"
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

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-updates-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab5 Deploy Updates Script"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
echo "AWS Region: $AWS_REGION"
echo "Stack Name: $SHARED_STACK_NAME"
echo ""

# Record start time
START_TIME=$(date +%s)

# Navigate to server directory
print_message "$YELLOW" "Step 1: Navigating to server directory..."
cd ../server || {
    print_message "$RED" "Error: Could not navigate to server directory"
    exit 1
}
print_message "$GREEN" "✓ In server directory"
echo ""

# Clean up previous build artifacts
print_message "$YELLOW" "Step 2: Cleaning up previous build artifacts..."
rm -rf .aws-sam/
print_message "$GREEN" "✓ Build artifacts cleaned"
echo ""

# Validate Python code
print_message "$YELLOW" "Step 3: Validating Python code with pylint..."

# Use virtual environment Python if available
if [ -f "../../.venv_py313/bin/python" ]; then
  PYTHON_CMD="../../.venv_py313/bin/python"
else
  PYTHON_CMD="python3"
fi

if command -v pylint &> /dev/null; then
  $PYTHON_CMD -m pylint -E -d E0401,E0606 $(find . -iname "*.py" -not -path "./.aws-sam/*" -not -path "./TenantPipeline/node_modules/*") || {
      print_message "$RED" "Error: Code validation failed. Please fix errors and retry."
      exit 1
  }
  print_message "$GREEN" "✓ Code validation passed"
else
  print_message "$YELLOW" "Warning: pylint not installed, skipping code validation"
fi
echo ""

# Deploy shared services changes
print_message "$YELLOW" "Step 4: Deploying shared services changes..."
print_message "$YELLOW" "  Syncing Lambda functions to stack: $SHARED_STACK_NAME"

# Build SAM sync command with optional profile
PROFILE_ARG=$(get_profile_arg)
if [[ -n "$AWS_PROFILE" ]]; then
  echo Y | sam sync \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    -t shared-template.yaml \
    --code \
    --resource-id LambdaFunctions/CreateTenantAdminUserFunction \
    --resource-id LambdaFunctions/ProvisionTenantFunction \
    -u || {
      print_message "$RED" "Error: SAM sync failed"
      exit 1
  }
else
  echo Y | sam sync \
    --stack-name "$SHARED_STACK_NAME" \
    --region "$AWS_REGION" \
    -t shared-template.yaml \
    --code \
    --resource-id LambdaFunctions/CreateTenantAdminUserFunction \
    --resource-id LambdaFunctions/ProvisionTenantFunction \
    -u || {
      print_message "$RED" "Error: SAM sync failed"
      exit 1
  }
fi

print_message "$GREEN" "✓ Shared services updated successfully"
echo ""

# Navigate back to scripts directory
cd ../scripts || exit

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display deployment summary
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Deploy Updates Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Duration: ${DURATION} seconds"
echo ""

# Display URLs
print_message "$BLUE" "Retrieving application URLs..."
if [[ -n "$AWS_PROFILE" ]]; then
  ./geturl.sh --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"
else
  ./geturl.sh --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION"
fi

echo ""
print_message "$GREEN" "Log file: $LOG_FILE"
