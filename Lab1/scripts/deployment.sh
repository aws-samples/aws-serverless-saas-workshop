#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c"
  echo "Command to deploy server code: deployment.sh -s"
  echo "Command to deploy server & client code: deployment.sh -s -c"
  exit 1
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -s) server=1 ;;
  -c) client=1 ;;
  *)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
  shift
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
STATIC_DIR="$SCRIPT_DIR/../../static"

REGION=$(aws configure get region)

IS_RUNNING_IN_EVENT_ENGINE=false
PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  echo "Workshop is running in WorkshopStudio"
  IS_RUNNING_IN_EVENT_ENGINE=true
  APP_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSiteBucket'].Value" --output text)
  APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)
fi

if [[ $server -eq 1 ]]; then
  echo "Server code is getting deployed"
  cd ../server || exit

  if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
    # Phase 1: Deploy IDE if not already deployed
    IDE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name serverless-saas-ide \
      --query "Stacks[0].StackStatus" --output text --region "$REGION" 2>/dev/null)
    if [ -z "$IDE_STACK_STATUS" ] || [ "$IDE_STACK_STATUS" = "None" ]; then
      echo "Deploying VS Code IDE..."
      aws cloudformation deploy \
        --template-file ide-template.yaml \
        --stack-name serverless-saas-ide \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    fi

    IDE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas-ide \
      --query "Stacks[0].Outputs[?OutputKey=='IdeUrl'].OutputValue" --output text --region "$REGION")
    IDE_PASSWORD=$(aws cloudformation describe-stacks --stack-name serverless-saas-ide \
      --query "Stacks[0].Outputs[?OutputKey=='IdePassword'].OutputValue" --output text --region "$REGION")
    echo ""
    echo "============================================"
    echo "VS Code IDE URL: ${IDE_URL}"
    echo "VS Code IDE Password: ${IDE_PASSWORD}"
    echo "============================================"
    echo ""

    # Phase 2: Deploy shared infrastructure (Layer, Cognito, DDB, S3, CloudFront)
    echo "Deploying shared infrastructure..."
    sam build -t shared-template.yaml
    sam deploy --config-file shared-samconfig.toml --region="$REGION"
  fi

  echo "Validating server code using pylint"
  python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi

  sam build -t template.yaml
  sam deploy --config-file samconfig.toml --region="$REGION"
  cd ../scripts || exit
fi

if [ "$IS_RUNNING_IN_EVENT_ENGINE" = false ]; then
  APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
fi

APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='APIGatewayURL'].OutputValue" --output text)

if [[ $client -eq 1 ]]; then
  echo "Client code is getting deployed"

  if ! aws s3 ls "s3://${APP_SITE_BUCKET}" >/dev/null 2>&1; then
    echo "Error! S3 Bucket: $APP_SITE_BUCKET not readable"
    exit 1
  fi

  TMPDIR=$(mktemp -d)
  unzip -q "$STATIC_DIR/lab1-application.zip" -d "$TMPDIR"
  find "$TMPDIR" -name "*.js" -exec sed -i "s|__APP_API_GATEWAY_URL__|${APP_APIGATEWAYURL}|g" {} +
  aws s3 sync --delete --cache-control no-store "$TMPDIR" "s3://${APP_SITE_BUCKET}"
  rm -rf "$TMPDIR"

  echo "Completed deploying App Client"
fi

echo "Application site URL: https://${APP_SITE_URL}"
