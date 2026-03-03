#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Optional, will use default profile if not provided
MAIN_STACK_NAME="serverless-saas-lab7"
TENANT_STACK_NAME="stack-pooled-lab7"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

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
    echo "  --profile <profile>            AWS CLI profile name (optional, uses default if not provided)"
    echo "  --region <region>              AWS region (default: us-east-1)"
    echo "  --main-stack <name>            Main stack name (default: serverless-saas-lab7)"
    echo "  --tenant-stack <name>          Tenant stack name (default: stack-pooled-lab7)"
    echo "  --help                         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Use default values"
    echo "  $0 --profile serverless-saas-demo              # Use specific AWS profile"
    echo "  $0 --region us-east-1                           # Use custom region"
    echo "  $0 --main-stack my-lab7-stack                   # Use custom main stack name"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --main-stack)
            MAIN_STACK_NAME=$2
            shift 2
            ;;
        --tenant-stack)
            TENANT_STACK_NAME=$2
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

# Validate prerequisites
print_message "$YELLOW" "Validating prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_message "$RED" "Error: AWS CLI is not installed"
    exit 1
fi

# Check SAM CLI
if ! command -v sam &> /dev/null; then
    print_message "$RED" "Error: AWS SAM CLI is not installed"
    exit 1
fi

# Check Python
if ! command -v python3 &> /dev/null; then
    print_message "$RED" "Error: Python 3 is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity $PROFILE_ARG &> /dev/null; then
    print_message "$RED" "Error: AWS credentials are not configured"
    exit 1
fi

print_message "$GREEN" "✓ All prerequisites validated"
echo ""

# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab7-deployment.log"
else
    # Individual Lab Mode: Create timestamped directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_DIR="$SCRIPT_DIR/logs/$TIMESTAMP"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/deployment.log"
fi

