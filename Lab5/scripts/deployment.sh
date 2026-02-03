#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Get the directory where the script is located and change to it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified
SHARED_STACK_NAME="serverless-saas-shared-lab5"
PIPELINE_STACK_NAME="serverless-saas-pipeline-lab5"
DEPLOY_SERVER=0
DEPLOY_BOOTSTRAP=0
DEPLOY_PIPELINE=0
DEPLOY_CLIENT=0

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to build AWS CLI profile argument
# Returns "--profile <profile>" if PROFILE is set, empty string otherwise
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --server              Deploy complete server (pipeline + bootstrap + tenant provisioning)"
    echo "  -b, --bootstrap           Deploy only bootstrap server code"
    echo "  -p, --pipeline            Deploy only CI/CD pipeline"
    echo "  -c, --client              Deploy client code (Admin, Landing, and App UIs)"
    echo "  --shared-stack <name>     Shared stack name (default: serverless-saas-shared-lab5)"
    echo "  --pipeline-stack <name>   Pipeline stack name (default: serverless-saas-pipeline-lab5)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <profile>       AWS profile to use (optional, uses machine's default if not specified)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s -c                                    # Deploy complete server and client"
    echo "  $0 -b                                       # Deploy only bootstrap infrastructure"
    echo "  $0 -p                                       # Deploy only pipeline"
    echo "  $0 -c --region us-east-1                    # Deploy client with custom region"
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
        -b|--bootstrap)
            DEPLOY_BOOTSTRAP=1
            shift
            ;;
        -p|--pipeline)
            DEPLOY_PIPELINE=1
            shift
            ;;
        -c|--client)
            DEPLOY_CLIENT=1
            shift
            ;;
        --shared-stack)
            SHARED_STACK_NAME=$2
            shift 2
            ;;
        --pipeline-stack)
            PIPELINE_STACK_NAME=$2
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
if [[ $DEPLOY_SERVER -eq 0 ]] && [[ $DEPLOY_BOOTSTRAP -eq 0 ]] && [[ $DEPLOY_PIPELINE -eq 0 ]] && [[ $DEPLOY_CLIENT -eq 0 ]]; then
    print_message "$RED" "Error: Must specify at least one deployment option (-s, -b, -p, or -c)"
    echo ""
    print_usage
    exit 1
fi

# Set PROFILE_ARG based on AWS_PROFILE for use in AWS CLI and SAM CLI commands
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# If server is selected, enable both pipeline and bootstrap
if [[ $DEPLOY_SERVER -eq 1 ]]; then
    DEPLOY_PIPELINE=1
    DEPLOY_BOOTSTRAP=1
fi

# Determine log file location based on execution context
if [[ -n "$E2E_TEST_MODE" ]]; then
    # E2E Test Mode: Skip logging (test framework handles it)
    LOG_FILE="/dev/null"
elif [[ -n "$GLOBAL_LOG_DIR" ]]; then
    # Global Scripts Mode: Write to global log directory
    LOG_FILE="$GLOBAL_LOG_DIR/lab5-deployment.log"
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
print_message "$BLUE" "Lab5 Deployment Script"
print_message "$BLUE" "=========================================="
echo "Log file: $LOG_FILE"
if [[ -n "$AWS_PROFILE" ]]; then
    echo "AWS Profile: $AWS_PROFILE"
else
    echo "AWS Profile: (using machine's default profile)"
fi
echo "AWS Region: $AWS_REGION"
echo "Shared Stack: $SHARED_STACK_NAME"
echo "Pipeline Stack: $PIPELINE_STACK_NAME"
echo ""

# Record start time
START_TIME=$(date +%s)

# Pre-deployment validation
print_message "$YELLOW" "Step 1: Validating prerequisites..."

# Check for Lab6 resources (conflict detection)
print_message "$YELLOW" "  Checking for Lab6 resource conflicts..."
PROFILE_ARG=$(get_profile_arg)
LAB6_PIPELINE_EXISTS=false
LAB6_SHARED_EXISTS=false

# Check for Lab6 pipeline stack
if aws cloudformation $PROFILE_ARG describe-stacks --stack-name "serverless-saas-pipeline-lab6" --region "$AWS_REGION" &> /dev/null; then
    LAB6_PIPELINE_EXISTS=true
    print_message "$YELLOW" "  ⚠ Warning: Lab6 pipeline stack exists (serverless-saas-pipeline-lab6)"
    print_message "$YELLOW" "    This may cause CDKToolkit conflicts during deployment"
    print_message "$YELLOW" "    Deployment will continue, but CDKToolkit may be shared between labs"
