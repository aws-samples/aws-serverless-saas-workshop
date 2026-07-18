#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c --email <email address>"
  echo "Command to deploy server code: deployment.sh -s --email <email address>"
  echo "Command to deploy server & client code: deployment.sh -s -c --email <email address>"
  exit 1
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -s) server=1 ;;
  -c) client=1 ;;
  --email)
    email=$2
    shift
    ;;
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

# Get UI resources from shared stack exports
ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
ADMIN_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminSiteBucket'].Value" --output text)
LANDING_APP_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSiteBucket'].Value" --output text)

if [ -z "$ADMIN_SITE_URL" ]; then
  echo "Shared infrastructure not found. Deploying from Lab1..."
  cd ../../Lab1/server || exit
  sam build -t shared-template.yaml
  sam deploy --config-file shared-samconfig.toml --region="$REGION"
  cd ../../Lab2/scripts || exit
  # Re-read exports
  ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
  ADMIN_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminSiteBucket'].Value" --output text)
  LANDING_APP_SITE_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSiteBucket'].Value" --output text)
fi

if [[ $server -eq 1 ]]; then
  echo "Server code is getting deployed"

  cd ../server || exit # stop execution if cd fails

  DEFAULT_SAM_S3_BUCKET=$(grep s3_bucket samconfig.toml | cut -d'=' -f2 | cut -d \" -f2)
  echo "aws s3 ls s3://$DEFAULT_SAM_S3_BUCKET"
  if ! aws s3 ls "s3://${DEFAULT_SAM_S3_BUCKET}"; then
    echo "S3 Bucket: $DEFAULT_SAM_S3_BUCKET specified in samconfig.toml is not readable.
      So creating a new S3 bucket and will update samconfig.toml with new bucket name."

    UUID=$(uuidgen | awk '{print tolower($0)}')
    SAM_S3_BUCKET=sam-bootstrap-bucket-$UUID
    aws s3 mb "s3://${SAM_S3_BUCKET}" --region "$REGION"
    aws s3api put-bucket-encryption \
      --bucket "$SAM_S3_BUCKET" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    if [[ $? -ne 0 ]]; then
      exit 1
    fi
    # Updating all labs samconfig.toml with new bucket name
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab3/server/samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab3/server/tenant-samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab4/server/samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab4/server/tenant-samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab5/server/samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab5/server/tenant-samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab6/server/samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab6/server/tenant-samconfig.toml
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' ../../Lab7/samconfig.toml
  fi

  echo "Validating server code using pylint"
  python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi

  sam build -t template.yaml
  sam deploy --config-file samconfig.toml --region="$REGION"

  cd ../scripts || exit # stop execution if cd fails
fi

if [[ $client -eq 1 ]]; then
  if [[ -z "$email" ]]; then
    echo "Please provide email address to setup an admin user"
    echo "Note: Invoke script without parameters to know the list of script parameters"
    exit 1
  fi
  echo "Client code is getting deployed"

  ADMIN_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text)
  ADMIN_APPCLIENTID=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-CognitoOperationUsersUserPoolClientId'].Value" --output text)
  ADMIN_USERPOOL_ID=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-CognitoOperationUsersUserPoolId'].Value" --output text)

  # Create admin-user in OperationUsers userpool with given input email address
  CREATE_ADMIN_USER=$(aws cognito-idp admin-create-user \
  --user-pool-id "$ADMIN_USERPOOL_ID" \
  --username admin-user \
  --user-attributes Name=email,Value="$email" Name=email_verified,Value="True" Name=phone_number,Value="+11234567890" Name="custom:userRole",Value="SystemAdmin" Name="custom:tenantId",Value="system_admins" \
  --desired-delivery-mediums EMAIL)

  echo "$CREATE_ADMIN_USER"

  # Add admin-user to admin user group
  ADD_ADMIN_USER_TO_GROUP=$(aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$ADMIN_USERPOOL_ID" \
    --username admin-user \
    --group-name "SystemAdmins")

  echo "$ADD_ADMIN_USER_TO_GROUP"

  # Deploy Admin UI
  TMPDIR=$(mktemp -d)
  unzip -q "$STATIC_DIR/lab2-admin.zip" -d "$TMPDIR"
  find "$TMPDIR" -name "*.js" -exec sed -i \
    -e "s|__ADMIN_API_GATEWAY_URL__|${ADMIN_APIGATEWAYURL}|g" \
    -e "s|__AWS_REGION__|${REGION}|g" \
    -e "s|__ADMIN_USERPOOL_ID__|${ADMIN_USERPOOL_ID}|g" \
    -e "s|__ADMIN_APPCLIENTID__|${ADMIN_APPCLIENTID}|g" {} +
  aws s3 sync --delete --cache-control no-store "$TMPDIR" "s3://${ADMIN_SITE_BUCKET}"
  rm -rf "$TMPDIR"
  echo "Completed deploying Admin Client"

  # Deploy Landing UI
  TMPDIR=$(mktemp -d)
  unzip -q "$STATIC_DIR/lab2-landing.zip" -d "$TMPDIR"
  find "$TMPDIR" -name "*.js" -exec sed -i "s|__ADMIN_API_GATEWAY_URL__|${ADMIN_APIGATEWAYURL}|g" {} +
  aws s3 sync --delete --cache-control no-store "$TMPDIR" "s3://${LANDING_APP_SITE_BUCKET}"
  rm -rf "$TMPDIR"
  echo "Completed deploying Landing Client"

  echo "Successfully completed deploying Admin UI and Landing UI"
fi
echo "Admin site URL: https://$ADMIN_SITE_URL"
echo "Landing site URL: https://$LANDING_APP_SITE_URL"
