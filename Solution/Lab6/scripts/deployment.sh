

echo "server code is getting deployed"
cd ../server
REGION=$(aws configure get region)

echo "Validating server code using pylint"
python3 -m pylint -E -d E0401 $(find . -iname "*.py")
if [[ $? -ne 0 ]]; then
  echo "****ERROR: Please fix above code errors and then rerun script!!****"
  exit 1
fi

sam build -t shared-template.yaml --use-container
sam deploy --config-file shared-samconfig.toml --region=$REGION

echo "Pooled tenant server code is getting deployed"
REGION=$(aws configure get region)
sam build -t tenant-template.yaml --use-container
sam deploy --config-file tenant-samconfig.toml --region=$REGION
cd ../scripts

ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text)
LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text)
APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)

echo "Admin site URL: https://$ADMIN_SITE_URL"
echo "Landing site URL: https://$LANDING_APP_SITE_URL"
echo "App site URL: https://$APP_SITE_URL"
  






