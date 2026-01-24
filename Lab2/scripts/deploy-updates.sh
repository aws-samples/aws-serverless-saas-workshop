#!/bin/bash

# AWS Profile should be passed via --profile parameter
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified

# Function to build AWS CLI profile argument
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy updates to Lab2 shared services"
    echo ""
    echo "Options:"
    echo "  --profile PROFILE    AWS profile to use (optional, uses default if not specified)"
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
        --help)
            show_help
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [--profile <profile>]"
            exit 1
            ;;
    esac
done

cd ../server || exit # stop execution if cd fails
rm -rf .aws-sam/
python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
#Deploying shared services changes
echo "Deploying shared services changes" 
PROFILE_ARG=$(get_profile_arg)
echo Y | sam sync $PROFILE_ARG --stack-name serverless-saas --code --resource-id LambdaFunctions/CreateUserFunction --resource-id LambdaFunctions/RegisterTenantFunction --resource-id LambdaFunctions/GetTenantFunction -u

cd ../scripts || exit
./geturl.sh $PROFILE_ARG