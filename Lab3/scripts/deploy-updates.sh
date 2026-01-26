#!/bin/bash

# AWS Profile should be passed via --profile parameter
AWS_PROFILE=""
AWS_REGION="us-east-1"
SHARED_STACK_NAME="serverless-saas-shared-lab3"
TENANT_STACK_NAME="serverless-saas-tenant-lab3"

# Function to build AWS CLI profile argument
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE --region $AWS_REGION"
    else
        echo "--region $AWS_REGION"
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy updates to Lab3 shared and tenant services"
    echo ""
    echo "Options:"
    echo "  --profile PROFILE    AWS profile to use (optional, uses default if not specified)"
    echo "  --region REGION      AWS region (default: us-east-1)"
    echo "  --help              Show this help message"
    exit 0
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        --region)
            AWS_REGION=$2
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [--profile <profile>] [--region <region>]"
            exit 1
            ;;
    esac
done

cd ../server || exit # stop execution if cd fails
rm -rf .aws-sam/

# Use virtual environment Python if available
if [ -f "../../.venv_py313/bin/python" ]; then
  PYTHON_CMD="../../.venv_py313/bin/python"
else
  PYTHON_CMD="python3"
fi

$PYTHON_CMD -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
#Deploying shared services changes
echo "Deploying shared services changes"  
PROFILE_ARG=$(get_profile_arg)
echo Y | sam sync $PROFILE_ARG --stack-name "$SHARED_STACK_NAME" -t shared-template.yaml --code --resource-id LambdaFunctions/ServerlessSaaSLayers --resource-id LambdaFunctions/SharedServicesAuthorizerFunction

#Deploying tenant services changes
echo "Deploying tenant services changes"
rm -rf .aws-sam/
echo Y | sam sync $PROFILE_ARG --stack-name "$TENANT_STACK_NAME" -t tenant-template.yaml --code --resource-id ServerlessSaaSLayers --resource-id BusinessServicesAuthorizerFunction --resource-id CreateProductFunction

cd ../scripts || exit
./geturl.sh $PROFILE_ARG