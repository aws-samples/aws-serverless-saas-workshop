#!/bin/bash
stackname="serverless-saas-workshop-lab1"

APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$stackname" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
echo "Application site URL: https://${APP_SITE_URL}"
