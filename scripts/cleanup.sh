#!/bin/bash
##
## This script aims to clean up resources created for the
## SaaS Serverless Workshop. This script is based on the guidance
## provided here:
## https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US/cleanup
##
## Note that this script can also be used to clean up resources for the
## Serverless SaaS Reference Solution as outlined here:
## https://github.com/aws-samples/aws-saas-factory-ref-solution-serverless-saas#steps-to-clean-up
##
##

# helper function
delete_stack_after_confirming() {
    if [[ -z "${1}" ]]; then
        echo "$(date) stack name missing..."
        return
    fi

    stack=$(aws cloudformation describe-stacks --stack-name "$1" --profile "$AWS_PROFILE")
    if [[ -z "${stack}" ]]; then
        echo "$(date) stack ${1} does not exist..."
        return
    fi

    if [[ -z "${skip_flag}" ]]; then
        read -p "Delete stack with name $1 [Y/n] " -n 1 -r
    fi

    if [[ $REPLY =~ ^[n]$ ]]; then
        echo "$(date) NOT deleting stack $1."
    else
        echo "$(date) deleting stack $1..."
        aws cloudformation delete-stack --stack-name "$1" --profile "$AWS_PROFILE"

        echo "$(date) waiting for stack delete operation to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$1" --profile "$AWS_PROFILE"
    fi
}

# helper function
delete_codecommit_repo_after_confirming() {
    REPO_NAME="$1"
    repo=$(aws codecommit get-repository --repository-name "$REPO_NAME" --profile "$AWS_PROFILE")
    if [[ -n "${repo}" ]]; then

        if [[ -z "${skip_flag}" ]]; then
            read -p "Delete codecommit repo with name \"$REPO_NAME\" [Y/n] " -n 1 -r
        fi

        if [[ $REPLY =~ ^[n]$ ]]; then
            echo "$(date) NOT deleting $REPO_NAME."
        else
            echo "$(date) deleting codecommit repo \"$REPO_NAME\"..."
            aws codecommit delete-repository --repository-name "$REPO_NAME" --profile "$AWS_PROFILE"
        fi
    else
        echo "$(date) repo \"$REPO_NAME\" does not exist..."
    fi
}

skip_flag='true'
interactive_flag=''
AWS_PROFILE=""

# Function to show help
show_help() {
    echo "Usage: $0 --profile <profile-name> [OPTIONS]"
    echo ""
    echo "Clean up all workshop resources including CloudFormation stacks, S3 buckets,"
    echo "CloudWatch log groups, Cognito user pools, and CodeCommit repositories."
    echo ""
    echo "Required:"
    echo "  --profile PROFILE    AWS profile to use"
    echo ""
    echo "Options:"
    echo "  -i                  Interactive mode (prompts before deletion)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --profile serverless-saas-demo"
    echo "  $0 --profile serverless-saas-demo -i"
    exit 0
}

while getopts 'i-:' flag; do
    case "${flag}" in
    i) 
        skip_flag=''
        interactive_flag='true'
        ;;
    -)
        case "${OPTARG}" in
        help)
            show_help
            ;;
        profile)
            AWS_PROFILE="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            ;;
        profile=*)
            AWS_PROFILE="${OPTARG#*=}"
            ;;
        *)
            echo "Unknown option --${OPTARG}" >&2
            exit 1
            ;;
        esac
        ;;
    *) echo "Unexpected option ${flag}!" && exit 1 ;;
    esac
done

# Validate profile is provided
if [[ -z "$AWS_PROFILE" ]]; then
    echo "Error: --profile parameter is required"
    echo "Usage: $0 --profile <profile-name> [-i]"
    echo "  --profile <name>  AWS CLI profile name (required)"
    echo "  -i                Interactive mode (prompts before deletion)"
    exit 1
fi

echo "$(date) Checking for prerequisites..."
jq --version || {
    echo "jq missing! Please install before using this script."
    exit 1
}
aws --version || {
    echo "ÅWS cli missing! Please install before using this script."
    exit 1
}
echo "$(date) Done checking for prerequisites."

echo "$(date) Cleaning up resources..."
if [[ -n "${skip_flag}" ]]; then
    echo "Automatic mode enabled. Script will not pause for confirmation before deleting resources!"
else
    echo "Interactive mode enabled. Script will pause for confirmation before deleting resources."
fi

delete_stack_after_confirming "serverless-saas-lab1"
delete_stack_after_confirming "stack-pooled"
delete_stack_after_confirming "serverless-saas-cost-per-tenant-lab7"

