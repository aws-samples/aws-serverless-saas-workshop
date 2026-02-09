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
AWS_PROFILE=""
SHARED_STACK_NAME="serverless-saas-shared-lab3"
TENANT_STACK_NAME="serverless-saas-tenant-lab3"
DEPLOY_SERVER=0
DEPLOY_BOOTSTRAP=0
DEPLOY_TENANT=0
DEPLOY_CLIENT=0
ADMIN_EMAIL=""
TENANT_ADMIN_EMAIL=""
CLOUDWATCH_ROLE_PRE_CREATED=0

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
    echo "  -s, --server              Deploy both bootstrap and tenant server code"
    echo "  -b, --bootstrap           Deploy only bootstrap server code (shared services)"
    echo "  -t, --tenant              Deploy only tenant server code (microservices)"
    echo "  -c, --client              Deploy client code (Application UI)"
    echo "  -e, --email <email>       Admin user email address"
    echo "  -te, --tenant-email <email>  Tenant admin email address (enables auto-tenant creation)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS CLI profile name (optional)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                                           # Deploy both bootstrap and tenant server"
    echo "  $0 -b                                           # Deploy only bootstrap server"
    echo "  $0 -t                                           # Deploy only tenant server"
    echo "  $0 -s -c                                        # Deploy server and client"
    echo "  $0 -s -e admin@example.com                      # Deploy server with admin email"
    echo "  $0 -s -te tenant@example.com                    # Deploy server with auto-tenant creation"
    echo "  $0 -s -c -e admin@example.com --region us-east-1  # Deploy with custom region"
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
            DEPLOY_BOOTSTRAP=1
            DEPLOY_TENANT=1
            # Lab 3 uses pooled architecture with both shared and tenant stacks
            # The -s flag deploys BOTH stacks for full functionality
            shift
            ;;
        -b|--bootstrap)
            DEPLOY_BOOTSTRAP=1
            shift
            ;;
        -t|--tenant)
            DEPLOY_TENANT=1
            shift
            ;;
        -c|--client)
            DEPLOY_CLIENT=1
            shift
            ;;
        -e|--email)
            ADMIN_EMAIL=$2
            shift 2
            ;;
        -te|--tenant-email)
            TENANT_ADMIN_EMAIL=$2
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
        --cloudwatch-role-created)
            CLOUDWATCH_ROLE_PRE_CREATED=1
            shift
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
if [[ $DEPLOY_BOOTSTRAP -eq 0 ]] && [[ $DEPLOY_TENANT -eq 0 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
    print_message "$RED" "Error: Must specify at least one deployment option (-s, -b, -t, or -c)"
    echo ""
    print_usage
    exit 1
fi

# Set PROFILE_ARG based on AWS_PROFILE for use in AWS CLI and SAM CLI commands
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab3-deployment.log"
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
print_message "$BLUE" "Lab3 Deployment Script"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Tenant Stack: $TENANT_STACK_NAME"
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

# Check Node.js if client deployment is requested
if [[ $DEPLOY_CLIENT -eq 1 ]]; then
    if ! command -v npm &> /dev/null; then
        print_message "$RED" "Error: npm is not installed"
        print_message "$YELLOW" "Install Node.js from: https://nodejs.org/"
        exit 1
    fi
    NODE_VERSION=$(node --version 2>&1)
    print_message "$GREEN" "  ✓ Node.js installed (version: $NODE_VERSION)"
fi

# Validate AWS credentials
print_message "$YELLOW" "  Validating AWS credentials..."
if [[ -n "$AWS_PROFILE" ]]; then
    if ! aws sts get-caller-identity --region "$AWS_REGION" --profile "$AWS_PROFILE" &> /dev/null; then
        print_message "$RED" "Error: AWS credentials not configured for profile: $AWS_PROFILE"
        print_message "$YELLOW" "Configure with: aws configure --profile $AWS_PROFILE"
        exit 1
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --region "$AWS_REGION" --profile "$AWS_PROFILE" --query Account --output text)
else
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        print_message "$RED" "Error: AWS credentials not configured"
        print_message "$YELLOW" "Configure with: aws configure"
        exit 1
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)
fi
print_message "$GREEN" "  ✓ AWS credentials valid"
print_message "$GREEN" "    Account: $ACCOUNT_ID"
print_message "$GREEN" "    Region: $AWS_REGION"
if [[ -n "$AWS_PROFILE" ]]; then
    print_message "$GREEN" "    Profile: $AWS_PROFILE"
fi

echo ""

# During AWS hosted events using event engine tool 
# we pre-provision cloudfront and s3 buckets which hosts UI code. 
# So that it improves this labs total execution time. 
# Below code checks if cloudfront and s3 buckets are 
# pre-provisioned or not and then concludes if the workshop 
# is running in AWS hosted event through event engine tool or not.
IS_RUNNING_IN_EVENT_ENGINE=false 
if [[ -n "$AWS_PROFILE" ]]; then
    PREPROVISIONED_ADMIN_SITE=$(aws cloudformation --profile "$AWS_PROFILE" list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
else
    PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
fi
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  print_message "$YELLOW" "  Workshop is running in WorkshopStudio"
  IS_RUNNING_IN_EVENT_ENGINE=true
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION")
    LANDING_APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text --region "$AWS_REGION")
    APP_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSiteBucket'].Value" --output text --region "$AWS_REGION")
    APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text --region "$AWS_REGION")
  else
    ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text --region "$AWS_REGION")
    LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text --region "$AWS_REGION")
    APP_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSiteBucket'].Value" --output text --region "$AWS_REGION")
    APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text --region "$AWS_REGION")
  fi
