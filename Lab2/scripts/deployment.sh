#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LAB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
AWS_PROFILE=""
STACK_NAME="serverless-saas-lab2"
DEPLOY_SERVER=0
DEPLOY_CLIENT=0
ADMIN_EMAIL=""
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
    echo "  -s, --server              Deploy server code (Lambda functions, API Gateway, DynamoDB, Cognito)"
    echo "  -c, --client              Deploy client code (Admin and Landing Angular applications)"
    echo "  --email <email>           Admin user email address (required for client deployment)"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab2)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS CLI profile name (optional, uses default profile if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                                           # Deploy only server"
    echo "  $0 -c --email admin@example.com                 # Deploy only client with admin user"
    echo "  $0 -s -c --email admin@example.com              # Deploy both server and client"
    echo "  $0 -s --stack-name my-stack --region us-east-1  # Deploy with custom stack name and region"
    echo "  $0 -s --profile my-profile                      # Deploy with custom AWS profile"
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
        --email)
            ADMIN_EMAIL=$2
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

# Validate email is provided if client deployment is requested
if [[ $DEPLOY_CLIENT -eq 1 ]] && [[ -z "$ADMIN_EMAIL" ]]; then
    print_message "$RED" "Error: --email parameter is required for client deployment"
    echo ""
    print_usage
    exit 1
fi

# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab2-deployment.log"
else
    # Individual Lab Mode: Create timestamped directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_DIR="logs/$TIMESTAMP"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/deployment.log"
fi

# AWS Profile should be passed via --profile parameter

# Redirect all output to log file and console
# Skip if running in test mode (test framework handles logging)
if [[ -z "$E2E_TEST_MODE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab2 Deployment Script"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using default)"
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

echo ""

# During AWS hosted events using event engine tool
# we pre-provision cloudfront and s3 buckets which hosts UI code.
# So that it improves this labs total execution time.
# Below code checks if cloudfront and s3 buckets are
# pre-provisioned or not and then concludes if the workshop
# is running in AWS hosted event through event engine tool or not.
IS_RUNNING_IN_EVENT_ENGINE=false
if [[ -n "$AWS_PROFILE" ]]; then
    PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --profile "$AWS_PROFILE" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null || echo "")
else
    PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null || echo "")
