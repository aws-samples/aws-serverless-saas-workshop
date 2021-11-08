#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c"
  echo "Command to deploy bootstrap server code: deployment.sh -b"
  echo "Command to deploy tenant server code: deployment.sh -t"
  echo "Command to deploy bootstrap & tenant server code: deployment.sh -s" 
  echo "Command to deploy server & client code: deployment.sh -s -c"
  exit 1      
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s) server=1 ;;
        -b) bootstrap=1 ;;
        -t) tenant=1 ;;
        -c) client=1 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ $server -eq 1 ]] || [[ $bootstrap -eq 1 ]] || [[ $tenant -eq 1 ]]; then
  echo "Validating server code using pylint"
  cd ../server
  python3 -m pylint -E -d E0401,E1111 $(find . -iname "*.py")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
  cd ../scripts
fi

if [[ $server -eq 1 ]] || [[ $bootstrap -eq 1 ]]; then
  echo "Bootstrap server code is getting deployed"
  cd ../server
  REGION=$(aws configure get region)
  sam build -t shared-template.yaml --use-container
  sam deploy --config-file shared-samconfig.toml --region=$REGION
  cd ../scripts
fi  

if [[ $server -eq 1 ]] || [[ $tenant -eq 1 ]]; then
  echo "Tenant server code is getting deployed"
  cd ../server
  REGION=$(aws configure get region)
  sam build -t tenant-template.yaml --use-container
  sam deploy --config-file tenant-samconfig.toml --region=$REGION
  cd ../scripts
fi

if [[ $client -eq 1 ]]; then
  # Admin UI and Landing UI are configured in Lab2 
  # App UI is configured in Lab3
  echo "Admin UI and Landing UI are configured in Lab2. App UI is configured in Lab3.
  So, no UI code is built in this Lab4"
  ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)


  echo "Admin site URL: https://$ADMIN_SITE_URL"
  echo "Landing site URL: https://$LANDING_APP_SITE_URL"
  echo "App site URL: https://$APP_SITE_URL"
  
fi  

