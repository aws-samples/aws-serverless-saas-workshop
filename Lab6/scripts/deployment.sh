#!/bin/bash

# Default values
AWS_PROFILE=""
server=0
bootstrap=0
pipeline=0
client=0

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s                Deploy complete server (pipeline + bootstrap)"
    echo "  -b                Deploy only bootstrap server code"
    echo "  -p                Deploy only CI/CD pipeline code"
    echo "  -c                Deploy client code"
    echo "  --profile <name>  AWS CLI profile name (optional, uses machine's default if not provided)"
    echo ""
    echo "Examples:"
    echo "  $0 -s -c --profile serverless-saas-demo"
    echo "  $0 -b --profile serverless-saas-demo"
    echo "  $0 -c --profile serverless-saas-demo"
    echo "  $0 -s -c    # Uses machine's default AWS profile"
}

if [[ "$#" -eq 0 ]]; then
  print_usage
  exit 1      
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s) server=1 ;;
        -b) bootstrap=1 ;;        
        -p) pipeline=1 ;;
        -c) client=1 ;;
        --profile)
            AWS_PROFILE=$2
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *) 
            echo "Unknown parameter passed: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
    shift
done

# Build AWS CLI profile argument if profile is specified
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Create log directory and file
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Lab6 Deployment Script"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo ""

# During AWS hosted events using event engine tool 
# we pre-provision cloudfront and s3 buckets which hosts UI code. 
# So that it improves this labs total execution time. 
# Below code checks if cloudfront and s3 buckets are 
# pre-provisioned or not and then concludes if the workshop 
# is running in AWS hosted event through event engine tool or not.
IS_RUNNING_IN_EVENT_ENGINE=false 
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  echo "Workshop is running in WorkshopStudio"
  IS_RUNNING_IN_EVENT_ENGINE=true
  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
  APP_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-AppBucket'].Value" --output text)
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)
fi



