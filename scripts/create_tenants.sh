#!/bin/bash
##
## This script is to help create different kinds of tenants quickly.
##

SAAS_ADMIN_URL="" # ex. https://m6slpkzugb.execute-api.us-west-2.amazonaws.com
EMAIL_ALIAS="" # ex. test
EMAIL_DOMAIN="" # ex. test.com

echo "Creating a Standard tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/prod/registration" \
--header 'Content-Type: application/json' \
--data-raw "{
    \"tenantName\": \"tenantstandardB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantstandardB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Standard\"
}"
echo "Done creating a Standard tenant!"

echo "Creating a Platinum tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/prod/registration" \
--header 'Content-Type: application/json' \
--data-raw "{
    \"tenantName\": \"tenantplatinumB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantplatinumB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Platinum\"
}"
echo "Done creating a Platinum tenant!"

echo "Creating a Premium tenant..."
curl --location --request POST "${SAAS_ADMIN_URL}/prod/registration" \
--header 'Content-Type: application/json' \
--data-raw "{
    \"tenantName\": \"tenantpremiumB\",
    \"tenantAddress\": \"123 street\",
    \"tenantEmail\": \"${EMAIL_ALIAS}+tenantpremiumB@${EMAIL_DOMAIN}\",
    \"tenantPhone\": \"1234567890\",
    \"tenantTier\": \"Premium\"
}"
echo "Done creating a Premium tenant!"