fi

# Check for Lab6 shared stack
if aws cloudformation $PROFILE_ARG describe-stacks --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION" &> /dev/null; then
    LAB6_SHARED_EXISTS=true
    print_message "$YELLOW" "  ⚠ Warning: Lab6 shared stack exists (serverless-saas-shared-lab6)"
    print_message "$YELLOW" "    This indicates Lab6 is currently deployed"
fi

if [[ "$LAB6_PIPELINE_EXISTS" == "false" ]] && [[ "$LAB6_SHARED_EXISTS" == "false" ]]; then
    print_message "$GREEN" "  ✓ No Lab6 resource conflicts detected"
fi
echo ""

print_message "$YELLOW" "Step 2: Validating prerequisites..."

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

# Check CDK CLI (required for pipeline)
if [[ $DEPLOY_PIPELINE -eq 1 ]] || [[ $DEPLOY_SERVER -eq 1 ]]; then
    if ! command -v cdk &> /dev/null; then
        print_message "$RED" "Error: AWS CDK CLI is not installed"
        print_message "$YELLOW" "Install with: npm install -g aws-cdk"
        exit 1
    fi
    print_message "$GREEN" "  ✓ AWS CDK CLI installed"
fi

# Check Python 3
if ! command -v python3 &> /dev/null; then
    print_message "$RED" "Error: Python 3 is not installed"
    exit 1
fi
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
print_message "$GREEN" "  ✓ Python installed (version: $PYTHON_VERSION)"

# Check Node.js (required for client and pipeline)
if [[ $DEPLOY_CLIENT -eq 1 ]] || [[ $DEPLOY_PIPELINE -eq 1 ]] || [[ $DEPLOY_SERVER -eq 1 ]]; then
    if ! command -v npm &> /dev/null; then
        print_message "$RED" "Error: npm is not installed"
        print_message "$YELLOW" "Install Node.js from: https://nodejs.org/"
        exit 1
    fi
    NODE_VERSION=$(node --version 2>&1)
    print_message "$GREEN" "  ✓ Node.js installed (version: $NODE_VERSION)"
fi

# Check Git (required for pipeline)
if [[ $DEPLOY_PIPELINE -eq 1 ]] || [[ $DEPLOY_SERVER -eq 1 ]]; then
    if ! command -v git &> /dev/null; then
        print_message "$RED" "Error: Git is not installed"
        exit 1
    fi
    print_message "$GREEN" "  ✓ Git installed"
fi

# Validate AWS credentials
print_message "$YELLOW" "  Validating AWS credentials..."
PROFILE_ARG=$(get_profile_arg)
if ! aws sts get-caller-identity $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
    print_message "$RED" "Error: AWS credentials not configured for profile: $AWS_PROFILE"
    print_message "$YELLOW" "Configure with: aws configure --profile $AWS_PROFILE"
    exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_ARG --region "$AWS_REGION" --query Account --output text)
print_message "$GREEN" "  ✓ AWS credentials valid"
print_message "$GREEN" "    Account: $ACCOUNT_ID"
print_message "$GREEN" "    Region: $AWS_REGION"
if [[ -n "$AWS_PROFILE" ]]; then
    print_message "$GREEN" "    Profile: $AWS_PROFILE"
fi

echo ""

# Check for Event Engine pre-provisioned resources
print_message "$YELLOW" "Step 3: Checking for Event Engine environment..."
IS_RUNNING_IN_EVENT_ENGINE=false 
PROFILE_ARG=$(get_profile_arg)
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation $PROFILE_ARG list-exports --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null || echo "")
if [[ ! -z "$PREPROVISIONED_ADMIN_SITE" ]]; then
  print_message "$GREEN" "  ✓ Workshop is running in WorkshopStudio/Event Engine"
  IS_RUNNING_IN_EVENT_ENGINE=true
  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
  APP_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG list-exports --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-AppBucket'].Value" --output text)
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --region "$AWS_REGION" --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)
else
  print_message "$GREEN" "  ✓ Running in standard AWS account"
