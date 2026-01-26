#!/bin/bash

# AWS Profile should be passed via --profile parameter

# Default values
AWS_PROFILE=""
STACK_NAME="serverless-saas-lab6"  # Default stack name
AWS_REGION="us-east-1"  # Default region

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stack-name <name>       CloudFormation stack name (default: serverless-saas-lab6)"
    echo "  --region <region>         AWS region (default: us-east-1)"
    echo "  --profile <name>          AWS CLI profile name (optional, uses machine's default if not provided)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Use default stack name"
    echo "  $0 --stack-name my-stack                        # Use custom stack name"
    echo "  $0 --profile serverless-saas-demo               # Use specific AWS profile"
    echo "  $0 --stack-name my-stack --profile my-profile   # Use custom stack name and profile"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

# Build AWS CLI profile argument if profile is specified
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

PREPROVISIONED_ADMIN_SITE=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
if [ ! -z "$PREPROVISIONED_ADMIN_SITE" ]; then
  echo "Workshop is running in WorkshopStudio"
  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-AdminAppSite'].Value" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-LandingApplicationSite'].Value" --output text)
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG list-exports --query "Exports[?Name=='Serverless-SaaS-ApplicationSite'].Value" --output text)

else

  ADMIN_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name $STACK_NAME --region $AWS_REGION --query "Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue" --output text)
  LANDING_APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name $STACK_NAME --region $AWS_REGION --query "Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name $STACK_NAME --region $AWS_REGION --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
fi

echo "Admin site URL: https://$ADMIN_SITE_URL"
echo "Landing site URL: https://$LANDING_APP_SITE_URL"
echo "App site URL: https://$APP_SITE_URL"