#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c"
  echo "Command to deploy bootstrap server code: deployment.sh -b"
  echo "Command to deploy CI/CD pipeline code: deployment.sh -p"
  echo "Command to deploy CI/CD pipeline, bootstrap & tenant server code: deployment.sh -s" 
  echo "Command to deploy server & client code: deployment.sh -s -c"
  exit 1      
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s) server=1 ;;
        -b) bootstrap=1 ;;        
        -p) pipeline=1 ;;
        -c) client=1 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ $server -eq 1 ]] || [[ $pipeline -eq 1 ]]; then
  echo "CI/CD pipeline code is getting deployed"
  #Create CodeCommit repo
  REGION=$(aws configure get region)
  REPO=$(aws codecommit get-repository --repository-name aws-serverless-saas-workshop)
  if [[ $? -ne 0 ]]; then
      echo "aws-serverless-saas-workshop codecommit repo is not present, will create one now"
      CREATE_REPO=$(aws codecommit create-repository --repository-name aws-serverless-saas-workshop --repository-description "Serverless SaaS workshop repository")
      echo $CREATE_REPO
      REPO_URL="codecommit::${REGION}://aws-serverless-saas-workshop"
      git remote add cc $REPO_URL
      if [[ $? -ne 0 ]]; then
           echo "Setting url to remote cc"
           git remote set-url cc $REPO_URL
      fi
      git push --set-upstream cc main
  fi

  #Deploying CI/CD pipeline
  cd ../server/TenantPipeline/
  npm install && npm run build 
  cdk bootstrap  
  cdk deploy --require-approval never

  cd ../../scripts

fi

if [[ $server -eq 1 ]] || [[ $bootstrap -eq 1 ]]; then
  echo "Bootstrap server code is getting deployed"
  cd ../server
  REGION=$(aws configure get region)
  sam build -t shared-template.yaml --use-container
  sam deploy --config-file shared-samconfig.toml --region=$REGION

  cd ../scripts

fi

if [[ $client -eq 1 ]]; then
  echo "Client code is getting deployed"
  ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text)
  APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSiteBucket'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)


  ADMIN_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AdminApi'].OutputValue" --output text)
  
  # Admin UI and Landing UI are configured in Lab2 
  echo "Admin UI and Landing UI are configured in Lab2. Only App UI will be reconfigured in this Lab5."
  
  # Configuring app UI 

  echo "aws s3 ls s3://$APP_SITE_BUCKET"
  aws s3 ls s3://$APP_SITE_BUCKET 
  if [ $? -ne 0 ]; then
      echo "Error! S3 Bucket: $APP_SITE_BUCKET not readable"
      exit 1
  fi

  cd ../client/Application

  echo "Configuring environment for App Client"

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

  npm install && npm run build

  echo "aws s3 sync --delete --cache-control no-store dist s3://$APP_SITE_BUCKET"
  aws s3 sync --delete --cache-control no-store dist s3://$APP_SITE_BUCKET 

  if [[ $? -ne 0 ]]; then
      exit 1
  fi

  echo "Completed configuring environment for App Client"

  echo "Admin site URL: https://$ADMIN_SITE_URL"
  echo "Landing site URL: https://$LANDING_APP_SITE_URL"
  echo "App site URL: https://$APP_SITE_URL"
  echo "Successfully completed redeploying Application UI"

fi
