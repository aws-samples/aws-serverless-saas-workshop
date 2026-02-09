#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
STACK_NAME="serverless-saas-lab1"
DEPLOY_SERVER=0
DEPLOY_CLIENT=0
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# AWS_PROFILE variable is used directly in AWS CLI commands
# Pattern: ${AWS_PROFILE:+--profile "$AWS_PROFILE"}
# This expands to --profile "value" when AWS_PROFILE is set, or nothing when empty

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --server              Deploy server code (Lambda functions, API Gateway, DynamoDB)"
    echo "  -c, --client              Deploy client code (Angular application to S3/CloudFront)"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab1)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS profile to use (optional, uses machine's default if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s -c                                    # Deploy both server and client with defaults"
    echo "  $0 -s --stack-name my-stack                 # Deploy only server with custom stack name"
    echo "  $0 -s -c --region us-east-1                 # Deploy both with custom region"
    echo "  $0 -s -c --profile my-profile               # Deploy both with specific AWS profile"
}

# Parse command line arguments
if [[ "$#" -eq 0 ]]; then
    print_message "$RED" "Error: No parameters provided"
    echo ""
    print_usage
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server)
            DEPLOY_SERVER=1
            shift
            ;;
        -c|--client)
            DEPLOY_CLIENT=1
            shift
            ;;
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