echo "$(date) cleaning up platinum tenants..."
next_token=""
STACK_STATUS_FILTER="CREATE_COMPLETE ROLLBACK_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE IMPORT_COMPLETE IMPORT_ROLLBACK_COMPLETE"
while true; do
    if [[ "${next_token}" == "" ]]; then
        echo "$(date) making api call to search for platinum tenants..."
        # shellcheck disable=SC2086
        # ignore shellcheck error for adding a quote as that causes the api call to fail
        response=$(aws cloudformation list-stacks --stack-status-filter $STACK_STATUS_FILTER --profile "$AWS_PROFILE")
    else
        echo "$(date) making api call to search for platinum tenants..."
        # shellcheck disable=SC2086
        # ignore shellcheck error for adding a quote as that causes the api call to fail
        response=$(aws cloudformation list-stacks --stack-status-filter $STACK_STATUS_FILTER --starting-token "$next_token" --profile "$AWS_PROFILE")
    fi

    tenant_stacks=$(echo "$response" | jq -r '.StackSummaries[].StackName | select(. | test("^stack-*"))')
    for i in $tenant_stacks; do
        delete_stack_after_confirming "$i"
    done

    next_token=$(echo "$response" | jq '.NextToken')
    if [[ "${next_token}" == "null" ]]; then
        echo "$(date) no more platinum tenants left."
        # no more results left. Exit loop...
        break
    fi
done

delete_stack_after_confirming "serverless-saas"
delete_stack_after_confirming "serverless-saas-pipeline"

# delete_codecommit_repo_after_confirming "aws-saas-factory-ref-serverless-saas"
delete_codecommit_repo_after_confirming "aws-serverless-saas-workshop"

echo "$(date) cleaning up buckets..."
for i in $(aws s3 ls --profile "$AWS_PROFILE" | awk '{print $3}' | grep -E "^serverless-saas-*|^sam-bootstrap-*"); do

    if [[ -z "${skip_flag}" ]]; then
        read -p "Delete bucket with name s3://${i} [Y/n] " -n 1 -r
    fi

    if [[ $REPLY =~ ^[n]$ ]]; then
        echo "$(date) NOT deleting bucket s3://${i}."
    else
        echo "$(date) emptying out s3 bucket with name s3://${i}..."
        aws s3 rm --recursive "s3://${i}" --profile "$AWS_PROFILE"

        echo "$(date) deleting s3 bucket with name s3://${i}..."
        aws s3 rb "s3://${i}" --profile "$AWS_PROFILE"
    fi
done

echo "$(date) cleaning up log groups..."
next_token=""
while true; do
    if [[ "${next_token}" == "" ]]; then
        response=$(aws logs describe-log-groups --profile "$AWS_PROFILE")
    else
        response=$(aws logs describe-log-groups --starting-token "$next_token" --profile "$AWS_PROFILE")
    fi

    # Updated pattern to include all workshop-related log groups:
    # - Lambda functions: /aws/lambda/stack-*, /aws/lambda/serverless-saas-*
    # - API Gateway: /aws/api-gateway/access-logs-serverless-saas-*
    # - Lab-specific patterns: serverless-saas-lab*
    log_groups=$(echo "$response" | jq -r '.logGroups[].logGroupName | select(. | test("^/aws/lambda/stack-*|^/aws/lambda/serverless-saas-*|^/aws/api-gateway/access-logs-serverless-saas-*|^/aws/lambda/.*-lab[1-7]|^/aws/lambda/create-product-pooled-lab|^/aws/lambda/update-product-pooled-lab|^/aws/lambda/get-products-pooled-lab"))')
    for i in $log_groups; do
        if [[ -z "${skip_flag}" ]]; then
            read -p "Delete log group with name $i [Y/n] " -n 1 -r
        fi

        if [[ $REPLY =~ ^[n]$ ]]; then
            echo "$(date) NOT deleting log group $i."
        else
            echo "$(date) deleting log group with name $i..."
            aws logs delete-log-group --log-group-name "$i" --profile "$AWS_PROFILE"
        fi
    done

    next_token=$(echo "$response" | jq '.NextToken')
    if [[ "${next_token}" == "null" ]]; then
        # no more results left. Exit loop...
        break
    fi
done

echo "$(date) cleaning up user pools..."
next_token=""
while true; do
    if [[ "${next_token}" == "" ]]; then
        response=$(aws cognito-idp list-user-pools --max-results 1 --profile "$AWS_PROFILE")
    else
        response=$(aws cognito-idp list-user-pools --max-results 1 --starting-token "$next_token" --profile "$AWS_PROFILE")
    fi

    pool_ids=$(echo "$response" | jq -r '.UserPools[] | select(.Name | test("^.*-ServerlessSaaSUserPool$")) |.Id')
    for i in $pool_ids; do
        if [[ -z "${skip_flag}" ]]; then
            read -p "Delete user pool with name $i [Y/n] " -n 1 -r
        fi

        if [[ $REPLY =~ ^[n]$ ]]; then
            echo "$(date) NOT deleting user pool $i."
        else
            echo "$(date) deleting user pool with name $i..."
            echo "getting pool domain..."
            pool_domain=$(aws cognito-idp describe-user-pool --user-pool-id "$i" --profile "$AWS_PROFILE" | jq -r '.UserPool.Domain')

            echo "deleting pool domain $pool_domain..."
            aws cognito-idp delete-user-pool-domain \
                --user-pool-id "$i" \
                --domain "$pool_domain" \
                --profile "$AWS_PROFILE"

            echo "deleting pool $i..."
            aws cognito-idp delete-user-pool --user-pool-id "$i" --profile "$AWS_PROFILE"
        fi
    done

    next_token=$(echo "$response" | jq '.NextToken')
    if [[ "${next_token}" == "null" ]]; then
        # no more results left. Exit loop...
        break
    fi
done

echo "$(date) Done cleaning up resources!"
