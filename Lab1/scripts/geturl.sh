#!/bin/bash
PREPROVISIONED=$(aws cloudformation list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)
if [ ! -z "$PREPROVISIONED" ]; then
  APP_SITE_URL=$PREPROVISIONED
else
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
fi

echo "Application site URL: https://${APP_SITE_URL}"
