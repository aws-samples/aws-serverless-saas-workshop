#!/bin/bash

# AWS Profile should be passed via --profile parameter

# Default values
AWS_PROFILE=""
TOKEN=""

# Function to print usage
print_usage() {
    echo "Usage: $0 <bearer-token> [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  <bearer-token>    Bearer token for API authentication (required)"
    echo ""
    echo "Options:"
    echo "  --profile <name>  AWS CLI profile name (optional, uses machine's default if not provided)"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9... --profile serverless-saas-demo"
    echo "  $0 eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...    # Uses machine's default AWS profile"
}

# Check if at least one argument is provided
if [[ "$#" -eq 0 ]]; then
    echo "Error: Bearer token is required"
    echo ""
    print_usage
    exit 1
fi

# First argument is the bearer token
TOKEN=$1
shift

# Parse remaining command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
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

APP_APIGATEWAYURL=$(aws cloudformation $PROFILE_ARG describe-stacks --stack-name stack-lab6-pooled --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" --output text)

get_product() {
   
  STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X GET -H "Authorization: Bearer $1" -H "Content-Type: application/json" $APP_APIGATEWAYURL/products)
  
  echo "STATUS_CODE : $STATUS_CODE";
  
}

for i in $(seq 1 1000)
do
  get_product $TOKEN $i &
done
wait
echo "All done"