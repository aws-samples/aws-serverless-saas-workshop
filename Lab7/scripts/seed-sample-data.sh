#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# seed-sample-data.sh
# Generates real traffic against Lab3 pooled APIs to populate CloudWatch Logs
# for Lab7 cost attribution. Wait ~5 min after running for the EventBridge
# Scheduler to aggregate usage into TenantCostAndUsageAttribution-lab7.
#
# Usage: ./seed-sample-data.sh <bearer-token> [--profile <p>] [--iterations <n>]
# =============================================================================

AWS_PROFILE=""
ITERATIONS=20

print_usage() {
    cat <<EOF
Usage: $0 <bearer-token> [OPTIONS]

Generates traffic against Lab3 pooled API using a tenant's bearer token.
After running, wait ~5 min for the scheduled lambda to populate
TenantCostAndUsageAttribution-lab7.

Arguments:
  <bearer-token>    Tenant admin ID Token (from the SaaS app Auth Debug page)

Options:
  --profile <name>  AWS CLI profile
  --iterations <n>  Operations per type (default: 20)
  --help            Show this help
EOF
}

if [[ "$#" -eq 0 ]]; then
    echo "Error: Bearer token required"
    print_usage
    exit 1
fi

TOKEN=$1
shift

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile) AWS_PROFILE=$2; shift 2 ;;
        --iterations) ITERATIONS=$2; shift 2 ;;
        --help|-h) print_usage; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

PROFILE_ARG=""
[[ -n "$AWS_PROFILE" ]] && PROFILE_ARG="--profile $AWS_PROFILE"

# Resolve Lab3 tenant API Gateway URL from CloudFormation stacks
# In Case_A (Workshop Studio), the stack is a nested stack under serverless-saas-workshop-main
# In Case_B (self-guided), it might be serverless-saas-lab3-pooled or similar
echo "Resolving Lab3 Tenant API URL..."

# Allow override via environment variable
if [[ -n "${API_URL:-}" ]]; then
    echo "  Using API_URL from environment: ${API_URL}"
else
    # Find the Lab3TenantStack name (nested stack in Case_A)
    TENANT_STACK=$(aws cloudformation list-stacks ${PROFILE_ARG} \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, 'Lab3TenantStack')].StackName | [0]" \
        --output text 2>/dev/null || true)

    if [[ -n "$TENANT_STACK" ]] && [[ "$TENANT_STACK" != "None" ]]; then
        API_URL=$(aws cloudformation describe-stacks \
            --stack-name "${TENANT_STACK}" \
            --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue | [0]" \
            --output text ${PROFILE_ARG} 2>/dev/null || true)
    fi

    # Fallback: try Case_B stack name
    if [[ -z "${API_URL:-}" ]] || [[ "$API_URL" == "None" ]]; then
        API_URL=$(aws cloudformation describe-stacks \
            --stack-name serverless-saas-lab3-pooled \
            --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue | [0]" \
            --output text ${PROFILE_ARG} 2>/dev/null || true)
    fi

    if [[ -z "${API_URL:-}" ]] || [[ "$API_URL" == "None" ]]; then
        echo "Error: Could not resolve Lab3 Tenant API Gateway URL."
        echo ""
        echo "You can pass the URL manually:"
        echo "  API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com/prod $0 <token>"
        exit 1
    fi
fi

# Strip trailing slash
API_URL="${API_URL%/}"

echo "Lab3 API: ${API_URL}"
echo "Iterations: ${ITERATIONS}"
echo ""

AUTH_HEADER="Authorization: Bearer ${TOKEN}"
CT_HEADER="Content-Type: application/json"

created_product_ids=()

# --- Create products ---
echo "Creating ${ITERATIONS} products..."
for i in $(seq 1 ${ITERATIONS}); do
    RESPONSE=$(curl -s -X POST \
        -H "${AUTH_HEADER}" -H "${CT_HEADER}" \
        -d "{\"name\":\"Product-${i}\",\"sku\":\"SKU-${i}\",\"price\":$((i * 10)),\"category\":\"demo\"}" \
        "${API_URL}/product" || echo "")
    # Extract productId if present (tolerate shape differences)
    PID=$(echo "$RESPONSE" | grep -oE '"productId":"[^"]+"' | head -1 | sed 's/.*":"\([^"]*\)".*/\1/' || true)
    [[ -n "$PID" ]] && created_product_ids+=("$PID")
done
echo "  Created ${#created_product_ids[@]} products"

# --- List products (generates DynamoDB Scan operations) ---
echo "Listing products (${ITERATIONS}x)..."
for i in $(seq 1 ${ITERATIONS}); do
    curl -s -o /dev/null -X GET -H "${AUTH_HEADER}" "${API_URL}/products"
done

# --- Get single product (generates DynamoDB GetItem operations) ---
if [[ ${#created_product_ids[@]} -gt 0 ]]; then
    echo "Getting individual products (${ITERATIONS}x)..."
    for i in $(seq 1 ${ITERATIONS}); do
        IDX=$((i % ${#created_product_ids[@]}))
        PID="${created_product_ids[$IDX]}"
        curl -s -o /dev/null -X GET -H "${AUTH_HEADER}" "${API_URL}/product/${PID}"
    done
fi

# --- Create orders ---
echo "Creating ${ITERATIONS} orders..."
for i in $(seq 1 ${ITERATIONS}); do
    curl -s -o /dev/null -X POST \
        -H "${AUTH_HEADER}" -H "${CT_HEADER}" \
        -d "{\"orderName\":\"Order-${i}\",\"orderProducts\":[{\"productId\":\"demo\",\"price\":10,\"quantity\":1}]}" \
        "${API_URL}/order"
done

# --- List orders ---
echo "Listing orders (${ITERATIONS}x)..."
for i in $(seq 1 ${ITERATIONS}); do
    curl -s -o /dev/null -X GET -H "${AUTH_HEADER}" "${API_URL}/orders"
done

echo ""
echo "Done. Generated ~$((ITERATIONS * 5)) API invocations with tenant context."
echo ""
echo "Next steps:"
echo "  1. Wait ~5 minutes for the EventBridge Scheduler to trigger the"
echo "     Lab7 cost attribution lambdas."
echo "  2. Check the DynamoDB table: TenantCostAndUsageAttribution-lab7"
echo "  3. Inspect CloudWatch Logs for 'Request completed' entries in the"
echo "     /aws/lambda/serverless-saas-lab3-* log groups to see the tenant"
echo "     activity that the aggregation lambda consumes."