fi


if [[ $DEPLOY_BOOTSTRAP -eq 1 ]] || [[ $DEPLOY_TENANT -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 2: Validating Python code"
  print_message "$BLUE" "=========================================="
  cd ../server || exit
  
  # Use virtual environment Python if available
  if [ -f "../../.venv_py313/bin/python" ]; then
    PYTHON_CMD="../../.venv_py313/bin/python"
  else
    PYTHON_CMD="python3"
  fi
  
  print_message "$YELLOW" "  Validating Python code with pylint..."
  if command -v pylint &> /dev/null; then
    $PYTHON_CMD -m pylint -E -d E0401,E1111 $(find . -iname "*.py" -not -path "./.aws-sam/*") || {
      print_message "$RED" "Error: Code validation failed. Please fix errors and retry."
      exit 1
    }
    print_message "$GREEN" "  ✓ Code validation passed"
  else
    print_message "$YELLOW" "  Warning: pylint not installed, skipping code validation"
  fi
  
  cd ../scripts || exit
  echo ""
fi

if [[ $DEPLOY_BOOTSTRAP -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 3: Deploying bootstrap server infrastructure"
  print_message "$BLUE" "=========================================="
  cd ../server || exit

  # Get SAM S3 bucket for shared stack from samconfig.toml
  SHARED_SAM_BUCKET=$(grep s3_bucket shared-samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")
  
  if [[ -z "$SHARED_SAM_BUCKET" ]]; then
    print_message "$RED" "Error: No SAM bucket specified in shared-samconfig.toml"
    print_message "$YELLOW" "Please add s3_bucket value to shared-samconfig.toml"
    exit 1
  fi
  
  print_message "$YELLOW" "  Checking SAM deployment bucket: $SHARED_SAM_BUCKET"
  PROFILE_ARG=""
  if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
  fi
  
  if ! aws s3 ls "s3://${SHARED_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
    print_message "$YELLOW" "  Bucket does not exist, creating: $SHARED_SAM_BUCKET"
    aws s3 mb "s3://${SHARED_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
    aws s3api put-bucket-encryption \
      $PROFILE_ARG \
      --bucket "$SHARED_SAM_BUCKET" \
      --region "$AWS_REGION" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    print_message "$GREEN" "  ✓ Created SAM deployment bucket: $SHARED_SAM_BUCKET"
  else
    print_message "$GREEN" "  ✓ SAM deployment bucket exists: $SHARED_SAM_BUCKET"
  fi

  # Build SAM application
  print_message "$YELLOW" "  Building SAM application (shared services)..."
  sam build -t shared-template.yaml || {
    print_message "$RED" "Error: SAM build failed"
    exit 1
  }
  print_message "$GREEN" "  ✓ SAM build completed"
  
  # Check if API Gateway CloudWatch role already exists
  print_message "$YELLOW" "  Checking for existing API Gateway CloudWatch role..."
  CREATE_CLOUDWATCH_ROLE="true"
  
  # If role was pre-created by deploy-all-labs.sh, skip the check
  if [[ $CLOUDWATCH_ROLE_PRE_CREATED -eq 1 ]]; then
    CREATE_CLOUDWATCH_ROLE="false"
    print_message "$GREEN" "  ✓ API Gateway CloudWatch role was pre-created, skipping creation"
  elif [[ -n "$AWS_PROFILE" ]]; then
    if aws iam get-role --role-name apigateway-cloudwatch-publish-role --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
      CREATE_CLOUDWATCH_ROLE="false"
      print_message "$GREEN" "  ✓ API Gateway CloudWatch role already exists, skipping creation"
    else
      print_message "$YELLOW" "  API Gateway CloudWatch role does not exist, will create it"
    fi
  else
    if aws iam get-role --role-name apigateway-cloudwatch-publish-role --region "$AWS_REGION" >/dev/null 2>&1; then
      CREATE_CLOUDWATCH_ROLE="false"
      print_message "$GREEN" "  ✓ API Gateway CloudWatch role already exists, skipping creation"
    else
      print_message "$YELLOW" "  API Gateway CloudWatch role does not exist, will create it"
    fi
  fi
  
  # Build parameter overrides
  PARAM_OVERRIDES="EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE"
  if [ ! -z "$ADMIN_EMAIL" ]; then
    PARAM_OVERRIDES="$PARAM_OVERRIDES AdminEmailParameter=$ADMIN_EMAIL"
    print_message "$YELLOW" "  Using admin email: $ADMIN_EMAIL"
  fi
  if [ ! -z "$TENANT_ADMIN_EMAIL" ]; then
    PARAM_OVERRIDES="$PARAM_OVERRIDES TenantAdminEmailParameter=$TENANT_ADMIN_EMAIL"
    print_message "$YELLOW" "  Using tenant admin email: $TENANT_ADMIN_EMAIL"
  fi
  
  # Deploy SAM application
  print_message "$YELLOW" "  Deploying SAM application to stack: $SHARED_STACK_NAME"
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = true ]; then
    if [[ -n "$AWS_PROFILE" ]]; then
      sam deploy --config-file shared-samconfig.toml --profile "$AWS_PROFILE" --region="$AWS_REGION" --stack-name "$SHARED_STACK_NAME" --parameter-overrides $PARAM_OVERRIDES AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL TenantUserPoolCallbackURLParameter=$APP_SITE_URL --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    else
      sam deploy --config-file shared-samconfig.toml --region="$AWS_REGION" --stack-name "$SHARED_STACK_NAME" --parameter-overrides $PARAM_OVERRIDES AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL TenantUserPoolCallbackURLParameter=$APP_SITE_URL --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    fi
  else
    if [[ -n "$AWS_PROFILE" ]]; then
      sam deploy --config-file shared-samconfig.toml --profile "$AWS_PROFILE" --region="$AWS_REGION" --stack-name "$SHARED_STACK_NAME" --parameter-overrides $PARAM_OVERRIDES --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    else
      sam deploy --config-file shared-samconfig.toml --region="$AWS_REGION" --stack-name "$SHARED_STACK_NAME" --parameter-overrides $PARAM_OVERRIDES --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    fi
  fi
  print_message "$GREEN" "  ✓ Bootstrap server infrastructure deployed successfully"
  
  cd ../scripts || exit
  echo ""
fi  

if [[ $DEPLOY_TENANT -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 4: Deploying tenant server infrastructure"
  print_message "$BLUE" "=========================================="
  cd ../server || exit

  # Get SAM S3 bucket for tenant stack from samconfig.toml
  TENANT_SAM_BUCKET=$(grep s3_bucket tenant-samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")
  
  if [[ -z "$TENANT_SAM_BUCKET" ]]; then
    print_message "$RED" "Error: No SAM bucket specified in tenant-samconfig.toml"
    print_message "$YELLOW" "Please add s3_bucket value to tenant-samconfig.toml"
    exit 1
  fi
  
  print_message "$YELLOW" "  Checking SAM deployment bucket: $TENANT_SAM_BUCKET"
  PROFILE_ARG=""
  if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
  fi
  
  if ! aws s3 ls "s3://${TENANT_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
    print_message "$YELLOW" "  Bucket does not exist, creating: $TENANT_SAM_BUCKET"
    aws s3 mb "s3://${TENANT_SAM_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
    aws s3api put-bucket-encryption \
      $PROFILE_ARG \
      --bucket "$TENANT_SAM_BUCKET" \
      --region "$AWS_REGION" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    print_message "$GREEN" "  ✓ Created SAM deployment bucket: $TENANT_SAM_BUCKET"
  else
    print_message "$GREEN" "  ✓ SAM deployment bucket exists: $TENANT_SAM_BUCKET"
  fi

  # Build SAM application
  print_message "$YELLOW" "  Building SAM application (tenant microservices)..."
  sam build -t tenant-template.yaml || {
    print_message "$RED" "Error: SAM build failed"
    exit 1
  }
  print_message "$GREEN" "  ✓ SAM build completed"
  
  # Deploy SAM application
  print_message "$YELLOW" "  Deploying SAM application to stack: $TENANT_STACK_NAME"
  if [[ -n "$AWS_PROFILE" ]]; then
    sam deploy --config-file tenant-samconfig.toml --profile "$AWS_PROFILE" --region="$AWS_REGION" --stack-name "$TENANT_STACK_NAME" --no-fail-on-empty-changeset || {
      print_message "$RED" "Error: SAM deployment failed"
      exit 1
    }
  else
    sam deploy --config-file tenant-samconfig.toml --region="$AWS_REGION" --stack-name "$TENANT_STACK_NAME" --no-fail-on-empty-changeset || {
      print_message "$RED" "Error: SAM deployment failed"
      exit 1
    }
  fi
  print_message "$GREEN" "  ✓ Tenant server infrastructure deployed successfully"
  
  cd ../scripts || exit
  echo ""
fi



if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
    APP_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  else
    ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
    APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  fi
fi

if [[ $DEPLOY_CLIENT -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 5: Deploying client applications"
  print_message "$BLUE" "=========================================="

  # Re-query stack outputs after deployment to ensure we have the latest values
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
    if [[ -n "$AWS_PROFILE" ]]; then
      APP_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    else
      APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$APP_SITE_BUCKET" ]] || [[ "$APP_SITE_BUCKET" == "None" ]]; then
    print_message "$RED" "Error: Could not retrieve Application S3 bucket from CloudFormation stack"
    print_message "$YELLOW" "Make sure the bootstrap server infrastructure is deployed first with -b or -s flag"
    exit 1
  fi

  # Lab 3 uses a pooled architecture with TWO API Gateways:
  # 1. Admin API Gateway (shared stack) - handles tenant/user management
  # 2. Tenant API Gateway (tenant stack) - handles business logic (products, orders)
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_APIGATEWAYURL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
    APP_APPCLIENTID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoTenantAppClientId'].OutputValue" --output text 2>/dev/null || echo "")
    APP_USERPOOLID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoTenantUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
    # Get Tenant API Gateway URL from tenant stack for product/order operations
    APP_APIGATEWAYURL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" --output text 2>/dev/null || echo "")
  else
    ADMIN_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
    APP_APPCLIENTID=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoTenantAppClientId'].OutputValue" --output text 2>/dev/null || echo "")
    APP_USERPOOLID=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoTenantUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
    # Get Tenant API Gateway URL from tenant stack for product/order operations
    APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name "$TENANT_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" --output text 2>/dev/null || echo "")
  fi

  if [[ -z "$APP_APIGATEWAYURL" ]] || [[ "$APP_APIGATEWAYURL" == "None" ]]; then
    print_message "$RED" "Error: Could not retrieve Admin API Gateway URL from CloudFormation stack"
    print_message "$YELLOW" "Make sure the shared server infrastructure is deployed first with -b or -s flag"
    exit 1
  fi

  # Lab 3 creates its own CloudFront distributions for Admin, Landing, and Application
  # We need to deploy all three client applications to their respective S3 buckets
  print_message "$YELLOW" "  Lab3 deploys Admin, Landing, and Application UIs with pooled multi-tenant architecture."
  
  # Get all S3 bucket names from CloudFormation stack
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_APPCLIENTID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USERPOOLID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
  else
    ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_APPCLIENTID=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USERPOOLID=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
  fi

  # Verify all buckets are accessible
  print_message "$YELLOW" "  Verifying S3 bucket access..."
  for BUCKET in "$ADMIN_SITE_BUCKET" "$LANDING_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if [[ -z "$BUCKET" ]] || [[ "$BUCKET" == "None" ]]; then
      print_message "$RED" "Error: Could not retrieve S3 bucket from CloudFormation stack"
      print_message "$YELLOW" "Make sure the bootstrap server infrastructure is deployed first with -b or -s flag"
      exit 1
    fi
    if [[ -n "$AWS_PROFILE" ]]; then
      if ! aws s3 --profile "$AWS_PROFILE" ls "s3://${BUCKET}" --region "$AWS_REGION" &> /dev/null; then
        print_message "$RED" "Error: S3 Bucket $BUCKET not accessible"
        exit 1
      fi
    else
      if ! aws s3 ls "s3://${BUCKET}" --region "$AWS_REGION" &> /dev/null; then
        print_message "$RED" "Error: S3 Bucket $BUCKET not accessible"
        exit 1
      fi
    fi
  done
  print_message "$GREEN" "  ✓ All S3 buckets accessible"

  # Deploy Admin Client
  print_message "$YELLOW" "  Deploying Admin Client..."
  cd ../client/Admin || exit

  print_message "$YELLOW" "  Configuring environment for Admin Client"
  
  # Create environments directory if it doesn't exist
  mkdir -p ./src/environments
  
  cat << EoF > ./src/environments/environment.prod.ts
  export const environment = {
    production: true,
    apiUrl: '$ADMIN_APIGATEWAYURL',
  };
EoF
  cat << EoF > ./src/environments/environment.ts
  export const environment = {
    production: true,
    apiUrl: '$ADMIN_APIGATEWAYURL',
  };
EoF

  print_message "$YELLOW" "  Configuring AWS Amplify for Admin Client"
  cat << EoF > ./src/aws-exports.ts
const awsmobile = {
  aws_project_region: '$AWS_REGION',
  aws_cognito_region: '$AWS_REGION',
  aws_user_pools_id: '$ADMIN_USERPOOLID',
  aws_user_pools_web_client_id: '$ADMIN_APPCLIENTID',
};

export default awsmobile;
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Admin Client..."
  rm -rf node_modules package-lock.json || true
  
  print_message "$YELLOW" "  Installing npm dependencies for Admin Client..."
  npm install --legacy-peer-deps || {
    print_message "$RED" "Error: npm install failed for Admin Client"
    exit 1
  }
  
  print_message "$YELLOW" "  Building Admin Client..."
  npm run build || {
    print_message "$RED" "Error: npm build failed for Admin Client"
    exit 1
  }
  print_message "$GREEN" "  ✓ Admin Client built successfully"

  print_message "$YELLOW" "  Uploading Admin Client to S3..."
  if [[ -n "$AWS_PROFILE" ]]; then
    aws s3 --profile "$AWS_PROFILE" sync --delete --cache-control no-store dist "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Admin Client to S3"
      exit 1
    }
  else
    aws s3 sync --delete --cache-control no-store dist "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Admin Client to S3"
      exit 1
    }
  fi
  print_message "$GREEN" "  ✓ Admin Client deployed successfully"

  # Deploy Landing Client
  print_message "$YELLOW" "  Deploying Landing Client..."
  cd ../Landing || exit

  print_message "$YELLOW" "  Configuring environment for Landing Client"
  
  # Create environments directory if it doesn't exist
  mkdir -p ./src/environments
  
  cat << EoF > ./src/environments/environment.prod.ts
  export const environment = {
    production: true,
    apiGatewayUrl: '$ADMIN_APIGATEWAYURL',
  };
EoF
  cat << EoF > ./src/environments/environment.ts
  export const environment = {
    production: true,
    apiGatewayUrl: '$ADMIN_APIGATEWAYURL',
  };
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Landing Client..."
  rm -rf node_modules package-lock.json || true
  
  print_message "$YELLOW" "  Installing npm dependencies for Landing Client..."
  npm install --legacy-peer-deps || {
    print_message "$RED" "Error: npm install failed for Landing Client"
    exit 1
  }
  
  print_message "$YELLOW" "  Building Landing Client..."
  npm run build || {
    print_message "$RED" "Error: npm build failed for Landing Client"
    exit 1
  }
  print_message "$GREEN" "  ✓ Landing Client built successfully"

  print_message "$YELLOW" "  Uploading Landing Client to S3..."
  if [[ -n "$AWS_PROFILE" ]]; then
    aws s3 --profile "$AWS_PROFILE" sync --delete --cache-control no-store dist "s3://${LANDING_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Landing Client to S3"
      exit 1
    }
  else
    aws s3 sync --delete --cache-control no-store dist "s3://${LANDING_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Landing Client to S3"
      exit 1
    }
  fi
  print_message "$GREEN" "  ✓ Landing Client deployed successfully"

  # Deploy Application Client
  print_message "$YELLOW" "  Deploying Application Client..."
  cd ../Application || exit

  print_message "$YELLOW" "  Configuring environment for App Client"
  
  # Create environments directory if it doesn't exist
  mkdir -p ./src/environments
  
  cat << EoF > ./src/environments/environment.prod.ts
  export const environment = {
    production: true,
    regApiGatewayUrl: '$ADMIN_APIGATEWAYURL',
    apiGatewayUrl: '$APP_APIGATEWAYURL',
    userPoolId: '$APP_USERPOOLID',
    appClientId: '$APP_APPCLIENTID',
  };
EoF
  cat << EoF > ./src/environments/environment.ts
  export const environment = {
    production: true,
    regApiGatewayUrl: '$ADMIN_APIGATEWAYURL',
    apiGatewayUrl: '$APP_APIGATEWAYURL',
    userPoolId: '$APP_USERPOOLID',
    appClientId: '$APP_APPCLIENTID',
  };
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for App Client..."
  rm -rf node_modules package-lock.json || true
  
  print_message "$YELLOW" "  Installing npm dependencies for App Client..."
  npm install --legacy-peer-deps || {
    print_message "$RED" "Error: npm install failed for App Client"
    exit 1
  }
  
  print_message "$YELLOW" "  Building App Client..."
  npm run build || {
    print_message "$RED" "Error: npm build failed for App Client"
    exit 1
  }
  print_message "$GREEN" "  ✓ App Client built successfully"

  print_message "$YELLOW" "  Uploading App Client to S3..."
  if [[ -n "$AWS_PROFILE" ]]; then
    aws s3 --profile "$AWS_PROFILE" sync --delete --cache-control no-store dist "s3://${APP_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload App Client to S3"
      exit 1
    }
  else
    aws s3 sync --delete --cache-control no-store dist "s3://${APP_SITE_BUCKET}" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload App Client to S3"
      exit 1
    }
  fi
  print_message "$GREEN" "  ✓ App Client deployed successfully"

  cd ../../scripts || exit
  echo ""
fi

# Automatically create admin user and sample tenants if email was provided
# Users are created after BOTH bootstrap AND tenant stacks are deployed
# because they need the Cognito user pools and Admin API to be ready
if [[ $DEPLOY_BOOTSTRAP -eq 1 ]] && [[ $DEPLOY_TENANT -eq 1 ]]; then
  
  # Step 6: Create Admin User
  if [ ! -z "$ADMIN_EMAIL" ]; then
    echo ""
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "Step 6: Creating admin user"
    print_message "$BLUE" "=========================================="
    
    # Get Cognito Operation Users Pool ID
    if [[ -n "$AWS_PROFILE" ]]; then
      ADMIN_USER_POOL_ID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null)
    else
      ADMIN_USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null)
    fi
    
    if [ -z "$ADMIN_USER_POOL_ID" ]; then
      print_message "$YELLOW" "  Warning: Could not find Admin User Pool ID. Skipping admin user creation."
    else
      # Generate secure temporary password
      ADMIN_USERNAME="admin-user"
      ADMIN_PASSWORD="TempPass$(date +%s)!"
      
      print_message "$YELLOW" "  Creating admin user: $ADMIN_USERNAME"
      
      # Create admin user in Cognito
      if [[ -n "$AWS_PROFILE" ]]; then
        aws cognito-idp admin-create-user \
          --profile "$AWS_PROFILE" \
          --user-pool-id "$ADMIN_USER_POOL_ID" \
          --username "$ADMIN_USERNAME" \
          --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=custom:tenantId,Value=system_admins Name=custom:userRole,Value=SystemAdmin \
          --temporary-password "$ADMIN_PASSWORD" \
          --message-action SUPPRESS \
          --region "$AWS_REGION" > /dev/null 2>&1
        
        # Add user to SystemAdmins group
        aws cognito-idp admin-add-user-to-group \
          --profile "$AWS_PROFILE" \
          --user-pool-id "$ADMIN_USER_POOL_ID" \
          --username "$ADMIN_USERNAME" \
          --group-name SystemAdmins \
          --region "$AWS_REGION" > /dev/null 2>&1
      else
        aws cognito-idp admin-create-user \
          --user-pool-id "$ADMIN_USER_POOL_ID" \
          --username "$ADMIN_USERNAME" \
          --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=custom:tenantId,Value=system_admins Name=custom:userRole,Value=SystemAdmin \
          --temporary-password "$ADMIN_PASSWORD" \
          --message-action SUPPRESS \
          --region "$AWS_REGION" > /dev/null 2>&1
        
        # Add user to SystemAdmins group
        aws cognito-idp admin-add-user-to-group \
          --user-pool-id "$ADMIN_USER_POOL_ID" \
          --username "$ADMIN_USERNAME" \
          --group-name SystemAdmins \
          --region "$AWS_REGION" > /dev/null 2>&1
      fi
      
      if [ $? -eq 0 ]; then
        print_message "$GREEN" "  ✓ Admin user created successfully"
        print_message "$GREEN" "    Username: $ADMIN_USERNAME"
        print_message "$GREEN" "    Email: $ADMIN_EMAIL"
        print_message "$GREEN" "    Temporary Password: $ADMIN_PASSWORD"
      else
        print_message "$RED" "  ✗ Failed to create admin user"
        ADMIN_USERNAME=""
        ADMIN_PASSWORD=""
      fi
    fi
  fi
  
  # Step 7: Create Sample Tenants
  if [ ! -z "$TENANT_ADMIN_EMAIL" ]; then
    echo ""
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "Step 7: Creating sample tenants"
    print_message "$BLUE" "=========================================="
  
  # Extract username and domain from email
  # Extract base username (before any + sign) to avoid double + in tenant emails
  EMAIL_FULL_USERNAME=$(echo "$TENANT_ADMIN_EMAIL" | cut -d'@' -f1)
  EMAIL_USERNAME=$(echo "$EMAIL_FULL_USERNAME" | cut -d'+' -f1)
  EMAIL_DOMAIN=$(echo "$TENANT_ADMIN_EMAIL" | cut -d'@' -f2)
  
  # Get the Admin API Gateway URL from Lab3 shared stack
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_API_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null)
  else
    ADMIN_API_URL=$(aws cloudformation describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null)
  fi
  
  if [ -z "$ADMIN_API_URL" ]; then
    print_message "$YELLOW" "  Warning: Could not find Admin API URL. Skipping automatic tenant creation."
  else
    # Create Tenant One
    TENANT1_EMAIL="${EMAIL_USERNAME}+lab3tenant1@${EMAIL_DOMAIN}"
    TENANT1_USERNAME="tenant1-admin"
    print_message "$YELLOW" "  Creating Tenant One with email: $TENANT1_EMAIL"
    
    TENANT1_RESPONSE=$(curl -s -X POST "${ADMIN_API_URL}/registration" \
      -H "Content-Type: application/json" \
      -d "{
        \"tenantName\": \"Tenant One\",
        \"tenantEmail\": \"$TENANT1_EMAIL\",
        \"tenantAdminUserName\": \"$TENANT1_USERNAME\",
        \"tenantTier\": \"standard\",
        \"tenantPhone\": \"+1-555-0001\",
        \"tenantAddress\": \"123 Main St, City, State 12345\"
      }")
    
    if echo "$TENANT1_RESPONSE" | grep -q "registered"; then
      # Extract temporary password from response
      TENANT1_PASSWORD=$(echo "$TENANT1_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', {}).get('temporaryPassword', ''))" 2>/dev/null || echo "")
      print_message "$GREEN" "  ✓ Tenant One created successfully"
      print_message "$GREEN" "    Username: $TENANT1_USERNAME"
      print_message "$GREEN" "    Email: $TENANT1_EMAIL"
      if [[ -n "$TENANT1_PASSWORD" ]]; then
        print_message "$GREEN" "    Temporary Password: $TENANT1_PASSWORD"
      else
        print_message "$YELLOW" "    ⚠️  Could not extract temporary password from API response"
      fi
    else
      print_message "$RED" "  ✗ Failed to create Tenant One"
      print_message "$RED" "    Response: $TENANT1_RESPONSE"
      TENANT1_USERNAME=""
      TENANT1_PASSWORD=""
    fi
    
    # Create Tenant Two
    TENANT2_EMAIL="${EMAIL_USERNAME}+lab3tenant2@${EMAIL_DOMAIN}"
    TENANT2_USERNAME="tenant2-admin"
    echo ""
    print_message "$YELLOW" "  Creating Tenant Two with email: $TENANT2_EMAIL"
    
    TENANT2_RESPONSE=$(curl -s -X POST "${ADMIN_API_URL}/registration" \
      -H "Content-Type: application/json" \
      -d "{
        \"tenantName\": \"Tenant Two\",
        \"tenantEmail\": \"$TENANT2_EMAIL\",
        \"tenantAdminUserName\": \"$TENANT2_USERNAME\",
        \"tenantTier\": \"standard\",
        \"tenantPhone\": \"+1-555-0002\",
        \"tenantAddress\": \"456 Oak Ave, City, State 12345\"
      }")
    
    if echo "$TENANT2_RESPONSE" | grep -q "registered"; then
      # Extract temporary password from response
      TENANT2_PASSWORD=$(echo "$TENANT2_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', {}).get('temporaryPassword', ''))" 2>/dev/null || echo "")
      print_message "$GREEN" "  ✓ Tenant Two created successfully"
      print_message "$GREEN" "    Username: $TENANT2_USERNAME"
      print_message "$GREEN" "    Email: $TENANT2_EMAIL"
      if [[ -n "$TENANT2_PASSWORD" ]]; then
        print_message "$GREEN" "    Temporary Password: $TENANT2_PASSWORD"
      else
        print_message "$YELLOW" "    ⚠️  Could not extract temporary password from API response"
      fi
    else
      print_message "$RED" "  ✗ Failed to create Tenant Two"
      print_message "$RED" "    Response: $TENANT2_RESPONSE"
      TENANT2_USERNAME=""
      TENANT2_PASSWORD=""
    fi
    
    echo ""
    print_message "$GREEN" "  ✓ Sample tenant creation complete!"
  fi
  
  # Display all credentials (admin + tenants) if any were created
  if [[ -n "$ADMIN_PASSWORD" ]] || [[ -n "$TENANT1_PASSWORD" ]] || [[ -n "$TENANT2_PASSWORD" ]]; then
    echo ""
    print_message "$YELLOW" "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "$GREEN" "  🔐 User Credentials Created:"
    echo ""
    
    if [[ -n "$ADMIN_PASSWORD" ]]; then
      print_message "$GREEN" "  Admin User (Operation Users Pool):"
      print_message "$GREEN" "    Username: $ADMIN_USERNAME"
      print_message "$GREEN" "    Password: $ADMIN_PASSWORD"
      print_message "$GREEN" "    Email: $ADMIN_EMAIL"
      print_message "$GREEN" "    Login at: https://${ADMIN_SITE_URL}"
      echo ""
    fi
    
    if [[ -n "$TENANT1_PASSWORD" ]]; then
      print_message "$GREEN" "  Tenant One (Pooled Tenant User Pool):"
      print_message "$GREEN" "    Username: $TENANT1_USERNAME"
      print_message "$GREEN" "    Password: $TENANT1_PASSWORD"
      print_message "$GREEN" "    Email: $TENANT1_EMAIL"
      echo ""
    fi
    
    if [[ -n "$TENANT2_PASSWORD" ]]; then
      print_message "$GREEN" "  Tenant Two (Pooled Tenant User Pool):"
      print_message "$GREEN" "    Username: $TENANT2_USERNAME"
      print_message "$GREEN" "    Password: $TENANT2_PASSWORD"
      print_message "$GREEN" "    Email: $TENANT2_EMAIL"
      echo ""
    fi
    
    print_message "$GREEN" "  Tenant Login URL: https://${APP_SITE_URL}"
    print_message "$YELLOW" "  ⚠️  You will be required to change these passwords on first login"
    print_message "$YELLOW" "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Update CloudFormation stack with all user credentials
    print_message "$YELLOW" "  Updating CloudFormation stack with user credentials..."
    
    # Build parameter list with all credentials
    STACK_PARAMS="ParameterKey=Environment,UsePreviousValue=true \
      ParameterKey=Owner,UsePreviousValue=true \
      ParameterKey=CostCenter,UsePreviousValue=true \
      ParameterKey=AdminEmailParameter,UsePreviousValue=true \
      ParameterKey=TenantAdminEmailParameter,UsePreviousValue=true \
      ParameterKey=SystemAdminRoleNameParameter,UsePreviousValue=true \
      ParameterKey=StageName,UsePreviousValue=true \
      ParameterKey=EventEngineParameter,UsePreviousValue=true \
      ParameterKey=AdminUserPoolCallbackURLParameter,UsePreviousValue=true \
      ParameterKey=TenantUserPoolCallbackURLParameter,UsePreviousValue=true \
      ParameterKey=CreateCloudWatchRole,UsePreviousValue=true"
    
    # Add admin credentials if created
    if [[ -n "$ADMIN_PASSWORD" ]]; then
      STACK_PARAMS="$STACK_PARAMS ParameterKey=AdminUsername,ParameterValue=\"$ADMIN_USERNAME\" \
        ParameterKey=AdminTemporaryPassword,ParameterValue=\"$ADMIN_PASSWORD\""
    else
      STACK_PARAMS="$STACK_PARAMS ParameterKey=AdminUsername,UsePreviousValue=true \
        ParameterKey=AdminTemporaryPassword,UsePreviousValue=true"
    fi
    
    # Add tenant credentials if created
    if [[ -n "$TENANT1_PASSWORD" ]]; then
      STACK_PARAMS="$STACK_PARAMS ParameterKey=Tenant1Username,ParameterValue=\"$TENANT1_USERNAME\" \
        ParameterKey=Tenant1TemporaryPassword,ParameterValue=\"$TENANT1_PASSWORD\""
    else
      STACK_PARAMS="$STACK_PARAMS ParameterKey=Tenant1Username,UsePreviousValue=true \
        ParameterKey=Tenant1TemporaryPassword,UsePreviousValue=true"
    fi
    
    if [[ -n "$TENANT2_PASSWORD" ]]; then
      STACK_PARAMS="$STACK_PARAMS ParameterKey=Tenant2Username,ParameterValue=\"$TENANT2_USERNAME\" \
        ParameterKey=Tenant2TemporaryPassword,ParameterValue=\"$TENANT2_PASSWORD\""
    else
      STACK_PARAMS="$STACK_PARAMS ParameterKey=Tenant2Username,UsePreviousValue=true \
        ParameterKey=Tenant2TemporaryPassword,UsePreviousValue=true"
    fi
    
    # Execute stack update
    if [[ -n "$AWS_PROFILE" ]]; then
      aws cloudformation update-stack \
        --profile "$AWS_PROFILE" \
        --stack-name "$SHARED_STACK_NAME" \
        --use-previous-template \
        --parameters $STACK_PARAMS \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --region "$AWS_REGION" > /dev/null 2>&1
    else
      aws cloudformation update-stack \
        --stack-name "$SHARED_STACK_NAME" \
        --use-previous-template \
        --parameters $STACK_PARAMS \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --region "$AWS_REGION" > /dev/null 2>&1
    fi
    
    UPDATE_EXIT_CODE=$?
    if [[ $UPDATE_EXIT_CODE -eq 0 ]]; then
      print_message "$GREEN" "  ✓ Stack update initiated"
      print_message "$YELLOW" "  Waiting for stack update to complete..."
      
      # Wait for stack update to complete
      if [[ -n "$AWS_PROFILE" ]]; then
        aws cloudformation wait stack-update-complete \
          --profile "$AWS_PROFILE" \
          --stack-name "$SHARED_STACK_NAME" \
          --region "$AWS_REGION"
      else
        aws cloudformation wait stack-update-complete \
          --stack-name "$SHARED_STACK_NAME" \
          --region "$AWS_REGION"
      fi
      
      WAIT_EXIT_CODE=$?
      if [[ $WAIT_EXIT_CODE -eq 0 ]]; then
        print_message "$GREEN" "  ✓ Stack updated with all user credentials"
        print_message "$GREEN" "  ℹ️  Credentials are now available in CloudFormation outputs"
        print_message "$YELLOW" "  💡 To retrieve credentials later, run:"
        if [[ -n "$AWS_PROFILE" ]]; then
          print_message "$YELLOW" "     aws cloudformation describe-stacks --stack-name $SHARED_STACK_NAME --profile $AWS_PROFILE --query \"Stacks[0].Outputs\""
        else
          print_message "$YELLOW" "     aws cloudformation describe-stacks --stack-name $SHARED_STACK_NAME --query \"Stacks[0].Outputs\""
        fi
      else
        print_message "$YELLOW" "  ⚠️  Stack update may have failed (exit code: $WAIT_EXIT_CODE)"
      fi
    else
      print_message "$YELLOW" "  ⚠️  Could not update stack with credentials (non-critical)"
    fi
  fi
  echo ""
  fi  # Close: if [ ! -z "$TENANT_ADMIN_EMAIL" ]; then (from line 806)
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display deployment summary
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab3 Deployment Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Duration: ${DURATION} seconds"
echo ""