fi
echo ""



if [[ $DEPLOY_PIPELINE -eq 1 ]]; then
  print_message "$YELLOW" "Step 4: Deploying CI/CD pipeline..."
  
  # Check if CDKToolkit stack exists and staging bucket is accessible
  print_message "$YELLOW" "  Checking CDKToolkit stack and staging bucket..."
  PROFILE_ARG=$(get_profile_arg)
  CDK_NEEDS_BOOTSTRAP=false
  
  # Check if CDKToolkit stack exists
  if ! aws cloudformation $PROFILE_ARG describe-stacks --stack-name "CDKToolkit" --region "$AWS_REGION" &> /dev/null; then
      print_message "$YELLOW" "  CDKToolkit stack not found"
      CDK_NEEDS_BOOTSTRAP=true
  else
      # CDKToolkit stack exists, but verify the staging bucket exists
      CDK_BUCKET="cdk-hnb659fds-assets-${ACCOUNT_ID}-${AWS_REGION}"
      if ! aws s3 $PROFILE_ARG ls "s3://${CDK_BUCKET}" --region "$AWS_REGION" &> /dev/null; then
          print_message "$YELLOW" "  CDKToolkit stack exists but staging bucket missing: $CDK_BUCKET"
          CDK_NEEDS_BOOTSTRAP=true
      else
          print_message "$GREEN" "  ✓ CDKToolkit stack and staging bucket verified"
      fi
  fi
  
  # Bootstrap CDK if needed
  if [[ "$CDK_NEEDS_BOOTSTRAP" == "true" ]]; then
      print_message "$YELLOW" "  Bootstrapping CDK..."
      if [[ -n "$AWS_PROFILE" ]]; then
        cdk bootstrap aws://${ACCOUNT_ID}/${AWS_REGION} --profile "$AWS_PROFILE" || {
            print_message "$RED" "Error: CDK bootstrap failed"
            print_message "$RED" "  This is required before deploying the pipeline"
            exit 1
        }
      else
        cdk bootstrap aws://${ACCOUNT_ID}/${AWS_REGION} || {
            print_message "$RED" "Error: CDK bootstrap failed"
            print_message "$RED" "  This is required before deploying the pipeline"
            exit 1
        }
      fi
      print_message "$GREEN" "  ✓ CDKToolkit bootstrapped successfully"
  fi
  
  # Create CodeCommit repository
  print_message "$YELLOW" "  Checking CodeCommit repository..."
  PROFILE_ARG=$(get_profile_arg)
  set +e  # Temporarily disable exit on error for repository check
  REPO=$(aws codecommit $PROFILE_ARG get-repository --repository-name aws-serverless-saas-workshop --region "$AWS_REGION" 2>&1)
  REPO_CHECK_EXIT_CODE=$?
  set -e  # Re-enable exit on error
  if [[ $REPO_CHECK_EXIT_CODE -ne 0 ]]; then
      print_message "$YELLOW" "  Creating CodeCommit repository: aws-serverless-saas-workshop"
      CREATE_REPO=$(aws codecommit $PROFILE_ARG create-repository \
          --repository-name aws-serverless-saas-workshop \
          --repository-description "Serverless SaaS workshop repository" \
          --region "$AWS_REGION")
      if [[ $? -eq 0 ]]; then
          print_message "$GREEN" "  ✓ Repository created"
          # Wait a few seconds for repository to be fully available
          print_message "$YELLOW" "  Waiting for repository to be ready..."
          sleep 5
      else
          print_message "$RED" "Error: Failed to create CodeCommit repository"
          exit 1
      fi
      
      REPO_URL="codecommit::${AWS_REGION}://aws-serverless-saas-workshop"
      git remote add cc $REPO_URL 2>/dev/null || git remote set-url cc $REPO_URL
  else
      print_message "$GREEN" "  ✓ Repository exists"
  fi
  
  # Push code to CodeCommit
  print_message "$YELLOW" "  Pushing code to CodeCommit..."
  
  # Navigate to git repository root (workshop directory)
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$GIT_ROOT" ]]; then
    print_message "$RED" "Error: Not in a git repository"
    exit 1
  fi
  
  CURRENT_BRANCH=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD)
  print_message "$YELLOW" "    Current branch: $CURRENT_BRANCH"
  print_message "$YELLOW" "    Git root: $GIT_ROOT"
  
  # Check for uncommitted changes
  if [[ -n $(git -C "$GIT_ROOT" status -s) ]]; then
    print_message "$YELLOW" "    ⚠ Warning: Uncommitted changes detected, committing now..."
    git -C "$GIT_ROOT" add -A
    git -C "$GIT_ROOT" commit -m "chore: Auto-commit before Lab5 deployment"
  fi
  
  # Push to CodeCommit
  # Export AWS_PROFILE for git-remote-codecommit (required for authentication)
  if [[ -n "$AWS_PROFILE" ]]; then
    export AWS_PROFILE
  fi
  REPO_URL="codecommit::${AWS_REGION}://aws-serverless-saas-workshop"
  git -C "$GIT_ROOT" remote set-url cc $REPO_URL 2>/dev/null || git -C "$GIT_ROOT" remote add cc $REPO_URL
  git -C "$GIT_ROOT" push cc $CURRENT_BRANCH:main --force
  if [[ $? -eq 0 ]]; then
    print_message "$GREEN" "  ✓ Code pushed to CodeCommit main branch"
  else
    print_message "$RED" "Error: Failed to push code to CodeCommit"
    exit 1
  fi
  
  # Deploy pipeline with CDK
  print_message "$YELLOW" "  Building and deploying pipeline with CDK..."
  cd ../server/TenantPipeline/ || exit
  
  print_message "$YELLOW" "  Cleaning previous npm installation for TenantPipeline..."
  rm -rf node_modules package-lock.json || true
  
  npm install || {
      print_message "$RED" "Error: npm install failed"
      exit 1
  }
  
  npm run build || {
      print_message "$RED" "Error: npm build failed"
      exit 1
  }
  
  print_message "$YELLOW" "  Deploying CDK stack..."
  if [[ -n "$AWS_PROFILE" ]]; then
    cdk deploy --profile "$AWS_PROFILE" --require-approval never --region "$AWS_REGION" || {
        print_message "$RED" "Error: CDK deploy failed"
        print_message "$RED" "  Fetching CloudFormation stack events for diagnosis..."
        
        # Log stack events for the pipeline stack
        PROFILE_ARG=$(get_profile_arg)
        STACK_EVENTS=$(aws cloudformation $PROFILE_ARG describe-stack-events \
            --stack-name "$PIPELINE_STACK_NAME" \
            --region "$AWS_REGION" \
            --max-items 20 \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED` || ResourceStatus==`DELETE_FAILED`].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
            --output table 2>/dev/null || echo "Could not retrieve stack events")
        
        if [[ "$STACK_EVENTS" != "Could not retrieve stack events" ]]; then
            print_message "$RED" "  Recent failure events:"
            echo "$STACK_EVENTS"
        else
            print_message "$YELLOW" "  Could not retrieve stack events (stack may not exist yet)"
        fi
        
        exit 1
    }
  else
    cdk deploy --require-approval never --region "$AWS_REGION" || {
        print_message "$RED" "Error: CDK deploy failed"
        print_message "$RED" "  Fetching CloudFormation stack events for diagnosis..."
        
        # Log stack events for the pipeline stack
        PROFILE_ARG=$(get_profile_arg)
        STACK_EVENTS=$(aws cloudformation $PROFILE_ARG describe-stack-events \
            --stack-name "$PIPELINE_STACK_NAME" \
            --region "$AWS_REGION" \
            --max-items 20 \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED` || ResourceStatus==`DELETE_FAILED`].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
            --output table 2>/dev/null || echo "Could not retrieve stack events")
        
        if [[ "$STACK_EVENTS" != "Could not retrieve stack events" ]]; then
            print_message "$RED" "  Recent failure events:"
            echo "$STACK_EVENTS"
        else
            print_message "$YELLOW" "  Could not retrieve stack events (stack may not exist yet)"
        fi
        
        exit 1
    }
  fi
  
  cd ../../scripts || exit
  
  print_message "$GREEN" "  ✓ Pipeline deployed successfully"
  echo ""