# Redirect all output to log file and console
# Skip if running in test mode (test framework handles logging)
if [[ -z "$E2E_TEST_MODE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

# Use virtual environment Python if available
if [ -f "$LAB_DIR/../.venv_py313/bin/python" ]; then
  export PATH="$LAB_DIR/../.venv_py313/bin:$PATH"
fi

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab7 Deployment Script - Provisioned"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
fi
echo "AWS Region: $AWS_REGION"
echo "Main Stack: $MAIN_STACK_NAME"
echo "Tenant Stack: $TENANT_STACK_NAME"
echo ""

# Get AWS Account ID for generating unique bucket names
ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_ARG --query Account --output text)
ACCOUNT_HASH=$(printf '%s' "serverless-saas-${ACCOUNT_ID}" | shasum -a 256 | cut -c1-8)

# Step 1: Deploy main Lab7 stack
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Deploying main Lab7 stack"
print_message "$BLUE" "=========================================="

# Generate a globally unique SAM S3 bucket name using a salted hash of the account ID.
# This avoids exposing the account ID in the bucket name while ensuring uniqueness.
SAM_BUCKET="sam-bootstrap-lab7-${ACCOUNT_HASH}"

print_message "$YELLOW" "  Checking SAM deployment bucket: $SAM_BUCKET"
if ! aws s3 ls "s3://${SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
  print_message "$YELLOW" "  Bucket does not exist, creating: $SAM_BUCKET"
  aws s3 mb "s3://${SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
  
  # Add encryption to the bucket
  aws s3api put-bucket-encryption \
    $PROFILE_ARG \
    --bucket "$SAM_BUCKET" \
    --region "$AWS_REGION" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  print_message "$GREEN" "  ✓ Created SAM deployment bucket: $SAM_BUCKET"
else
  print_message "$GREEN" "  ✓ SAM deployment bucket exists: $SAM_BUCKET"
fi

sam build -t "$LAB_DIR/template.yaml"
if sam deploy --config-file "$LAB_DIR/samconfig.toml" --region="$AWS_REGION" --stack-name="$MAIN_STACK_NAME" --s3-bucket "$SAM_BUCKET" $PROFILE_ARG 2>&1 | tee /dev/tty | grep -q "No changes to deploy"; then
  print_message "$GREEN" "✓ Main stack is up to date (no changes to deploy)"
else
  print_message "$GREEN" "✓ Main stack deployed"
fi
echo ""

# Step 2: Upload sample CUR data
print_message "$YELLOW" "Step 2: Uploading sample CUR data..."
CUR_BUCKET=$(aws cloudformation list-exports --region="$AWS_REGION" $PROFILE_ARG --query "Exports[?Name=='CURBucketname'].Value" --output text)
AWSCURInitializerFunctionName=$(aws cloudformation list-exports --region="$AWS_REGION" $PROFILE_ARG --query "Exports[?Name=='AWSCURInitializerFunctionName'].Value" --output text)

if [[ -z "$CUR_BUCKET" ]] || [[ "$CUR_BUCKET" == "None" ]]; then
    print_message "$RED" "Error: Could not retrieve CUR bucket name from stack exports"
    exit 1
fi

aws s3 cp "$LAB_DIR/SampleCUR/" s3://$CUR_BUCKET/curoutput/year=2022/month=10/ --recursive --region="$AWS_REGION" $PROFILE_ARG
print_message "$GREEN" "✓ Sample CUR data uploaded"
echo ""

# Step 3: Initialize CUR crawler
print_message "$YELLOW" "Step 3: Initializing CUR crawler..."
aws lambda invoke --function-name $AWSCURInitializerFunctionName --region="$AWS_REGION" $PROFILE_ARG "$LAB_DIR/lambdaoutput.json"
rm -f "$LAB_DIR/lambdaoutput.json"
print_message "$GREEN" "✓ CUR crawler initialized"
echo ""

# Step 3.5: Wait for Glue Crawler to complete
print_message "$YELLOW" "Step 3.5: Waiting for Glue Crawler to complete..."
echo "The Glue Crawler needs to catalog the CUR data before Athena can query it."
echo "This typically takes 2-5 minutes. Checking crawler status..."

CRAWLER_NAME="AWSCURCrawler-Multi-tenant-lab7"
MAX_WAIT_TIME=600  # 10 minutes max
WAIT_INTERVAL=15   # Check every 15 seconds
ELAPSED_TIME=0

while [ $ELAPSED_TIME -lt $MAX_WAIT_TIME ]; do
  CRAWLER_STATE=$(aws glue get-crawler --name "$CRAWLER_NAME" --region="$AWS_REGION" $PROFILE_ARG --query 'Crawler.State' --output text 2>/dev/null || echo "UNKNOWN")
  
  if [ "$CRAWLER_STATE" == "READY" ]; then
    # Check if crawler has run at least once
    LAST_CRAWL=$(aws glue get-crawler --name "$CRAWLER_NAME" --region="$AWS_REGION" $PROFILE_ARG --query 'Crawler.LastCrawl.Status' --output text 2>/dev/null || echo "NONE")
    
    if [ "$LAST_CRAWL" == "SUCCEEDED" ]; then
      print_message "$GREEN" "✓ Glue Crawler completed successfully"
      
      # Verify the table was created
      TABLE_EXISTS=$(aws glue get-table --database-name costexplorerdb-lab7 --name curoutput --region="$AWS_REGION" $PROFILE_ARG --query 'Table.Name' --output text 2>/dev/null || echo "")
      
      if [ -n "$TABLE_EXISTS" ]; then
        print_message "$GREEN" "✓ Athena table 'curoutput' created successfully"
        break
      else
        print_message "$YELLOW" "  Waiting for Athena table to be available..."
      fi
    elif [ "$LAST_CRAWL" == "FAILED" ]; then
      print_message "$RED" "Error: Glue Crawler failed"
      print_message "$YELLOW" "Check CloudWatch logs for crawler: $CRAWLER_NAME"
      exit 1
    fi
  fi
  
  echo "  Crawler state: $CRAWLER_STATE (elapsed: ${ELAPSED_TIME}s)"
  sleep $WAIT_INTERVAL
  ELAPSED_TIME=$((ELAPSED_TIME + WAIT_INTERVAL))
done

if [ $ELAPSED_TIME -ge $MAX_WAIT_TIME ]; then
  print_message "$RED" "Warning: Glue Crawler did not complete within $MAX_WAIT_TIME seconds"
  print_message "$YELLOW" "The crawler may still be running. Attribution Lambdas may fail until it completes."
  print_message "$YELLOW" "You can check crawler status with:"
  print_message "$YELLOW" "  aws glue get-crawler --name $CRAWLER_NAME --region $AWS_REGION $PROFILE_ARG"
fi
echo ""

# Step 4: Deploy tenant stack for cost attribution demo
print_message "$YELLOW" "Step 4: Deploying tenant stack ($TENANT_STACK_NAME)..."

# Generate a globally unique SAM S3 bucket name for tenant stack
TENANT_SAM_BUCKET="sam-bootstrap-tenant-lab7-${ACCOUNT_HASH}"

print_message "$YELLOW" "  Checking SAM deployment bucket: $TENANT_SAM_BUCKET"
if ! aws s3 ls "s3://${TENANT_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
  print_message "$YELLOW" "  Bucket does not exist, creating: $TENANT_SAM_BUCKET"
  aws s3 mb "s3://${TENANT_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
  
  # Add encryption to the bucket
  aws s3api put-bucket-encryption \
    $PROFILE_ARG \
    --bucket "$TENANT_SAM_BUCKET" \
    --region "$AWS_REGION" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  print_message "$GREEN" "  ✓ Created SAM deployment bucket: $TENANT_SAM_BUCKET"
else
  print_message "$GREEN" "  ✓ SAM deployment bucket exists: $TENANT_SAM_BUCKET"
fi

sam build --template-file "$LAB_DIR/tenant-template.yaml"
if sam deploy --config-file "$LAB_DIR/tenant-samconfig.toml" --region="$AWS_REGION" --stack-name="$TENANT_STACK_NAME" --s3-bucket "$TENANT_SAM_BUCKET" $PROFILE_ARG 2>&1 | tee /dev/tty | grep -q "No changes to deploy"; then
  print_message "$GREEN" "✓ Tenant stack is up to date (no changes to deploy)"
else
  print_message "$GREEN" "✓ Tenant stack deployed"
fi
echo ""

# Step 5: Generate Lambda invocations for cost attribution demo
print_message "$YELLOW" "Step 5: Generating Lambda invocations for cost attribution..."
echo "Generating 30 invocations (10 create + 10 update + 10 get)..."

for i in {1..10}; do
  aws lambda invoke --function-name create-product-pooled-lab7 --region="$AWS_REGION" $PROFILE_ARG --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name update-product-pooled-lab7 --region="$AWS_REGION" $PROFILE_ARG --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Updated Product '$i'","price":149.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name get-products-pooled-lab7 --region="$AWS_REGION" $PROFILE_ARG --cli-binary-format raw-in-base64-out --payload '{}' /dev/null > /dev/null 2>&1
done

print_message "$GREEN" "✓ 30 Lambda invocations generated"
echo ""
print_message "$YELLOW" "Waiting 4 minutes for CloudWatch Logs ingestion and Insights indexing..."
echo "(CloudWatch Logs Insights needs time to index logs before they're queryable)"
echo "(The scheduled attribution Lambdas run every 5 minutes and will process these invocations)"
sleep 240
echo "Total: 30 Lambda invocations generated"
echo ""

print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab7 Deployment Complete!"
print_message "$GREEN" "=========================================="
echo ""
echo "Resources deployed:"
echo "  - Main stack: $MAIN_STACK_NAME"
echo "  - Tenant stack: $TENANT_STACK_NAME"
echo "  - CUR S3 Bucket: $CUR_BUCKET"
echo "  - DynamoDB Table: TenantCostAndUsageAttribution-lab7"
echo ""
echo "Attribution system:"
echo "  - Scheduled attribution Lambdas run every 5 minutes"
echo "  - Data is automatically collected and stored in DynamoDB"
echo "  - 30 test invocations generated for demo purposes"
echo ""
echo "Note: CloudWatch Logs Insights indexing may take a few minutes."
echo "Initial attribution runs may show fewer invocations until indexing completes."
echo ""
echo "View attribution data:"
echo "  aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7 --region $AWS_REGION"
echo ""
