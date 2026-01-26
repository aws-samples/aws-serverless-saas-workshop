#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Test script for Lab2 registration endpoint

# AWS Profile should be passed via --profile parameter
AWS_PROFILE=""  # Empty by default - will use machine's default profile if not specified

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if API URL is provided
if [ -z "$1" ]; then
    print_message "$RED" "Error: API URL is required"
    echo "Usage: $0 <API_URL>"
    echo "Example: $0 https://wppwh3p97c.execute-api.us-west-2.amazonaws.com/prod"
    exit 1
fi

API_URL=$1

print_message "$YELLOW" "Testing registration endpoint..."
print_message "$YELLOW" "API URL: $API_URL/registration"
echo ""

# Test data
TENANT_DATA='{
  "tenantName": "Test Company",
  "tenantEmail": "test@example.com",
  "tenantTier": "basic",
  "tenantPhone": "555-0100",
  "tenantAddress": "123 Test St"
}'

print_message "$YELLOW" "Sending POST request with test data..."
echo ""

# Make the POST request
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$TENANT_DATA" \
  "$API_URL/registration")

# Extract HTTP status code
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo "Response Body:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_STATUS" -eq 200 ]; then
    print_message "$GREEN" "✓ Registration endpoint is working! (HTTP $HTTP_STATUS)"
else
    print_message "$RED" "✗ Registration failed with HTTP status: $HTTP_STATUS"
    
    # Provide helpful error messages
    case $HTTP_STATUS in
        403)
            print_message "$YELLOW" "This usually means:"
            echo "  - Missing Authentication Token error"
            echo "  - The endpoint path might be wrong"
            echo "  - Check if the stack is fully deployed"
            ;;
        500)
            print_message "$YELLOW" "This usually means:"
            echo "  - Lambda function error"
            echo "  - Check CloudWatch logs for details"
            ;;
        *)
            print_message "$YELLOW" "Check the response body above for details"
            ;;
    esac
fi

echo ""
print_message "$YELLOW" "To test in browser, you need to use a tool like:"
echo "  - Postman"
echo "  - Browser DevTools Console (fetch API)"
echo "  - curl command"
echo ""
print_message "$YELLOW" "Example curl command:"
echo "curl -X POST \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '$TENANT_DATA' \\"
echo "  $API_URL/registration"
