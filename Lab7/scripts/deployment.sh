#!/bin/bash

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

REGION=$(aws configure get region)

# Create log directory and file
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

# Use virtual environment Python if available
if [ -f "$LAB_DIR/../.venv_py313/bin/python" ]; then
  export PATH="$LAB_DIR/../.venv_py313/bin:$PATH"
fi

echo "=========================================="
echo "Lab7 Deployment Script - Provisioned"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo ""

# Step 1: Deploy main Lab7 stack
echo "Step 1: Deploying main Lab7 stack..."
sam build -t "$LAB_DIR/template.yaml"
sam deploy --config-file "$LAB_DIR/samconfig.toml" --region=$REGION
echo "✓ Main stack deployed"
echo ""

# Step 2: Upload sample CUR data
echo "Step 2: Uploading sample CUR data..."
CUR_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='CURBucketname'].Value" --output text)
AWSCURInitializerFunctionName=$(aws cloudformation list-exports --query "Exports[?Name=='AWSCURInitializerFunctionName'].Value" --output text)

aws s3 cp "$LAB_DIR/SampleCUR/" s3://$CUR_BUCKET/curoutput/year=2022/month=10/ --recursive
echo "✓ Sample CUR data uploaded"
echo ""

# Step 3: Initialize CUR crawler
echo "Step 3: Initializing CUR crawler..."
aws lambda invoke --function-name $AWSCURInitializerFunctionName "$LAB_DIR/lambdaoutput.json"
rm -f "$LAB_DIR/lambdaoutput.json"
echo "✓ CUR crawler initialized"
echo ""

# Step 4: Deploy tenant stack for cost attribution demo
echo "Step 4: Deploying tenant stack (stack-pooled-lab7)..."
sam build --template-file "$LAB_DIR/tenant-template.yaml"
sam deploy --config-file "$LAB_DIR/tenant-samconfig.toml"
echo "✓ Tenant stack deployed"
echo ""

# Step 5: Generate Lambda invocations for cost attribution demo
echo "Step 5: Generating Lambda invocations for cost attribution..."
echo "Generating 30 invocations (10 create + 10 update + 10 get)..."

for i in {1..10}; do
  aws lambda invoke --function-name create-product-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name update-product-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Updated Product '$i'","price":149.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name get-products-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{}' /dev/null > /dev/null 2>&1
done

echo "✓ 30 Lambda invocations generated"
echo ""
echo "Waiting 4 minutes for CloudWatch Logs ingestion and Insights indexing..."
echo "(CloudWatch Logs Insights needs time to index logs before they're queryable)"
echo "(The scheduled attribution Lambdas run every 5 minutes and will process these invocations)"
sleep 240
echo "Total: 30 Lambda invocations generated"
echo ""

echo "=========================================="
echo "Lab7 Deployment Complete!"
echo "=========================================="
echo ""
echo "Resources deployed:"
echo "  - Main stack: serverless-saas-workshop-lab7"
echo "  - Tenant stack: stack-pooled-lab7"
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
echo "  aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7 --region $REGION"
echo ""
