#!/bin/bash

set -e  # Exit on error

REGION=$(aws configure get region)

# Use virtual environment Python if available
if [ -f "../.venv_py313/bin/python" ]; then
  export PATH="../.venv_py313/bin:$PATH"
fi

echo "=========================================="
echo "Lab7 Deployment Script"
echo "=========================================="
echo ""

# Step 1: Deploy main Lab7 stack
echo "Step 1: Deploying main Lab7 stack..."
sam build -t template.yaml
sam deploy --config-file samconfig.toml --region=$REGION
echo "✓ Main stack deployed"
echo ""

# Step 2: Upload sample CUR data
echo "Step 2: Uploading sample CUR data..."
CUR_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='CURBucketname'].Value" --output text)
AWSCURInitializerFunctionName=$(aws cloudformation list-exports --query "Exports[?Name=='AWSCURInitializerFunctionName'].Value" --output text)

aws s3 cp SampleCUR/ s3://$CUR_BUCKET/curoutput/year=2022/month=10/ --recursive
echo "✓ Sample CUR data uploaded"
echo ""

# Step 3: Initialize CUR crawler
echo "Step 3: Initializing CUR crawler..."
aws lambda invoke --function-name $AWSCURInitializerFunctionName lambdaoutput.json
rm -f lambdaoutput.json
echo "✓ CUR crawler initialized"
echo ""

# Step 4: Deploy tenant stack for cost attribution demo
echo "Step 4: Deploying tenant stack (stack-pooled-lab7)..."
sam build --template-file tenant-template.yaml
sam deploy --stack-name stack-pooled-lab7 --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset
echo "✓ Tenant stack deployed"
echo ""

# Step 5: Invoke Lambda functions to generate logs for cost attribution
echo "Step 5: Generating Lambda invocations for cost attribution..."
for i in {1..30}; do
  aws lambda invoke --function-name create-product-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name update-product-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{"productId":"prod-'$i'","productName":"Updated Product '$i'","price":149.99}' /dev/null > /dev/null 2>&1
  aws lambda invoke --function-name get-products-pooled-lab7 --cli-binary-format raw-in-base64-out --payload '{}' /dev/null > /dev/null 2>&1
done
echo "✓ Generated 90 Lambda invocations (30 create + 30 update + 30 get)"
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
echo "Cost attribution functions run every 1 minute via EventBridge."
echo "Check DynamoDB table for cost data:"
echo "  aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7"
echo ""
