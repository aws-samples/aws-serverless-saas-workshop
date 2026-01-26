# Lab 1: Introducing a Basic Serverless Web Application

## Quick Reference

**Deployment Time:** ~10-15 minutes | **Cleanup Time:** ~15-20 minutes

### Quick Start
```bash
# Deploy
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo

# Get URLs
./geturl.sh --profile serverless-saas-demo

# Cleanup
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

### What You'll Deploy
- **10 Lambda Functions** - Product and order management (Python 3.14)
- **2 DynamoDB Tables** - Product-Lab1, Order-Lab1
- **1 API Gateway** - REST API with product/order endpoints
- **1 CloudFront Distribution** - Global content delivery
- **1 S3 Bucket** - Static website hosting

### Key Features
- Basic CRUD operations for products and orders
- Serverless architecture with no server management
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

---

## Overview

Lab 1 introduces the foundational concepts of serverless architecture by building a basic web application for product and order management. This lab demonstrates how to create a fully functional serverless application using AWS Lambda, API Gateway, DynamoDB, and CloudFront without managing any servers.

**What You'll Build:**
- RESTful API for product and order management
- Serverless backend with Lambda functions
- DynamoDB tables for data persistence
- CloudFront distribution for content delivery
- Static web application hosted on S3

**Learning Objectives:**
- Understand serverless architecture fundamentals
- Deploy Lambda functions with Python 3.14 runtime
- Configure API Gateway for REST APIs
- Set up DynamoDB for NoSQL data storage
- Implement CloudFront for global content delivery

## Prerequisites

Before starting this lab, ensure you have:

### Required Tools
- **AWS CLI** (v2.x or later) - [Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **AWS SAM CLI** (v1.x or later) - [Installation Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- **Python 3.14** - [Download](https://www.python.org/downloads/)
- **Docker** - Required for SAM build - [Installation Guide](https://docs.docker.com/get-docker/)
- **Git** - For cloning the repository

### AWS Account Requirements
- Active AWS account with appropriate permissions
- AWS credentials configured locally
- Sufficient service limits for:
  - Lambda functions (10 functions)
  - DynamoDB tables (2 tables)
  - API Gateway REST APIs (1 API)
  - CloudFront distributions (1 distribution)
  - S3 buckets (1 bucket)

### AWS Profile Setup
Configure your AWS profile if not already done:
```
aws configure --profile serverless-saas-demo
```

You'll be prompted for:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (recommend: us-east-1)
- Default output format (recommend: json)

## Architecture

### High-Level Architecture
```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│   CloudFront    │ ◄── Content Delivery Network
└────────┬────────┘
         │
         ▼
    ┌────────┐
    │   S3   │ ◄── Static Website Hosting
    └────────┘
         │
         ▼