fi

if [[ $DEPLOY_BOOTSTRAP -eq 1 ]]; then
  STEP_NUM=$((DEPLOY_PIPELINE + 4))
  print_message "$YELLOW" "Step $STEP_NUM: Deploying bootstrap server infrastructure..."
  
  cd ../server || exit
  
  # Get SAM S3 bucket from shared-samconfig.toml
  SHARED_SAM_BUCKET=$(grep s3_bucket shared-samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")
  
  if [[ -z "$SHARED_SAM_BUCKET" ]]; then
    print_message "$RED" "Error: No SAM bucket specified in shared-samconfig.toml"
    print_message "$YELLOW" "Please add s3_bucket value to shared-samconfig.toml"
    exit 1
  fi
  
  # Check if bucket exists, create if needed
  print_message "$YELLOW" "  Checking SAM deployment bucket: $SHARED_SAM_BUCKET"
  PROFILE_ARG=$(get_profile_arg)
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
  
  # Validate Python code
  print_message "$YELLOW" "  Validating Python code with pylint..."
  
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
    print_message "$GREEN" "  ✓ Code validation passed"
  else
    print_message "$YELLOW" "  Warning: pylint not installed, skipping code validation"
  fi
  
  # Build SAM application
  print_message "$YELLOW" "  Building SAM application..."
  # Build without container since Python 3.14 is available locally
  # SAM will use the local Python 3.14 installation instead of Docker/Finch
  sam build -t shared-template.yaml || {
      print_message "$RED" "Error: SAM build failed"
      exit 1
  }
  print_message "$GREEN" "  ✓ SAM build completed"
  
  # Check if API Gateway CloudWatch role already exists
  print_message "$YELLOW" "  Checking for existing API Gateway CloudWatch role..."
  CREATE_CLOUDWATCH_ROLE="true"
  PROFILE_ARG=$(get_profile_arg)
  if aws iam get-role --role-name apigateway-cloudwatch-publish-role $PROFILE_ARG --region "$AWS_REGION" >/dev/null 2>&1; then
    CREATE_CLOUDWATCH_ROLE="false"
    print_message "$GREEN" "  ✓ API Gateway CloudWatch role already exists, skipping creation"
  else
    print_message "$YELLOW" "  API Gateway CloudWatch role does not exist, will create it"
  fi
  
  # Deploy SAM application
  print_message "$YELLOW" "  Deploying shared infrastructure stack: $SHARED_STACK_NAME"
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = true ]; then
    sam deploy \
        $PROFILE_ARG \
        --config-file shared-samconfig.toml \
        --region "$AWS_REGION" \
        --stack-name "$SHARED_STACK_NAME" \
        --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL TenantUserPoolCallbackURLParameter=$APP_SITE_URL \
        --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
    }
  else
    sam deploy \
        $PROFILE_ARG \
        --config-file shared-samconfig.toml \
        --region "$AWS_REGION" \
        --stack-name "$SHARED_STACK_NAME" \
        --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE CreateCloudWatchRole=$CREATE_CLOUDWATCH_ROLE \
        --no-fail-on-empty-changeset || {
        print_message "$RED" "Error: SAM deployment failed"
        exit 1
    }
  fi
  print_message "$GREEN" "  ✓ Shared infrastructure deployed"
  
  # Wait for DynamoDB tables
  print_message "$YELLOW" "  Waiting for DynamoDB tables to be active..."
  PROFILE_ARG=$(get_profile_arg)
  for table in "ServerlessSaaS-Settings-lab5" "ServerlessSaaS-TenantStackMapping-lab5" "ServerlessSaaS-TenantDetails-lab5" "ServerlessSaaS-TenantUserMapping-lab5"; do
    print_message "$YELLOW" "    Checking $table..."
    aws dynamodb $PROFILE_ARG wait table-exists --table-name $table --region "$AWS_REGION" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      print_message "$GREEN" "    ✓ $table is active"
    else
      print_message "$YELLOW" "    ⚠ Warning: Could not verify $table status"
    fi
  done
  print_message "$GREEN" "  ✓ All DynamoDB tables are ready"
  
  cd ../scripts || exit
  echo ""
