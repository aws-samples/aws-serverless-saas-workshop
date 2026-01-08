PREPROVISIONED_ADMIN_SITE=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null)
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  echo "Workshop is running in WorkshopStudio"
  ADMIN_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text 2>/dev/null)
  LANDING_APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text 2>/dev/null)
  APP_SITE_URL=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text 2>/dev/null)

else
  # Check if stack exists before querying
  if aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab3 &>/dev/null; then
    ADMIN_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab3 --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text 2>/dev/null)
    LANDING_APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab3 --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text 2>/dev/null)
    APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas-workshop-shared-lab3 --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text 2>/dev/null)
  else
    ADMIN_SITE_URL=""
    LANDING_APP_SITE_URL=""
    APP_SITE_URL=""
  fi
fi

if [ ! -z "$ADMIN_SITE_URL" ]; then
  echo "Admin site URL: https://$ADMIN_SITE_URL"
else
  echo "Admin site URL: Not available"
fi

if [ ! -z "$LANDING_APP_SITE_URL" ]; then
  echo "Landing site URL: https://$LANDING_APP_SITE_URL"
else
  echo "Landing site URL: Not available"
fi

if [ ! -z "$APP_SITE_URL" ]; then
  echo "App site URL: https://$APP_SITE_URL"
else
  echo "App site URL: Not available"
fi
