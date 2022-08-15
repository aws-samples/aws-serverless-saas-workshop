#!/bin/bash
##
## This script is to help create different kinds of tenants quickly.
##
## To use:
## bash create_tenants.sh myemail mydomain.com
##

EMAIL_ALIAS="$1"  # ex. test
EMAIL_DOMAIN="$2" # ex. test.com

echo "$(date) finding saas admin API GW url..."
next_token=""
while true; do
    if [[ "${next_token}" == "" ]]; then
        echo "$(date) making api call to search for saas admin API GWs..."
        response=$(aws apigateway get-rest-apis)
    else
        echo "$(date) making api call to search for saas admin API GWs..."
        response=$(aws apigateway get-rest-apis --starting-token "$next_token")
    fi

    api_gw_id=$(echo "$response" | jq -r '.items[] | select (.name | match("serverless-saas-admin-api")) | .id')
    if [[ "${api_gw_id}" != "" ]]; then
        echo "$(date) saas admin API rest id found!"
        # no need to look any further...
        break
    fi

    next_token=$(echo "$response" | jq '.NextToken')
    if [[ "${next_token}" == "null" ]]; then
        echo "$(date) no more API GWs left!"
        # no more results left. Exit loop...
        break
    fi
done

SAAS_ADMIN_URL_STAGE="prod"
CURRENT_REGION=$(aws configure get region || echo "$AWS_DEFAULT_REGION")
SAAS_ADMIN_URL="https://${api_gw_id}.execute-api.${CURRENT_REGION}.amazonaws.com/${SAAS_ADMIN_URL_STAGE}" # ex. https://m6slpkzugb.execute-api.us-west-2.amazonaws.com

echo "EMAIL_ALIAS=${EMAIL_ALIAS}"
echo "EMAIL_DOMAIN=${EMAIL_DOMAIN}"
echo "SAAS_ADMIN_URL=${SAAS_ADMIN_URL}"
echo "REGION=${CURRENT_REGION}"

read -rp "press any key to confirm above parameters and continue..."

echo "$(date) Creating a Standard tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/registration" \
    --header 'Content-Type: application/json' \
    --data-raw "{
    \"tenantName\": \"tenantstandardB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantstandardB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Standard\"
}"
echo "$(date) Done creating a Standard tenant!"

echo "$(date) Creating a Platinum tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/registration" \
    --header 'Content-Type: application/json' \
    --data-raw "{
    \"tenantName\": \"tenantplatinumB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantplatinumB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Platinum\"
}"
echo "$(date) Done creating a Platinum tenant!"

echo "$(date) Creating a Premium tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/registration" \
    --header 'Content-Type: application/json' \
    --data-raw "{
    \"tenantName\": \"tenantpremiumB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantpremiumB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Premium\"
}"
echo "$(date) Done creating a Premium tenant!"