fi

# Get stack outputs if not in Event Engine
if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
  print_message "$YELLOW" "  Retrieving CloudFormation stack outputs..."
  PROFILE_ARG=$(get_profile_arg)
  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null || echo "")
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  APP_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text 2>/dev/null || echo "")
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null || echo "")
  print_message "$GREEN" "  ✓ Retrieved stack outputs"
fi



if [[ $DEPLOY_CLIENT -eq 1 ]]; then
  STEP_NUM=$((DEPLOY_PIPELINE + DEPLOY_BOOTSTRAP + 4))
  print_message "$YELLOW" "Step $STEP_NUM: Deploying client applications..."
  
  # Get CloudFormation outputs
  print_message "$YELLOW" "  Retrieving CloudFormation stack outputs..."
  PROFILE_ARG=$(get_profile_arg)
  ADMIN_APIGATEWAYURL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text 2>/dev/null || echo "")
  ADMIN_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
  LANDING_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text 2>/dev/null || echo "")
  ADMIN_USERPOOLID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolId'].OutputValue" --output text 2>/dev/null || echo "")
  ADMIN_APPCLIENTID=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name "$SHARED_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='CognitoOperationUsersUserPoolClientId'].OutputValue" --output text 2>/dev/null || echo "")
  
  if [[ -z "$ADMIN_APIGATEWAYURL" ]] || [[ "$ADMIN_APIGATEWAYURL" == "None" ]]; then
      print_message "$RED" "Error: Could not retrieve Admin API URL from CloudFormation stack"
      print_message "$YELLOW" "Make sure the bootstrap infrastructure is deployed first with -b flag"
      exit 1
  fi
  
  print_message "$GREEN" "  ✓ Retrieved stack outputs"
  
  # Verify all buckets are accessible
  print_message "$YELLOW" "  Verifying S3 buckets..."
  PROFILE_ARG=$(get_profile_arg)
  for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    if ! aws s3 $PROFILE_ARG ls "s3://$bucket" --region "$AWS_REGION" &> /dev/null; then
      print_message "$RED" "Error: S3 bucket not accessible: $bucket"
      exit 1
    fi
  done
  print_message "$GREEN" "  ✓ All S3 buckets verified"
  echo ""

  # Deploy Admin UI
  print_message "$YELLOW" "  Deploying Admin UI..."
  cd ../client/Admin || exit

  cat << EoF > ./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiUrl: '$ADMIN_APIGATEWAYURL'
};
EoF
  cat << EoF > ./src/environments/environment.ts