┌─────────────────┐
│  API Gateway    │ ◄── REST API Endpoint
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Lambda Functions│ ◄── Business Logic (Python 3.14)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    DynamoDB     │ ◄── Data Persistence
└─────────────────┘
```

### Components

#### Lambda Functions (10 total)
**Product Service:**
- `GetProductFunction` - Retrieve single product
- `GetProductsFunction` - List all products
- `CreateProductFunction` - Create new product
- `UpdateProductFunction` - Update existing product
- `DeleteProductFunction` - Delete product

**Order Service:**
- `GetOrderFunction` - Retrieve single order
- `GetOrdersFunction` - List all orders
- `CreateOrderFunction` - Create new order
- `UpdateOrderFunction` - Update existing order
- `DeleteOrderFunction` - Delete order

#### DynamoDB Tables (2 total)
- `Product-Lab1` - Stores product information
- `Order-Lab1` - Stores order information

#### API Gateway
- REST API with product and order endpoints
- Integrated with Lambda functions
- CloudWatch logging enabled (60-day retention)

#### CloudFront Distribution
- Global content delivery
- S3 origin for static assets
- HTTPS enabled

#### S3 Bucket
- Static website hosting
- Application UI files
- CloudFront origin

## Deployment Steps

### Step 1: Navigate to Lab 1 Directory
```
cd workshop/Lab1/scripts
```

### Step 2: Deploy the Application

**Full Deployment (Server + Client):**
```
./deployment.sh -s -c --profile serverless-saas-demo
```

**Server Only:**
```
./deployment.sh -s --profile serverless-saas-demo
```

**Client Only (requires server deployed first):**
```
./deployment.sh -c --profile serverless-saas-demo
```

**Deployment Options:**
- `-s, --server` - Deploy backend infrastructure (Lambda, API Gateway, DynamoDB)
- `-c, --client` - Deploy frontend application (S3, CloudFront)
- `--profile <name>` - AWS profile to use (optional, uses default if not specified)
- `--region <region>` - AWS region (default: us-east-1)
- `--stack-name <name>` - CloudFormation stack name (default: serverless-saas-lab1)
- `-h, --help` - Display help message

**Expected Deployment Time:** 10-15 minutes

**Deployment Process:**
1. Validates prerequisites (AWS CLI, SAM CLI, Python, Docker, credentials)
2. Builds Lambda functions using SAM
3. Packages application artifacts
4. Deploys CloudFormation stack
5. Uploads static assets to S3
6. Configures CloudFront distribution
7. Outputs application URLs

### Step 3: Retrieve Application URLs
```
./geturl.sh --profile serverless-saas-demo
```

**Expected Output:**
```
Application Site URL: https://<cloudfront-distribution-id>.cloudfront.net
API Gateway URL: https://<api-id>.execute-api.us-east-1.amazonaws.com/Prod
S3 Bucket: serverless-saas-lab1-app-<unique-id>
```

## Verification

### 1. Verify CloudFormation Stack
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

**Expected Output:** `"CREATE_COMPLETE"`

### 2. Verify Lambda Functions
```
aws lambda list-functions \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Functions[?contains(FunctionName, `lab1`)].FunctionName'
```

**Expected Output:** List of 10 Lambda functions with `lab1` in their names

### 3. Verify DynamoDB Tables
```
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'TableNames[?contains(@, `Lab1`)]'
```

**Expected Output:** `["Product-Lab1", "Order-Lab1"]`

### 4. Test API Endpoints

**Create a Product:**
```
API_URL=$(aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

curl -X POST ${API_URL}/product \
  -H "Content-Type: application/json" \
  -d '{
    "category": "Electronics",
    "name": "Alexa Echo Dot",
    "price": "49.99",
    "sku": "ECHO-DOT-001"
  }'
```

**Expected Response:**
```json
{
  "productId": "generated-uuid",
  "category": "Electronics",
  "name": "Alexa Echo Dot",
  "price": "49.99",
  "sku": "ECHO-DOT-001"
}
```

**List Products:**
```
curl -X GET ${API_URL}/products
```

**Create an Order:**
```
curl -X POST ${API_URL}/order \
  -H "Content-Type: application/json" \
  -d '{
    "orderName": "Test Order",
    "orderProducts": [
      {
        "productId": "generated-uuid",
        "quantity": 2,
        "price": "49.99"
      }
    ]
  }'
```

### 5. Access Web Application
Open the Application Site URL (CloudFront URL) in your browser. You should see the product and order management interface.

## Testing

### Manual Testing Checklist
- [ ] Create a product via API
- [ ] List all products via API
- [ ] Get a specific product via API
- [ ] Update a product via API
- [ ] Delete a product via API
- [ ] Create an order via API
- [ ] List all orders via API
- [ ] Get a specific order via API
- [ ] Update an order via API
- [ ] Delete an order via API
- [ ] Access web application via CloudFront URL
- [ ] Verify data persists in DynamoDB

### Automated Testing
Run the property-based tests to verify deployment:
```
cd workshop/tests
python -m pytest test_lab1_scripts.py -v
```

## Cleanup

### Option 1: Automated Cleanup (Recommended)
```
cd workshop/Lab1/scripts
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

