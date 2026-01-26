# Lab 1 Summary

## Overview
Lab 1 introduces a basic serverless web application with product and order management functionality. This lab demonstrates fundamental AWS serverless architecture patterns using Lambda, API Gateway, DynamoDB, and CloudFront.

## Architecture
- **Lambda Functions**: Product and order management (Python 3.14 runtime)
- **API Gateway**: REST API for product/order operations
- **DynamoDB**: Single table for data storage
- **CloudFront**: Content delivery for web application
- **S3**: Static website hosting

## Key Features
- Basic CRUD operations for products and orders
- Serverless architecture with no server management
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

## Deployment
```
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**Deployment Time**: ~10-15 minutes

## Verification
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Outputs**:
- Application Site URL (CloudFront)
- API Gateway URL
- S3 Bucket name

## Testing
Test API endpoint with sample product creation:
```
curl -X POST <API_GATEWAY_URL>/product \
  -H "Content-Type: application/json" \
  -d '{"category": "category1", "name": "Alexa", "price": "25", "sku": "XYZ"}'
```

## Cleanup
```
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

## Requirements Validated
- 4.1: Resource tagging
- 4.2: Cleanup completeness
- 9.1: Deployment success
- 10.1: Script functionality
- 10.2: Error handling
- 10.3: Profile parameter support