# Output URLs
if [[ -n "$ADMIN_SITE_URL" ]] && [[ "$ADMIN_SITE_URL" != "None" ]]; then
  print_message "$BLUE" "Application URLs:"
  print_message "$BLUE" "  Admin Site: https://${ADMIN_SITE_URL}"
  print_message "$BLUE" "  Landing Site: https://${LANDING_APP_SITE_URL}"
  print_message "$BLUE" "  App Site: https://${APP_SITE_URL}"
  echo ""
fi

print_message "$YELLOW" "Next Steps:"
if [[ $DEPLOY_BOOTSTRAP -eq 1 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
  print_message "$YELLOW" "  1. Deploy the client application: ./deployment.sh -c"
  print_message "$YELLOW" "  2. Access the Admin Site using the URL above"
  print_message "$YELLOW" "  3. Create tenants and test multi-tenancy"
elif [[ $DEPLOY_CLIENT -eq 1 ]]; then
  print_message "$YELLOW" "  1. Open the App Site URL in your browser"
  print_message "$YELLOW" "  2. Log in with tenant credentials"
  print_message "$YELLOW" "  3. Test product and order management"
  print_message "$YELLOW" "  4. Verify tenant isolation"
fi
print_message "$YELLOW" "  5. To retrieve URLs later: ./geturl.sh"
print_message "$YELLOW" "  6. To clean up resources: ./cleanup.sh"
echo ""
print_message "$GREEN" "Log file: $LOG_FILE"