### Option 2: Interactive Cleanup
```
./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

You'll be prompted to confirm deletion.

### Cleanup Options
- `--stack-name <name>` - CloudFormation stack name (default: serverless-saas-lab1)
- `--profile <name>` - AWS profile to use (optional)
- `--region <region>` - AWS region (default: us-east-1)
- `-h, --help` - Display help message

### What Gets Deleted
The cleanup script removes:
- CloudFormation stack (including all nested resources)
- Lambda functions and layers
- API Gateway REST API
- DynamoDB tables
- CloudFront distribution
- S3 bucket (including all objects)
- CloudWatch log groups
- IAM roles and policies

**Cleanup Time:** 15-20 minutes (CloudFront deletion takes longest)

### Verify Cleanup
```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile serverless-saas-demo \
  --region us-east-1
```

**Expected Output:** Stack not found error (indicates successful deletion)

## Troubleshooting

### Deployment Issues

#### Issue: "AWS CLI not found"
**Solution:**
```
# Install AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

#### Issue: "SAM CLI not found"
**Solution:**
```
# Install SAM CLI via Homebrew (macOS)
brew install aws-sam-cli

# Or via pip
pip install aws-sam-cli
```

#### Issue: "Docker not running"
**Solution:**
Start Docker Desktop and ensure it's running before deployment.

#### Issue: "Insufficient permissions"
**Solution:**
Ensure your AWS credentials have the following permissions:
- CloudFormation: Full access
- Lambda: Full access
- API Gateway: Full access
- DynamoDB: Full access
- S3: Full access
- CloudFront: Full access
- IAM: Create/update roles and policies
- CloudWatch: Create log groups

#### Issue: "Stack already exists"
**Solution:**
Either use a different stack name or clean up the existing stack:
```
./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

#### Issue: "SAM build fails"
**Solution:**
1. Ensure Python 3.14 is installed
2. Verify Docker is running
3. Check Lambda function code for syntax errors
4. Review build logs in `workshop/Lab1/logs/deployment-*.log`

### Runtime Issues

#### Issue: "API returns 500 error"
**Solution:**
Check Lambda function logs:
```
aws logs tail /aws/lambda/serverless-saas-lab1-GetProductFunction \
  --profile serverless-saas-demo \
  --region us-east-1 \
  --follow
```

#### Issue: "DynamoDB table not found"
**Solution:**
Verify tables exist:
```
aws dynamodb describe-table \
  --table-name Product-Lab1 \
  --profile serverless-saas-demo \
  --region us-east-1
```

#### Issue: "CloudFront returns 403 error"
**Solution:**
1. Verify S3 bucket policy allows CloudFront access
2. Check CloudFront distribution status (must be "Deployed")
3. Wait 15-20 minutes for CloudFront propagation

### Cleanup Issues

#### Issue: "Stack deletion fails"
**Solution:**
1. Check CloudFormation events for specific error
2. Manually delete resources blocking deletion
3. Retry cleanup script

#### Issue: "S3 bucket not empty"
**Solution:**
The cleanup script automatically empties buckets. If it fails:
```
aws s3 rm s3://serverless-saas-lab1-app-xyz123 --recursive \
  --profile serverless-saas-demo \
  --region us-east-1
```

#### Issue: "CloudWatch logs not deleted"
**Solution:**
Manually delete log groups:
```
aws logs delete-log-group \
  --log-group-name /aws/lambda/serverless-saas-lab1-GetProductFunction \
  --profile serverless-saas-demo \
  --region us-east-1
```

## Additional Resources

### Documentation
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [Amazon CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/latest/developerguide/)
- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/)

### Workshop Resources
- [Lab 1 Summary](LAB1_SUMMARY.md) - Quick reference guide
- [Deployment Manual](../DEPLOYMENT_CLEANUP_MANUAL.md) - Comprehensive deployment guide
- [Resource Naming Convention](../RESOURCE_NAMING_CONVENTION.md) - Naming standards

### Next Steps
After completing Lab 1, proceed to:
- **Lab 2**: Introducing SaaS Shared Services - Add tenant management and user authentication

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Review deployment logs in `workshop/Lab1/logs/`
3. Consult the [Deployment Manual](../DEPLOYMENT_CLEANUP_MANUAL.md)
4. Open an issue in the workshop repository

## License

This workshop is licensed under the MIT-0 License. See the LICENSE file for details.