fi
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  print_message "$YELLOW" "  Workshop is running in WorkshopStudio"
  IS_RUNNING_IN_EVENT_ENGINE=true
  if [[ -n "$AWS_PROFILE" ]]; then
      ADMIN_SITE_URL=$(aws cloudformation list-exports --profile "$AWS_PROFILE" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
      LANDING_APP_SITE_URL=$(aws cloudformation list-exports --profile "$AWS_PROFILE" --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
      ADMIN_SITE_BUCKET=$(aws cloudformation list-exports --profile "$AWS_PROFILE" --query "Exports[?Name=='Serverless-SaaS-AdminSiteBucket'].Value" --output text)
      LANDING_APP_SITE_BUCKET=$(aws cloudformation list-exports --profile "$AWS_PROFILE" --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSiteBucket'].Value" --output text)
  else
      ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
      LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
      ADMIN_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminSiteBucket'].Value" --output text)
      LANDING_APP_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSiteBucket'].Value" --output text)
  fi
fi

if [[ $DEPLOY_SERVER -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 2: Deploying server infrastructure"
  print_message "$BLUE" "=========================================="
  
  # Get the directory where this script is located
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  cd "$SCRIPT_DIR/../server" || exit

  # Note: API Gateway CloudWatch role will be created by CloudFormation if needed
  # We don't create it manually here to avoid conflicts

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

  # Deploy SAM application
  print_message "$YELLOW" "  Deploying SAM application to stack: $STACK_NAME"
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = true ]; then
    if [[ -n "$AWS_PROFILE" ]]; then
      sam deploy --config-file samconfig.toml --profile "$AWS_PROFILE" --region="$AWS_REGION" --stack-name "$STACK_NAME" --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    else
      sam deploy --config-file samconfig.toml --region="$AWS_REGION" --stack-name "$STACK_NAME" --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    fi
  else
    if [[ -n "$AWS_PROFILE" ]]; then
      sam deploy --config-file samconfig.toml --profile "$AWS_PROFILE" --region="$AWS_REGION" --stack-name "$STACK_NAME" --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    else
      sam deploy --config-file samconfig.toml --region="$AWS_REGION" --stack-name "$STACK_NAME" --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
      }
    fi
  fi
  print_message "$GREEN" "  ✓ Server infrastructure deployed successfully"

  cd ../scripts || exit
  echo ""
fi

if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
  else
    ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
  fi
fi

if [[ $DEPLOY_CLIENT -eq 1 ]]; then
  print_message "$BLUE" "=========================================="
  print_message "$BLUE" "Step 3: Deploying client applications"
  print_message "$BLUE" "=========================================="

  # Re-query stack outputs after deployment to ensure we have the latest values
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
    if [[ -n "$AWS_PROFILE" ]]; then
      ADMIN_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
      LANDING_APP_SITE_URL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
      ADMIN_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
      LANDING_APP_SITE_BUCKET=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    else
      ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
      LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
      ADMIN_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
      LANDING_APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$ADMIN_SITE_BUCKET" ]] || [[ "$ADMIN_SITE_BUCKET" == "None" ]]; then
    print_message "$RED" "Error: Could not retrieve Admin S3 bucket from CloudFormation stack"
    print_message "$YELLOW" "Make sure the server infrastructure is deployed first with -s flag"
    exit 1
  fi

  if [[ -n "$AWS_PROFILE" ]]; then
    ADMIN_APIGATEWAYURL=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_APPCLIENTID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USERPOOL_ID=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USER_GROUP_NAME=$(aws cloudformation --profile "$AWS_PROFILE" describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoAdminUserGroupName'].OutputValue" --output text 2>/dev/null || echo "")
  else
    ADMIN_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_APPCLIENTID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USERPOOL_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
    ADMIN_USER_GROUP_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoAdminUserGroupName'].OutputValue" --output text 2>/dev/null || echo "")
  fi

  if [[ -z "$ADMIN_APIGATEWAYURL" ]] || [[ "$ADMIN_APIGATEWAYURL" == "None" ]]; then
    print_message "$RED" "Error: Could not retrieve API Gateway URL from CloudFormation stack"
    exit 1
  fi

  # Create admin-user in OperationUsers userpool with given input email address
  print_message "$YELLOW" "  Creating admin user in Cognito..."
  print_message "$YELLOW" "    User Pool ID: $ADMIN_USERPOOL_ID"
  print_message "$YELLOW" "    Email: $ADMIN_EMAIL"
  
  # Generate a temporary password
  TEMP_PASSWORD="TempPass$(date +%s)!"
  
  if [[ -n "$AWS_PROFILE" ]]; then
    CREATE_ADMIN_USER=$(aws cognito-idp --profile "$AWS_PROFILE" admin-create-user \
      --user-pool-id "$ADMIN_USERPOOL_ID" \
      --username admin-user \
      --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=email_verified,Value="True" Name=phone_number,Value="+11234567890" Name="custom:userRole",Value="SystemAdmin" Name="custom:tenantId",Value="system_admins" \
      --message-action SUPPRESS \
      --temporary-password "$TEMP_PASSWORD" \
      --region "$AWS_REGION" 2>&1)
  else
    CREATE_ADMIN_USER=$(aws cognito-idp admin-create-user \
      --user-pool-id "$ADMIN_USERPOOL_ID" \
      --username admin-user \
      --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=email_verified,Value="True" Name=phone_number,Value="+11234567890" Name="custom:userRole",Value="SystemAdmin" Name="custom:tenantId",Value="system_admins" \
      --message-action SUPPRESS \
      --temporary-password "$TEMP_PASSWORD" \
      --region "$AWS_REGION" 2>&1)
  fi

  CREATE_USER_EXIT_CODE=$?
  if [[ $CREATE_USER_EXIT_CODE -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Admin user created successfully"
    # Store credentials for display at the end
    ADMIN_USERNAME="admin-user"
    ADMIN_TEMP_PASSWORD="$TEMP_PASSWORD"
    
    # Update CloudFormation stack with the password
    print_message "$YELLOW" "  Updating CloudFormation stack with admin password..."
    if [[ -n "$AWS_PROFILE" ]]; then
      aws cloudformation update-stack \
        --profile "$AWS_PROFILE" \
        --stack-name "$STACK_NAME" \
        --use-previous-template \
        --parameters \
          ParameterKey=AdminEmailParameter,UsePreviousValue=true \
          ParameterKey=SystemAdminRoleNameParameter,UsePreviousValue=true \
          ParameterKey=StageName,UsePreviousValue=true \
          ParameterKey=EventEngineParameter,UsePreviousValue=true \
          ParameterKey=AdminUserPoolCallbackURLParameter,UsePreviousValue=true \
          ParameterKey=Environment,UsePreviousValue=true \
          ParameterKey=Owner,UsePreviousValue=true \
          ParameterKey=CostCenter,UsePreviousValue=true \
          ParameterKey=CreateCloudWatchRole,UsePreviousValue=true \
          ParameterKey=AdminTemporaryPassword,ParameterValue="$TEMP_PASSWORD" \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --region "$AWS_REGION" > /dev/null 2>&1
    else
      aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --use-previous-template \
        --parameters \
          ParameterKey=AdminEmailParameter,UsePreviousValue=true \
          ParameterKey=SystemAdminRoleNameParameter,UsePreviousValue=true \
          ParameterKey=StageName,UsePreviousValue=true \
          ParameterKey=EventEngineParameter,UsePreviousValue=true \
          ParameterKey=AdminUserPoolCallbackURLParameter,UsePreviousValue=true \
          ParameterKey=Environment,UsePreviousValue=true \
          ParameterKey=Owner,UsePreviousValue=true \
          ParameterKey=CostCenter,UsePreviousValue=true \
          ParameterKey=CreateCloudWatchRole,UsePreviousValue=true \
          ParameterKey=AdminTemporaryPassword,ParameterValue="$TEMP_PASSWORD" \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --region "$AWS_REGION" > /dev/null 2>&1
    fi
    
    UPDATE_EXIT_CODE=$?
    if [[ $UPDATE_EXIT_CODE -eq 0 ]]; then
      print_message "$GREEN" "  ✓ Stack updated with admin password"
      print_message "$YELLOW" "  ℹ️  Password will be available in CloudFormation outputs after stack update completes"
    else
      print_message "$YELLOW" "  ⚠️  Could not update stack with password (non-critical)"
    fi
  else
    if echo "$CREATE_ADMIN_USER" | grep -q "UsernameExistsException"; then
      print_message "$YELLOW" "  Warning: Admin user already exists"
    else
      print_message "$RED" "  Error creating admin user (exit code: $CREATE_USER_EXIT_CODE)"
      print_message "$RED" "  Error details: $CREATE_ADMIN_USER"
      exit 1
    fi
  fi

  # Add admin-user to admin user group
  print_message "$YELLOW" "  Adding admin user to admin group..."
  print_message "$YELLOW" "    Group Name: $ADMIN_USER_GROUP_NAME"
  
  if [[ -n "$AWS_PROFILE" ]]; then
    ADD_ADMIN_USER_TO_GROUP=$(aws cognito-idp --profile "$AWS_PROFILE" admin-add-user-to-group \
      --user-pool-id "$ADMIN_USERPOOL_ID" \
      --username admin-user \
      --group-name "$ADMIN_USER_GROUP_NAME" \
      --region "$AWS_REGION" 2>&1)
  else
    ADD_ADMIN_USER_TO_GROUP=$(aws cognito-idp admin-add-user-to-group \
      --user-pool-id "$ADMIN_USERPOOL_ID" \
      --username admin-user \
      --group-name "$ADMIN_USER_GROUP_NAME" \
      --region "$AWS_REGION" 2>&1)
  fi

  ADD_USER_GROUP_EXIT_CODE=$?
  if [[ $ADD_USER_GROUP_EXIT_CODE -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Admin user added to group"
  else
    print_message "$YELLOW" "  Warning: Could not add user to group (exit code: $ADD_USER_GROUP_EXIT_CODE)"
    print_message "$YELLOW" "  Details: $ADD_ADMIN_USER_TO_GROUP"
  fi

  # Configuring admin UI
  print_message "$YELLOW" "  Configuring Admin UI..."

  # Verify S3 bucket is accessible
  if [[ -n "$AWS_PROFILE" ]]; then
    if ! aws s3 --profile "$AWS_PROFILE" ls "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
      print_message "$RED" "Error: S3 Bucket $ADMIN_SITE_BUCKET not accessible"
      exit 1
    fi
  else
    if ! aws s3 ls "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
      print_message "$RED" "Error: S3 Bucket $ADMIN_SITE_BUCKET not accessible"
      exit 1
    fi
  fi

  cd "$SCRIPT_DIR/../client/Admin" || exit

  print_message "$YELLOW" "  Configuring environment for Admin Client"
  cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiUrl: '$ADMIN_APIGATEWAYURL',
};
EoF

  cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiUrl: '$ADMIN_APIGATEWAYURL',
};
EoF

  cat <<EoF >./src/aws-exports.ts
const awsmobile = {
    "aws_project_region": "$AWS_REGION",
    "aws_cognito_region": "$AWS_REGION",
    "aws_user_pools_id": "$ADMIN_USERPOOL_ID",
    "aws_user_pools_web_client_id": "$ADMIN_APPCLIENTID",
};

export default awsmobile;
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Admin Client..."
  rm -rf node_modules package-lock.json || true

  print_message "$YELLOW" "  Installing npm dependencies for Admin Client..."
  NPM_INSTALL_OUTPUT=$(npm install 2>&1)
  NPM_INSTALL_EXIT_CODE=$?
  
  if [[ $NPM_INSTALL_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: npm install failed for Admin Client (exit code: $NPM_INSTALL_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$NPM_INSTALL_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ npm dependencies installed"
  
  print_message "$YELLOW" "  Building Admin Client..."
  NPM_BUILD_OUTPUT=$(npm run build 2>&1)
  NPM_BUILD_EXIT_CODE=$?
  
  if [[ $NPM_BUILD_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: npm build failed for Admin Client (exit code: $NPM_BUILD_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$NPM_BUILD_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ Admin Client built successfully"

  print_message "$YELLOW" "  Uploading Admin Client to S3..."
  S3_SYNC_OUTPUT=$(
    if [[ -n "$AWS_PROFILE" ]]; then
      aws s3 --profile "$AWS_PROFILE" sync --delete --cache-control no-store dist "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" 2>&1
    else
      aws s3 sync --delete --cache-control no-store dist "s3://${ADMIN_SITE_BUCKET}" --region "$AWS_REGION" 2>&1
    fi
  )
  S3_SYNC_EXIT_CODE=$?
  
  if [[ $S3_SYNC_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: Failed to upload Admin Client to S3 (exit code: $S3_SYNC_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$S3_SYNC_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ Admin Client deployed successfully"

  # Configuring landing UI
  print_message "$YELLOW" "  Configuring Landing UI..."

  # Verify S3 bucket is accessible
  if [[ -n "$AWS_PROFILE" ]]; then
    if ! aws s3 --profile "$AWS_PROFILE" ls "s3://${LANDING_APP_SITE_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
      print_message "$RED" "Error: S3 Bucket $LANDING_APP_SITE_BUCKET not accessible"
      exit 1
    fi
  else
    if ! aws s3 ls "s3://${LANDING_APP_SITE_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
      print_message "$RED" "Error: S3 Bucket $LANDING_APP_SITE_BUCKET not accessible"
      exit 1
    fi
  fi

  cd "$SCRIPT_DIR/../client/Landing" || exit

  print_message "$YELLOW" "  Configuring environment for Landing Client"

  cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF
  cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Landing Client..."
  rm -rf node_modules package-lock.json || true

  print_message "$YELLOW" "  Installing npm dependencies for Landing Client..."
  NPM_INSTALL_OUTPUT=$(npm install 2>&1)
  NPM_INSTALL_EXIT_CODE=$?
  
  if [[ $NPM_INSTALL_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: npm install failed for Landing Client (exit code: $NPM_INSTALL_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$NPM_INSTALL_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ npm dependencies installed"
  
  print_message "$YELLOW" "  Building Landing Client..."
  NPM_BUILD_OUTPUT=$(npm run build 2>&1)
  NPM_BUILD_EXIT_CODE=$?
  
  if [[ $NPM_BUILD_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: npm build failed for Landing Client (exit code: $NPM_BUILD_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$NPM_BUILD_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ Landing Client built successfully"

  print_message "$YELLOW" "  Uploading Landing Client to S3..."
  S3_SYNC_OUTPUT=$(
    if [[ -n "$AWS_PROFILE" ]]; then
      aws s3 --profile "$AWS_PROFILE" sync --delete --cache-control no-store dist "s3://${LANDING_APP_SITE_BUCKET}" --region "$AWS_REGION" 2>&1
    else
      aws s3 sync --delete --cache-control no-store dist "s3://${LANDING_APP_SITE_BUCKET}" --region "$AWS_REGION" 2>&1
    fi
  )
  S3_SYNC_EXIT_CODE=$?
  
  if [[ $S3_SYNC_EXIT_CODE -ne 0 ]]; then
    print_message "$RED" "Error: Failed to upload Landing Client to S3 (exit code: $S3_SYNC_EXIT_CODE)"
    print_message "$RED" "Error output:"
    echo "$S3_SYNC_OUTPUT"
    exit 1
  fi
  print_message "$GREEN" "  ✓ Landing Client deployed successfully"

  cd ../../scripts || exit
  echo ""
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display deployment summary
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab2 Deployment Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Duration: ${DURATION} seconds"
echo ""

# Output URLs
if [[ -n "$ADMIN_SITE_URL" ]] && [[ "$ADMIN_SITE_URL" != "None" ]]; then
  print_message "$BLUE" "Application URLs:"
  print_message "$BLUE" "  Admin Site: https://${ADMIN_SITE_URL}"
  print_message "$BLUE" "  Landing Site: https://${LANDING_APP_SITE_URL}"
  if [[ -n "$ADMIN_APIGATEWAYURL" ]]; then
    print_message "$BLUE" "  Admin API: ${ADMIN_APIGATEWAYURL}"
  fi
  echo ""
fi

print_message "$YELLOW" "Next Steps:"
if [[ $DEPLOY_SERVER -eq 1 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
  print_message "$YELLOW" "  1. Deploy the client applications: ./deployment.sh -c --email <your-email>"
  print_message "$YELLOW" "  2. Check your email for temporary password"
  print_message "$YELLOW" "  3. Access the Admin Site using the URL above"
elif [[ $DEPLOY_CLIENT -eq 1 ]]; then
  # Display admin credentials if user was created
  if [[ -n "$ADMIN_TEMP_PASSWORD" ]]; then
    echo ""
    print_message "$YELLOW" "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "$GREEN" "  📧 Admin User Credentials:"
    print_message "$GREEN" "     Username: $ADMIN_USERNAME"
    print_message "$GREEN" "     Temporary Password: $ADMIN_TEMP_PASSWORD"
    print_message "$GREEN" "     Email: $ADMIN_EMAIL"
    print_message "$YELLOW" "  ⚠️  You will be required to change this password on first login"
    print_message "$YELLOW" "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_message "$YELLOW" "  💡 To retrieve credentials later, run:"
    if [[ -n "$AWS_PROFILE" ]]; then
      print_message "$YELLOW" "     aws cloudformation describe-stacks --stack-name $STACK_NAME --profile $AWS_PROFILE --query \"Stacks[0].Outputs\""
    else
      print_message "$YELLOW" "     aws cloudformation describe-stacks --stack-name $STACK_NAME --query \"Stacks[0].Outputs\""
    fi
    echo ""
  fi
  print_message "$YELLOW" "  1. Open the Admin Site URL in your browser"
  print_message "$YELLOW" "  2. Log in with the credentials shown above"
  print_message "$YELLOW" "  3. Follow the lab instructions to create tenants"
fi
print_message "$YELLOW" "  5. To retrieve URLs later: ./geturl.sh --stack-name $STACK_NAME"
print_message "$YELLOW" "  6. To clean up resources: ./cleanup.sh --stack-name $STACK_NAME"
echo ""
print_message "$GREEN" "Log file: $LOG_FILE"