# Validate at least one deployment option is selected
if [[ $DEPLOY_SERVER -eq 0 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
    print_message "$RED" "Error: Must specify at least one deployment option (-s or -c)"
    echo ""
    print_usage
    exit 1
fi

# Set PROFILE_ARG based on AWS_PROFILE for use in AWS CLI and SAM CLI commands
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Create log directory and file
# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab1-deployment.log"
else
    # Individual Lab Mode: Create timestamped directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_DIR="logs/$TIMESTAMP"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/deployment.log"
fi

# Redirect all output to log file and console
# Skip if running in test mode (test framework handles logging)
if [[ -z "$E2E_TEST_MODE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab1 Deployment Script"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using machine's default profile)"
fi
echo "AWS Region: $AWS_REGION"
echo "Stack Name: $STACK_NAME"
echo ""

# Record start time
START_TIME=$(date +%s)

# Pre-deployment validation
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step 1: Validating prerequisites"
print_message "$BLUE" "=========================================="

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_message "$RED" "Error: AWS CLI is not installed"
    print_message "$YELLOW" "Install from: https://aws.amazon.com/cli/"
    exit 1
fi
print_message "$GREEN" "  ✓ AWS CLI installed"

# Check SAM CLI
if ! command -v sam &> /dev/null; then
    print_message "$RED" "Error: SAM CLI is not installed"
    print_message "$YELLOW" "Install from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi
print_message "$GREEN" "  ✓ SAM CLI installed"

# Check Python 3.14
if ! command -v python3 &> /dev/null; then
    print_message "$RED" "Error: Python 3 is not installed"
    exit 1
fi
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
print_message "$GREEN" "  ✓ Python installed (version: $PYTHON_VERSION)"

# Check Node.js version (only if client deployment is requested)
if [[ $DEPLOY_CLIENT -eq 1 ]]; then
    if ! command -v node &> /dev/null; then
        print_message "$RED" "Error: Node.js is not installed"
        print_message "$YELLOW" "Install Node.js LTS from: https://nodejs.org/"
        exit 1
    fi
    
    NODE_VERSION=$(node --version 2>&1 | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    
    print_message "$GREEN" "  ✓ Node.js installed (version: v$NODE_VERSION)"
    
    # Check if Node.js version is LTS (even-numbered major versions)
    if [ $((NODE_MAJOR % 2)) -eq 1 ]; then
        print_message "$YELLOW" "  ⚠️  WARNING: Node.js v$NODE_MAJOR is not an LTS version"
        print_message "$YELLOW" "  Odd-numbered Node.js versions are not recommended for production"
        print_message "$YELLOW" "  Recommended LTS versions: v20.x or v22.x"
        print_message "$YELLOW" "  Download from: https://nodejs.org/"
        echo ""
        read -p "Continue anyway? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_message "$YELLOW" "Deployment cancelled. Please install a Node.js LTS version."
            exit 0
        fi
    fi
fi

# Validate AWS credentials
print_message "$YELLOW" "  Validating AWS credentials..."
if ! aws sts get-caller-identity ${AWS_PROFILE:+--profile "$AWS_PROFILE"} --region "$AWS_REGION" &> /dev/null; then
    print_message "$RED" "Error: AWS credentials not configured"
    print_message "$YELLOW" "Configure with: aws configure"
    exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity ${AWS_PROFILE:+--profile "$AWS_PROFILE"} --region "$AWS_REGION" --query Account --output text)
print_message "$GREEN" "  ✓ AWS credentials valid"
print_message "$GREEN" "    Account: $ACCOUNT_ID"
print_message "$GREEN" "    Region: $AWS_REGION"

# Check and configure API Gateway CloudWatch Logs role (required for API Gateway logging)
print_message "$YELLOW" "  Checking API Gateway CloudWatch Logs role..."
ROLE_NAME="apigateway-cloudwatch-publish-role"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Check if role exists
if ! aws iam get-role $PROFILE_ARG --role-name "$ROLE_NAME" &> /dev/null; then
    print_message "$YELLOW" "  Creating API Gateway CloudWatch Logs role..."
    
    # Create trust policy
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
    
    # Create role
    aws iam create-role \
        $PROFILE_ARG \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Allows API Gateway to push logs to CloudWatch Logs" &> /dev/null || {
        print_message "$RED" "Error: Failed to create API Gateway CloudWatch Logs role"
        exit 1
    }
    
    # Attach policy
    aws iam attach-role-policy \
        $PROFILE_ARG \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs" &> /dev/null || {
        print_message "$RED" "Error: Failed to attach policy to API Gateway CloudWatch Logs role"
        exit 1
    }
    
    print_message "$GREEN" "  ✓ API Gateway CloudWatch Logs role created"
    
    # Wait a moment for role to propagate
    sleep 5
else
    print_message "$GREEN" "  ✓ API Gateway CloudWatch Logs role exists"
fi

# Configure API Gateway account settings
CURRENT_ROLE=$(aws apigateway get-account $PROFILE_ARG --region "$AWS_REGION" --query 'cloudwatchRoleArn' --output text 2>/dev/null || echo "None")
if [[ "$CURRENT_ROLE" == "None" ]] || [[ -z "$CURRENT_ROLE" ]]; then
    print_message "$YELLOW" "  Configuring API Gateway account settings..."
    aws apigateway update-account \
        $PROFILE_ARG \
        --patch-operations op=replace,path=/cloudwatchRoleArn,value="$ROLE_ARN" \
        --region "$AWS_REGION" &> /dev/null || {
        print_message "$YELLOW" "  Warning: Failed to configure API Gateway account settings (may require additional permissions)"
    }
    print_message "$GREEN" "  ✓ API Gateway account settings configured"
else
    print_message "$GREEN" "  ✓ API Gateway account settings already configured"
fi

echo ""

if [[ $DEPLOY_SERVER -eq 1 ]]; then
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "Step 2: Deploying server infrastructure"
    print_message "$BLUE" "=========================================="
    
    # Get the directory where the script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    LAB_DIR="$(dirname "$SCRIPT_DIR")"
    
    cd "$LAB_DIR/server" || exit
    
    # Check if samconfig.toml exists
    if [[ ! -f samconfig.toml ]]; then
        print_message "$RED" "Error: samconfig.toml not found in server directory"
        exit 1
    fi
    
    # Get or create SAM S3 bucket from samconfig.toml
    DEFAULT_SAM_S3_BUCKET=$(grep s3_bucket samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")
    
    if [[ -z "$DEFAULT_SAM_S3_BUCKET" ]]; then
        print_message "$RED" "Error: No SAM bucket specified in samconfig.toml"
        exit 1
    fi
    
    print_message "$YELLOW" "  Checking SAM deployment bucket: $DEFAULT_SAM_S3_BUCKET"
    if ! aws s3 ls "s3://${DEFAULT_SAM_S3_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Bucket does not exist, creating: $DEFAULT_SAM_S3_BUCKET"
        aws s3 mb "s3://${DEFAULT_SAM_S3_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
        aws s3api put-bucket-encryption \
            $PROFILE_ARG \
            --bucket "$DEFAULT_SAM_S3_BUCKET" \
            --region "$AWS_REGION" \
            --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
        print_message "$GREEN" "  ✓ Created SAM deployment bucket: $DEFAULT_SAM_S3_BUCKET"
    else
        print_message "$GREEN" "  ✓ SAM deployment bucket exists: $DEFAULT_SAM_S3_BUCKET"
    fi
    
    # Validate Python code
    print_message "$YELLOW" "  Validating Python code with pylint..."
    if command -v pylint &> /dev/null; then
        python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*") || {
            print_message "$RED" "Error: Code validation failed. Please fix errors and retry."
            exit 1
        }
        print_message "$GREEN" "  ✓ Code validation passed"
    else
        print_message "$YELLOW" "  Warning: pylint not installed, skipping code validation"
    fi
    
    # Build SAM application
    print_message "$YELLOW" "  Building SAM application..."
    sam build -t template.yaml || {
        print_message "$RED" "Error: SAM build failed"
        exit 1
    }
    print_message "$GREEN" "  ✓ SAM build completed"
    
    # Deploy SAM application
    print_message "$YELLOW" "  Deploying SAM application to stack: $STACK_NAME"
    sam deploy \
        $PROFILE_ARG \
        --config-file samconfig.toml \
        --region "$AWS_REGION" \
        --stack-name "$STACK_NAME" \
        --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
    }
    print_message "$GREEN" "  ✓ Server infrastructure deployed successfully"
    
    cd ../scripts || exit
    echo ""
fi

if [[ $DEPLOY_CLIENT -eq 1 ]]; then
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "Step 3: Deploying client application"
    print_message "$BLUE" "=========================================="
    
    # Get CloudFormation outputs
    print_message "$YELLOW" "  Retrieving CloudFormation stack outputs..."
    APP_SITE_BUCKET=$(aws cloudformation describe-stacks \
        $PROFILE_ARG \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    APP_SITE_URL=$(aws cloudformation describe-stacks \
        $PROFILE_ARG \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    APP_APIGATEWAYURL=$(aws cloudformation describe-stacks \
        $PROFILE_ARG \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='APIGatewayURL'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$APP_SITE_BUCKET" ]] || [[ "$APP_SITE_BUCKET" == "None" ]]; then
        print_message "$RED" "Error: Could not retrieve S3 bucket from CloudFormation stack"
        print_message "$YELLOW" "Make sure the server infrastructure is deployed first with -s flag"
        exit 1
    fi
    
    if [[ -z "$APP_APIGATEWAYURL" ]] || [[ "$APP_APIGATEWAYURL" == "None" ]]; then
        print_message "$RED" "Error: Could not retrieve API Gateway URL from CloudFormation stack"
        exit 1
    fi
    
    print_message "$GREEN" "  ✓ Retrieved stack outputs"
    
    # Verify S3 bucket is accessible
    print_message "$YELLOW" "  Verifying S3 bucket access: $APP_SITE_BUCKET"
    if ! aws s3 ls "s3://${APP_SITE_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$RED" "Error: S3 bucket not accessible: $APP_SITE_BUCKET"
        exit 1
    fi
    print_message "$GREEN" "  ✓ S3 bucket accessible"
    
    # Navigate to client directory
    cd ../client/Application || exit
    
    # Check if Node.js is installed
    if ! command -v npm &> /dev/null; then
        print_message "$RED" "Error: npm is not installed"
        print_message "$YELLOW" "Install Node.js from: https://nodejs.org/"
        exit 1
    fi
    
    # Configure environment files
    print_message "$YELLOW" "  Configuring Angular environment files..."
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$APP_APIGATEWAYURL'
};
EoF

    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$APP_APIGATEWAYURL'
};
EoF
    
    print_message "$GREEN" "  ✓ Environment files configured"
    
    # Clean previous npm installation to avoid stale dependencies
    print_message "$YELLOW" "  Cleaning previous npm installation..."
    rm -rf node_modules package-lock.json || true
    
    # Install dependencies and build
    print_message "$YELLOW" "  Installing npm dependencies..."
    npm install || {
        print_message "$RED" "Error: npm install failed"
        exit 1
    }
    print_message "$GREEN" "  ✓ Dependencies installed"
    
    print_message "$YELLOW" "  Building Angular application..."
    # Use Angular CLI directly to avoid Node.js compatibility issues
    if node node_modules/@angular/cli/bin/ng.js build; then
        print_message "$GREEN" "  ✓ Application built"
    else
        print_message "$RED" "Error: Angular build failed"
        if [ $((NODE_MAJOR % 2)) -eq 1 ]; then
            print_message "$YELLOW" "This may be due to Node.js v$NODE_MAJOR not being an LTS version"
            print_message "$YELLOW" "Please install Node.js LTS (v20.x or v22.x) from: https://nodejs.org/"
        fi
        exit 1
    fi
    
    # Deploy to S3
    print_message "$YELLOW" "  Uploading application to S3..."
    aws s3 sync --delete --cache-control no-store dist "s3://${APP_SITE_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" || {
        print_message "$RED" "Error: Failed to upload to S3"
        exit 1
    }
    print_message "$GREEN" "  ✓ Application uploaded to S3"
    
    cd ../../scripts || exit
    echo ""
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display deployment summary
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab1 Deployment Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Duration: ${DURATION} seconds"
echo ""

# Output URLs if client was deployed
if [[ $DEPLOY_CLIENT -eq 1 ]] && [[ -n "$APP_SITE_URL" ]]; then
    print_message "$BLUE" "Application URLs:"
    print_message "$BLUE" "  Application Site: https://${APP_SITE_URL}"
    if [[ -n "$APP_APIGATEWAYURL" ]]; then
        print_message "$BLUE" "  API Gateway URL: ${APP_APIGATEWAYURL}"
    fi
    echo ""
fi

print_message "$YELLOW" "Next Steps:"
if [[ $DEPLOY_SERVER -eq 1 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
    print_message "$YELLOW" "  1. Deploy the client application: ./deployment.sh -c"
    print_message "$YELLOW" "  2. Access the application using the URL above"
elif [[ $DEPLOY_CLIENT -eq 1 ]]; then
    print_message "$YELLOW" "  1. Open the Application Site URL in your browser"
    print_message "$YELLOW" "  2. Follow the lab instructions to test the application"
fi
print_message "$YELLOW" "  3. To retrieve URLs later: ./geturl.sh --stack-name $STACK_NAME"
print_message "$YELLOW" "  4. To clean up resources: ./cleanup.sh --stack-name $STACK_NAME"
echo ""
print_message "$GREEN" "Log file: $LOG_FILE"