export const environment = {
  production: true,
  apiUrl: '$ADMIN_APIGATEWAYURL'
};
EoF

  print_message "$YELLOW" "  Configuring AWS Amplify for Admin UI"
  cat << EoF > ./src/aws-exports.ts
const awsmobile = {
  aws_project_region: '$AWS_REGION',
  aws_cognito_region: '$AWS_REGION',
  aws_user_pools_id: '$ADMIN_USERPOOLID',
  aws_user_pools_web_client_id: '$ADMIN_APPCLIENTID',
};

export default awsmobile;
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Admin UI..."
  rm -rf node_modules package-lock.json || true

  npm install --legacy-peer-deps || {
      print_message "$RED" "Error: npm install failed for Admin UI"
      exit 1
  }
  
  npm run build || {
      print_message "$RED" "Error: npm build failed for Admin UI"
      exit 1
  }

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist "s3://$ADMIN_SITE_BUCKET" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Admin UI to S3"
      exit 1
  }
  print_message "$GREEN" "  ✓ Admin UI deployed successfully"
  echo ""

  # Deploy Landing UI
  print_message "$YELLOW" "  Deploying Landing UI..."
  cd ../Landing || exit

  cat << EoF > ./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF
  cat << EoF > ./src/environments/environment.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for Landing UI..."
  rm -rf node_modules package-lock.json || true

  npm install --legacy-peer-deps || {
      print_message "$RED" "Error: npm install failed for Landing UI"
      exit 1
  }
  
  npm run build || {
      print_message "$RED" "Error: npm build failed for Landing UI"
      exit 1
  }

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist "s3://$LANDING_SITE_BUCKET" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload Landing UI to S3"
      exit 1
  }
  print_message "$GREEN" "  ✓ Landing UI deployed successfully"
  echo ""

  # Deploy App UI
  print_message "$YELLOW" "  Deploying App UI..."
  cd ../Application || exit

  cat << EoF > ./src/environments/environment.prod.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF
  cat << EoF > ./src/environments/environment.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$ADMIN_APIGATEWAYURL'
};
EoF

  print_message "$YELLOW" "  Cleaning previous npm installation for App UI..."
  rm -rf node_modules package-lock.json || true

  npm install --legacy-peer-deps || {
      print_message "$RED" "Error: npm install failed for App UI"
      exit 1
  }
  
  npm run build || {
      print_message "$RED" "Error: npm build failed for App UI"
      exit 1
  }

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist "s3://$APP_SITE_BUCKET" --region "$AWS_REGION" || {
      print_message "$RED" "Error: Failed to upload App UI to S3"
      exit 1
  }
  print_message "$GREEN" "  ✓ App UI deployed successfully"
  echo ""

  # Invalidate CloudFront caches
  print_message "$YELLOW" "  Invalidating CloudFront caches..."
  
  # Extract ShortId from bucket name to find matching distributions
  SHORTID=$(echo $APP_SITE_BUCKET | grep -oE '[a-f0-9]{8}$')
  
  if [ ! -z "$SHORTID" ]; then
    print_message "$YELLOW" "    Detected ShortId: $SHORTID"
    
    # Get distribution IDs for buckets with this ShortId
    DIST_IDS=$(aws cloudfront $PROFILE_ARG list-distributions --region "$AWS_REGION" --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, '$SHORTID')].Id" --output text 2>/dev/null)
    
    if [ ! -z "$DIST_IDS" ]; then
      for dist_id in $DIST_IDS; do
        print_message "$YELLOW" "    Invalidating distribution: $dist_id"
        aws cloudfront $PROFILE_ARG create-invalidation --distribution-id "$dist_id" --paths "/*" --region "$AWS_REGION" > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
          print_message "$GREEN" "      ✓ Invalidation created"
        else
          print_message "$YELLOW" "      ⚠ Could not invalidate (may not exist or no permissions)"
        fi
      done
      print_message "$GREEN" "  ✓ CloudFront cache invalidation completed"
    else
      print_message "$YELLOW" "  ⚠ No CloudFront distributions found for ShortId: $SHORTID"
      print_message "$YELLOW" "    CloudFront caches will clear automatically within 24 hours"
    fi
  else
    print_message "$YELLOW" "  ⚠ Could not detect ShortId from bucket name"
    print_message "$YELLOW" "    CloudFront caches will clear automatically within 24 hours"
  fi
  
  cd ../../scripts || exit
  echo ""
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MINUTES=$((DURATION / 60))
DURATION_SECONDS=$((DURATION % 60))