if [[ $server -eq 1 ]] || [[ $bootstrap -eq 1 ]]; then
  echo "=========================================="
  echo "Bootstrap server code is getting deployed"
  echo "=========================================="
  cd ../server
  REGION=$(aws configure get region $PROFILE_ARG)
  
  # Get SAM S3 bucket from shared-samconfig.toml
  SHARED_SAM_BUCKET=$(grep s3_bucket shared-samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")
  
  if [[ -z "$SHARED_SAM_BUCKET" ]]; then
    echo "✗ Error: No SAM bucket specified in shared-samconfig.toml"
    echo "  Please add s3_bucket value to shared-samconfig.toml"
    exit 1
  fi
  
  # Check if bucket exists, create if needed
  echo "Checking SAM deployment bucket: $SHARED_SAM_BUCKET"
  if ! aws s3 ls "s3://${SHARED_SAM_BUCKET}" $PROFILE_ARG --region "$REGION" &> /dev/null; then
    echo "  Bucket does not exist, creating: $SHARED_SAM_BUCKET"
    aws s3 mb "s3://${SHARED_SAM_BUCKET}" $PROFILE_ARG --region "$REGION"
    aws s3api put-bucket-encryption \
      $PROFILE_ARG \
      --bucket "$SHARED_SAM_BUCKET" \
      --region "$REGION" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    echo "  ✓ Created SAM deployment bucket: $SHARED_SAM_BUCKET"
  else
    echo "  ✓ SAM deployment bucket exists: $SHARED_SAM_BUCKET"
  fi
  echo ""
  
  echo "Validating server code using pylint"
  
  # Use virtual environment Python if available
  if [ -f "../../.venv_py313/bin/python" ]; then
    PYTHON_CMD="../../.venv_py313/bin/python"
  else
    PYTHON_CMD="python3"
  fi
  
  $PYTHON_CMD -m pylint -E -d E0401,E0606 $(find . -iname "*.py" -not -path "./.aws-sam/*" -not -path "./TenantPipeline/node_modules/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
  echo "✓ Code validation passed"
  echo ""

  echo "Building SAM template..."
  sam build -t shared-template.yaml
  if [[ $? -ne 0 ]]; then
    echo "✗ Error: SAM build failed"
    exit 1
  fi
  echo "✓ SAM build completed"
  echo ""
  
  echo "Deploying shared infrastructure stack..."
  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = true ]; then
    sam deploy $PROFILE_ARG --config-file shared-samconfig.toml --region=$REGION --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE AdminUserPoolCallbackURLParameter=$ADMIN_SITE_URL TenantUserPoolCallbackURLParameter=$APP_SITE_URL
  else
    sam deploy $PROFILE_ARG --config-file shared-samconfig.toml --region=$REGION --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE
  fi
  
  if [[ $? -ne 0 ]]; then
    echo "✗ Error: SAM deploy failed"
    exit 1
  fi
  echo "✓ Shared infrastructure deployed"
  echo ""
  
  # Wait for DynamoDB tables to be fully active before proceeding
  echo "Waiting for DynamoDB tables to be active..."
  for table in "ServerlessSaaS-Settings-lab6" "ServerlessSaaS-TenantStackMapping-lab6" "ServerlessSaaS-TenantDetails-lab6" "ServerlessSaaS-TenantUserMapping-lab6"; do
    echo "  Checking $table..."
    aws dynamodb $PROFILE_ARG wait table-exists --table-name $table
    if [[ $? -eq 0 ]]; then
      echo "  ✓ $table is active"
    else
      echo "  ⚠ Warning: Could not verify $table status"
    fi
  done
  echo "✓ All DynamoDB tables are ready"
  echo ""

  cd ../scripts

fi

# Deploy pipeline AFTER shared stack and DynamoDB tables are ready
if [[ $server -eq 1 ]] || [[ $pipeline -eq 1 ]]; then
  echo "=========================================="
  echo "CI/CD pipeline code is getting deployed"
  echo "=========================================="
  
  #Create CodeCommit repo
  REGION=$(aws configure get region $PROFILE_ARG)
  REPO=$(aws codecommit $PROFILE_ARG get-repository --repository-name aws-serverless-saas-workshop 2>&1)
  if [[ $? -ne 0 ]]; then
      echo "aws-serverless-saas-workshop codecommit repo is not present, will create one now"
      CREATE_REPO=$(aws codecommit $PROFILE_ARG create-repository --repository-name aws-serverless-saas-workshop --repository-description "Serverless SaaS workshop repository")
      echo $CREATE_REPO
      REPO_URL="codecommit::${REGION}://aws-serverless-saas-workshop"
      git remote add cc $REPO_URL
      if [[ $? -ne 0 ]]; then
           echo "Setting url to remote cc"
           git remote set-url cc $REPO_URL
      fi
  fi
  
  # Push current branch changes to CodeCommit main branch
  echo ""
  echo "Pushing latest code to CodeCommit..."
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "Current branch: $CURRENT_BRANCH"
  
  # Check if there are uncommitted changes
  if [[ -n $(git status -s) ]]; then
    echo "⚠ Warning: You have uncommitted changes. Committing them now..."
    git add -A
    git commit -m "chore: Auto-commit before Lab6 deployment"
  fi
  
  # Push current branch to CodeCommit main
  git push cc $CURRENT_BRANCH:main --force
  if [[ $? -eq 0 ]]; then
    echo "✓ Code pushed to CodeCommit main branch"
  else
    echo "✗ Error: Failed to push code to CodeCommit"
    exit 1
  fi
  echo ""

  #Deploying CI/CD pipeline
  cd ../server/TenantPipeline/
  print_message "$YELLOW" "  Cleaning previous npm installation for TenantPipeline..."
  rm -rf node_modules package-lock.json || true
  npm install && npm run build 
  cdk bootstrap  
  cdk deploy --require-approval never

  cd ../../scripts
  
  echo "✓ Pipeline deployed successfully"
  echo ""
  
  # Wait for pipeline to create the pooled stack
  echo "=========================================="
  echo "Waiting for pipeline to create pooled stack..."
  echo "=========================================="
  echo "The pipeline will automatically trigger and create stack-lab6-pooled"
  echo "This typically takes 5-10 minutes..."
  echo ""
  
  # Wait for pipeline execution to start
  sleep 30
  
  # Monitor pipeline execution
  MAX_WAIT=900  # 15 minutes
  ELAPSED=0
  INTERVAL=30
  
  while [ $ELAPSED -lt $MAX_WAIT ]; do
    PIPELINE_STATUS=$(aws codepipeline $PROFILE_ARG get-pipeline-state --name serverless-saas-pipeline-lab6 --region us-east-1 --query 'stageStates[?stageName==`Deploy`].latestExecution.status' --output text 2>/dev/null)
    
    if [ "$PIPELINE_STATUS" = "Succeeded" ]; then
      echo "✓ Pipeline Deploy stage completed successfully"
      break
    elif [ "$PIPELINE_STATUS" = "Failed" ]; then
      echo "⚠ Warning: Pipeline Deploy stage failed"
      echo "  You may need to manually trigger the pipeline"
      break
    elif [ ! -z "$PIPELINE_STATUS" ]; then
      echo "  Pipeline Deploy stage status: $PIPELINE_STATUS (waiting...)"
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠ Warning: Timeout waiting for pipeline"
    echo "  The pipeline may still be running. Check the console:"
    echo "  https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view"
  fi
  
  # Wait for pooled stack to be fully created
  echo ""
  echo "Waiting for stack-lab6-pooled to be ready..."
  aws cloudformation $PROFILE_ARG wait stack-create-complete --stack-name stack-lab6-pooled --region us-east-1 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "✓ stack-lab6-pooled is ready"
  else
    # Stack might already exist, check if it's in UPDATE_COMPLETE
    STACK_STATUS=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name stack-lab6-pooled --region us-east-1 --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
    if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
      echo "✓ stack-lab6-pooled is ready (status: $STACK_STATUS)"
    else
      echo "⚠ Warning: stack-lab6-pooled status: $STACK_STATUS"
      echo "  Continuing anyway, but tenant registration may fail until stack is ready"
    fi
  fi
  echo ""

fi

if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text)
  APP_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
