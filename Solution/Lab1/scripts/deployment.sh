#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c --stack-name <CloudFormation stack name>"
  echo "Command to deploy server code: deployment.sh -s --stack-name <CloudFormation stack name>" 
  echo "Command to deploy server & client code: deployment.sh -s -c --stack-name <CloudFormation stack name>"
  exit 1      
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s) server=1 ;;
        -c) client=1 ;;
        --stack-name)  stackname=$2 
          shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$stackname" ]]; then
    echo "Please provide CloudFormation stack name as parameter" 
    echo "Note: Invoke script without parameters to know the list of script parameters"
    exit 1  
fi

if [[ $server -eq 1 ]]; then
  echo "Server code is getting deployed"
  cd ../server
  REGION=$(aws configure get region)
  sam build -t template.yaml --use-container
  sam deploy --config-file samconfig.toml --region=$REGION --stack-name=$stackname
  cd ../scripts
fi

if [[ $client -eq 1 ]]; then
  echo "Client code is getting deployed"
  APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name $stackname --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name $stackname --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
  APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name $stackname --query "Stacks[0].Outputs[?OutputKey=='APIGatewayURL'].OutputValue" --output text)

  # Configuring application UI 

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
  apiGatewayUrl: '$APP_APIGATEWAYURL'
 };
EoF

 cat << EoF > ./src/environments/environment.ts
 export const environment = {
   production: true,
   apiGatewayUrl: '$APP_APIGATEWAYURL'
 };
EoF

 echo no | npm install && npm run build

 echo "aws s3 sync --delete --cache-control no-store dist s3://$APP_SITE_BUCKET"
 aws s3 sync --delete --cache-control no-store dist s3://$APP_SITE_BUCKET 

 if [[ $? -ne 0 ]]; then
     exit 1
 fi

 echo "Completed configuring environment for App Client"

 echo "Application site URL: https://$APP_SITE_URL"
fi