# Display deployment summary
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Lab5 Deployment Complete!"
print_message "$GREEN" "=========================================="
print_message "$GREEN" "Duration: ${DURATION_MINUTES}m ${DURATION_SECONDS}s"
echo ""

# Output URLs if available
if [[ ! -z "$ADMIN_SITE_URL" ]]; then
    print_message "$BLUE" "Application URLs:"
    print_message "$BLUE" "  Admin Site: https://$ADMIN_SITE_URL"
    print_message "$BLUE" "  Landing Site: https://$LANDING_APP_SITE_URL"
    print_message "$BLUE" "  App Site: https://$APP_SITE_URL"
    if [[ ! -z "$ADMIN_APIGATEWAYURL" ]]; then
        print_message "$BLUE" "  Admin API: $ADMIN_APIGATEWAYURL"
    fi
    echo ""
fi

print_message "$YELLOW" "Next Steps:"
if [[ $DEPLOY_PIPELINE -eq 1 ]] || [[ $DEPLOY_SERVER -eq 1 ]]; then
    print_message "$YELLOW" "  1. Monitor the pipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/$PIPELINE_STACK_NAME/view?region=$AWS_REGION"
fi
if [[ $DEPLOY_BOOTSTRAP -eq 1 ]] || [[ $DEPLOY_SERVER -eq 1 ]]; then
    print_message "$YELLOW" "  2. Access the Admin site to create tenants"
    print_message "$YELLOW" "  3. Check CloudFormation stacks for tenant deployments"
fi
if [[ $DEPLOY_CLIENT -eq 1 ]]; then
    print_message "$YELLOW" "  4. Open the application URLs in your browser"
fi
print_message "$YELLOW" "  5. To retrieve URLs later: ./geturl.sh --stack-name $SHARED_STACK_NAME"
print_message "$YELLOW" "  6. To clean up resources: ./cleanup.sh --region $AWS_REGION"
echo ""
print_message "$GREEN" "Log file: $LOG_FILE"
  
