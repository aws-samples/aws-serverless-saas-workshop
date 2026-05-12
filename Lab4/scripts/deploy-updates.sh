#!/usr/bin/env bash
# =============================================================================
# deploy-updates.sh — Lab 4
# Syncs Lambda function code after the participant completes the TODOs.
#
# Works in both Case_A (Workshop Studio) and Case_B (self-guided).
# Uses `aws lambda update-function-code` directly — no SAM build needed.
#
# In Case_A the Lab 4 stack is already deployed by the Orchestration_Template.
# This script only pushes the participant's code edits to the existing
# Lambda functions. It does NOT recreate stacks, change URLs, or modify
# CloudFormation resources.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

AWS_REGION="us-east-1"
AWS_PROFILE=""

# Functions whose code the participant modifies in Lab 4 TODOs.
# Format: "function-name|source-subdirectory"
declare -a FUNCTIONS_TO_UPDATE=(
    "serverless-saas-lab4-business-services-authorizer|Resources"
    "serverless-saas-lab4-create-product|ProductService"
    "serverless-saas-lab4-get-product|ProductService"
    "serverless-saas-lab4-get-products|ProductService"
    "serverless-saas-lab4-update-product|ProductService"
    "serverless-saas-lab4-delete-product|ProductService"
    "serverless-saas-lab4-create-order|OrderService"
    "serverless-saas-lab4-get-order|OrderService"
    "serverless-saas-lab4-get-orders|OrderService"
    "serverless-saas-lab4-update-order|OrderService"
    "serverless-saas-lab4-delete-order|OrderService"
)

print_message() { echo -e "${1}${2}${NC}"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) AWS_PROFILE="$2"; shift 2 ;;
        --region)  AWS_REGION="$2"; shift 2 ;;
        *) print_message "$RED" "Unknown option: $1"; exit 1 ;;
    esac
done

aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    else
        aws --region "$AWS_REGION" "$@"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../server"

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab 4 — Deploy Code Updates"
print_message "$BLUE" "=========================================="
echo ""
print_message "$BLUE" "Region:  $AWS_REGION"
print_message "$BLUE" "Profile: ${AWS_PROFILE:-instance profile / env credentials}"
echo ""

# Step 1: Validate Python code
print_message "$YELLOW" "Step 1: Validating Python code..."
PYTHON_CMD="python3"
if [ -f "$SERVER_DIR/../../.venv_py314/bin/python" ]; then
    PYTHON_CMD="$SERVER_DIR/../../.venv_py314/bin/python"
fi

if command -v pylint &> /dev/null; then
    $PYTHON_CMD -m pylint -E -d E0401,E1111 $(find "$SERVER_DIR" -iname "*.py" -not -path "*/.aws-sam/*") || {
        print_message "$RED" "ERROR: Fix the code errors above and rerun."
        exit 1
    }
    print_message "$GREEN" "✓ Code validation passed"
else
    print_message "$YELLOW" "⚠ pylint not installed, skipping validation"
fi
echo ""

# Step 2: Pre-flight
print_message "$YELLOW" "Step 2: Pre-flight — checking Lab 4 deployment..."
CANARY="serverless-saas-lab4-business-services-authorizer"
if ! aws_cmd lambda get-function --function-name "$CANARY" \
        --query 'Configuration.FunctionName' --output text > /dev/null 2>&1; then
    print_message "$RED" "ERROR: Lab 4 does not appear to be deployed."
    print_message "$YELLOW" "  Could not find Lambda function: $CANARY"
    exit 1
fi
print_message "$GREEN" "✓ Lab 4 is deployed"
echo ""

# Step 3: Package and update each function
print_message "$YELLOW" "Step 3: Updating Lambda function code..."

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

PYTHON_CMD="python3"
if [ -f "$SERVER_DIR/../../.venv_py314/bin/python" ]; then
    PYTHON_CMD="$SERVER_DIR/../../.venv_py314/bin/python"
fi

FAILED=0
for entry in "${FUNCTIONS_TO_UPDATE[@]}"; do
    IFS='|' read -r func_name source_dir <<< "$entry"
    zip_file="$TEMP_DIR/${func_name}.zip"
    stage_dir="$TEMP_DIR/${func_name}_stage"
    mkdir -p "$stage_dir"

    print_message "$BLUE" "  Packaging $func_name..."

    # 1. Install pip dependencies for this service (if requirements.txt exists)
    if [[ -f "$SERVER_DIR/$source_dir/requirements.txt" ]]; then
        $PYTHON_CMD -m pip install \
            --quiet --disable-pip-version-check --no-color --no-warn-conflicts \
            --target "$stage_dir" \
            -r "$SERVER_DIR/$source_dir/requirements.txt" 2>/dev/null || true
    fi

    # 2. Copy the service source code on top
    cp -R "$SERVER_DIR/$source_dir"/*.py "$stage_dir/" 2>/dev/null || true
    for item in "$SERVER_DIR/$source_dir"/*/; do
        [[ -d "$item" ]] || continue
        [[ "$(basename "$item")" == "__pycache__" ]] && continue
        cp -R "$item" "$stage_dir/"
    done

    # 3. Include layers/ content (shared utilities: logger, metrics_manager, auth_manager, utils)
    if [[ -d "$SERVER_DIR/layers" ]]; then
        cp -R "$SERVER_DIR/layers"/*.py "$stage_dir/" 2>/dev/null || true
    fi

    # 4. Zip it
    (cd "$stage_dir" && zip -qr "$zip_file" . -x "*.pyc" "__pycache__/*" "requirements.txt")

    print_message "$BLUE" "  Deploying $func_name..."
    if aws_cmd lambda update-function-code \
        --function-name "$func_name" \
        --zip-file "fileb://$zip_file" \
        --query 'FunctionName' --output text > /dev/null 2>&1; then
        print_message "$GREEN" "  ✓ $func_name updated"
    else
        print_message "$RED" "  ✗ Failed to update $func_name"
        ((FAILED++))
    fi
done

echo ""
if [[ $FAILED -gt 0 ]]; then
    print_message "$RED" "$FAILED function(s) failed."
    exit 1
fi

print_message "$GREEN" "=========================================="
print_message "$GREEN" "✓ All Lambda functions updated successfully!"
print_message "$GREEN" "=========================================="
echo ""
print_message "$BLUE" "The code changes are now live. Test them by:"
print_message "$BLUE" "  1. Opening the Lab 4 Application URL"
print_message "$BLUE" "  2. Logging in as tenant2-admin"
print_message "$BLUE" "  3. Creating a product and testing cross-tenant access"
echo ""