fi



if [[ $client -eq 1 ]]; then
  echo "=========================================="
  echo "Client code deployment started"
  echo "=========================================="
  
  ADMIN_APIGATEWAYURL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text)
  ADMIN_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='AdminSiteBucket'].OutputValue" --output text)
  LANDING_SITE_BUCKET=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name serverless-saas-shared-lab6 --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSiteBucket'].OutputValue" --output text)
  
  # Verify all buckets are accessible
  echo "Verifying S3 buckets..."
  for bucket in "$ADMIN_SITE_BUCKET" "$LANDING_SITE_BUCKET" "$APP_SITE_BUCKET"; do
    aws s3 $PROFILE_ARG ls s3://$bucket > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Error! S3 Bucket: $bucket not readable"
      exit 1
    fi
  done
  echo "✓ All S3 buckets verified"
  echo ""

  # Check if Lab6 pre-built files exist (fallback for Node.js compatibility issues)
  USE_PREBUILT=false
  if [ -d "../client/Admin/dist" ] && [ -d "../client/Landing/dist" ] && [ -d "../client/Application/dist" ]; then
    echo ""
    echo "ℹ️  Lab6 pre-built client files detected"
    echo "   These can be used if Node.js build fails (Node.js v18 or earlier recommended)"
    USE_PREBUILT=true
  fi

  # Deploy Admin UI
  echo "=========================================="
  echo "Deploying Admin UI..."
  echo "=========================================="
  cd ../client/Admin
  
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

  # Try to build, fallback to pre-built if it fails
  USED_PREBUILT_ADMIN=false
  if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
    echo "Using pre-built files from Lab6..."
    USED_PREBUILT_ADMIN=true
  else
    print_message "$YELLOW" "  Cleaning previous npm installation for Admin Client..."
    rm -rf node_modules package-lock.json || true
    npm install --legacy-peer-deps && npm run build
    if [[ $? -ne 0 ]]; then
      if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
        echo "⚠️  Build failed, using pre-built files from Lab6..."
        USED_PREBUILT_ADMIN=true
      else
        echo "❌ Error building Admin UI and no pre-built files available"
        exit 1
      fi
    fi
  fi

  # Update API Gateway URL in pre-built files if they were used
  if [ "$USED_PREBUILT_ADMIN" = true ]; then
    echo "Updating API Gateway URL in pre-built files..."
    find dist -name "*.js" -type f -exec sed -i.bak "s|https://[a-z0-9]*\.execute-api\.[a-z0-9-]*\.amazonaws\.com/prod|$ADMIN_APIGATEWAYURL|g" {} \;
    find dist -name "*.js.bak" -type f -delete
    echo "✓ API Gateway URL updated"
  fi

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist s3://$ADMIN_SITE_BUCKET
  if [[ $? -ne 0 ]]; then
      echo "Error uploading Admin UI to S3"
      exit 1
  fi
  echo "✓ Admin UI deployed successfully"
  echo ""

  # Deploy Landing UI
  echo "=========================================="
  echo "Deploying Landing UI..."
  echo "=========================================="
  cd ../Landing

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

  # Try to build, fallback to pre-built if it fails
  USED_PREBUILT_LANDING=false
  if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
    echo "Using pre-built files from Lab6..."
    USED_PREBUILT_LANDING=true
  else
    print_message "$YELLOW" "  Cleaning previous npm installation for Landing Client..."
    rm -rf node_modules package-lock.json || true
    npm install --legacy-peer-deps && npm run build
    if [[ $? -ne 0 ]]; then
      if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
        echo "⚠️  Build failed, using pre-built files from Lab6..."
        USED_PREBUILT_LANDING=true
      else
        echo "❌ Error building Landing UI and no pre-built files available"
        exit 1
      fi
    fi
  fi

  # Update API Gateway URL in pre-built files if they were used
  if [ "$USED_PREBUILT_LANDING" = true ]; then
    echo "Updating API Gateway URL in pre-built files..."
    find dist -name "*.js" -type f -exec sed -i.bak "s|https://[a-z0-9]*\.execute-api\.[a-z0-9-]*\.amazonaws\.com/prod|$ADMIN_APIGATEWAYURL|g" {} \;
    find dist -name "*.js.bak" -type f -delete
    echo "✓ API Gateway URL updated"
  fi

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist s3://$LANDING_SITE_BUCKET
  if [[ $? -ne 0 ]]; then
      echo "Error uploading Landing UI to S3"
      exit 1
  fi
  echo "✓ Landing UI deployed successfully"
  echo ""

  # Deploy App UI
  echo "=========================================="
  echo "Deploying Application UI..."
  echo "=========================================="
  cd ../Application

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

  # Try to build, fallback to pre-built if it fails
  USED_PREBUILT_APP=false
  if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
    echo "Using pre-built files from Lab6..."
    USED_PREBUILT_APP=true
  else
    print_message "$YELLOW" "  Cleaning previous npm installation for App Client..."
    rm -rf node_modules package-lock.json || true
    npm install --legacy-peer-deps && npm run build
    if [[ $? -ne 0 ]]; then
      if [ "$USE_PREBUILT" = true ] && [ -d "dist" ]; then
        echo "⚠️  Build failed, using pre-built files from Lab6..."
        USED_PREBUILT_APP=true
      else
        echo "❌ Error building Application UI and no pre-built files available"
        exit 1
      fi
    fi
  fi

  # Update API Gateway URL in pre-built files if they were used
  if [ "$USED_PREBUILT_APP" = true ]; then
    echo "Updating API Gateway URL in pre-built files..."
    find dist -name "*.js" -type f -exec sed -i.bak "s|https://[a-z0-9]*\.execute-api\.[a-z0-9-]*\.amazonaws\.com/prod|$ADMIN_APIGATEWAYURL|g" {} \;
    find dist -name "*.js.bak" -type f -delete
    echo "✓ API Gateway URL updated"
  fi

  aws s3 $PROFILE_ARG sync --delete --cache-control no-store dist s3://$APP_SITE_BUCKET
  if [[ $? -ne 0 ]]; then
      echo "Error uploading App UI to S3"
      exit 1
  fi
  echo "✓ Application UI deployed successfully"
  echo ""

  # Invalidate CloudFront caches (async - don't wait)
  echo "=========================================="
  echo "Invalidating CloudFront caches..."
  echo "=========================================="
  
  # Extract ShortId from bucket name to find matching distributions
  SHORTID=$(echo $APP_SITE_BUCKET | grep -oE '[a-f0-9]{8}$')
  
  if [ ! -z "$SHORTID" ]; then
    echo "Detected ShortId: $SHORTID"
    
    # Get distribution IDs for buckets with this ShortId
    DIST_IDS=$(aws cloudfront $PROFILE_ARG list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, '$SHORTID')].Id" --output text)
    
    if [ ! -z "$DIST_IDS" ]; then
      for dist_id in $DIST_IDS; do
        echo "Invalidating CloudFront distribution: $dist_id (async)"
        aws cloudfront $PROFILE_ARG create-invalidation --distribution-id "$dist_id" --paths "/*" > /dev/null 2>&1 &
      done
      echo "✓ CloudFront cache invalidations initiated (running in background)"
    else
      echo "⚠ Warning: No CloudFront distributions found for ShortId: $SHORTID"
      echo "  CloudFront caches will clear automatically within 24 hours"
    fi
  else
    echo "⚠ Warning: Could not detect ShortId from bucket name"
    echo "  CloudFront caches will clear automatically within 24 hours"
  fi
  
  cd ../../scripts
  
  echo ""
  echo "=========================================="
  echo "✓ All client UIs deployed successfully!"
  echo "=========================================="

fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "Admin site URL: https://$ADMIN_SITE_URL"
echo "Landing site URL: https://$LANDING_APP_SITE_URL"
echo "App site URL: https://$APP_SITE_URL"
echo ""
echo "Next steps:"
echo "1. Access the Admin site to create tenants"
echo "2. Monitor the pipeline at: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view"
echo "3. Check CloudFormation stacks for tenant deployments"
echo "=========================================="
