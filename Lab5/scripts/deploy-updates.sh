#!/usr/bin/env bash
# =============================================================================
# deploy-updates.sh — Lab 5
# Syncs Lambda function code after the participant completes the TODOs.
#
# Works in both Case_A (Workshop Studio) and Case_B (self-guided).
# Uses `aws lambda update-function-code` directly.
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
AWS_REGION="us-east-1"
AWS_PROFILE=""

# Lambda functions to update (function-name → source directory relative to Lab5/server/)
# These are the functions whose code the participant modifies in Lab 5 TODOs.
declare -a FUNCTIONS_TO_UPDATE=(
    "serverless-saas-lab5-create-tenant-admin-user|TenantManagementService"
    "serverless-saas-lab5-provision-tenant|TenantManagementService"
)

print_message() {
    echo -e "${1}${2}${NC}"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploys code changes to Lab 5 Lambda functions after completing the TODOs.

Options:
  --profile <profile>   AWS CLI profile (optional; uses instance role if omitted)
  --region <region>     AWS region (default: us-east-1)
  --help                Show this help message

Examples:
  # Workshop Studio IDE (no profile needed)
  $0

  # Self-guided with a named profile
  $0 --profile my-profile
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) AWS_PROFILE="$2"; shift 2 ;;
        --region)  AWS_REGION="$2"; shift 2 ;;
        --help|-h) show_help ;;
        *) print_message "$RED" "Unknown option: $1"; show_help ;;
    esac
done

# AWS CLI wrapper
aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    else
        aws --region "$AWS_REGION" "$@"
    fi
}

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../server"

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab 5 — Deploy Code Updates"
print_message "$BLUE" "=========================================="
echo ""
print_message "$BLUE" "Region:  $AWS_REGION"
print_message "$BLUE" "Profile: ${AWS_PROFILE:-instance profile / env credentials}"
echo ""

# Determine log file location
if [[ -n "${E2E_TEST_MODE:-}" ]]; then
    LOG_FILE="/dev/null"
elif [[ -n "${GLOBAL_LOG_DIR:-}" ]]; then
    LOG_FILE="$GLOBAL_LOG_DIR/lab5-deploy-updates.log"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_DIR="$SCRIPT_DIR/logs/$TIMESTAMP"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/deploy-updates.log"
fi

# Redirect output to log + console (skip in test mode)
if [[ -z "${E2E_TEST_MODE:-}" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

# Step 1: Validate Python code
print_message "$YELLOW" "Step 1: Validating Python code..."
PYTHON_CMD="python3"
if [ -f "$SERVER_DIR/../../.venv_py314/bin/python" ]; then
    PYTHON_CMD="$SERVER_DIR/../../.venv_py314/bin/python"
fi

if command -v pylint &> /dev/null; then
    $PYTHON_CMD -m pylint -E -d E0401,E0606 $(find "$SERVER_DIR" -iname "*.py" -not -path "*/.aws-sam/*" -not -path "*/TenantPipeline/node_modules/*") || {
        print_message "$RED" "ERROR: Fix the code errors above and rerun."
        exit 1
    }
    print_message "$GREEN" "✓ Code validation passed"
else
    print_message "$YELLOW" "⚠ pylint not installed, skipping validation"
fi
echo ""

# Step 2: Package and update each function
print_message "$YELLOW" "Step 2: Updating Lambda functions..."

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

update_function() {
    local func_name="$1"
    local source_dir="$2"
    local zip_file="$TEMP_DIR/${func_name}.zip"

    print_message "$BLUE" "  Packaging $func_name..."

    # Create zip from the source directory
    (cd "$SERVER_DIR/$source_dir" && zip -qr "$zip_file" . -x "*.pyc" "__pycache__/*" ".aws-sam/*")

    # Include the layers/ directory content (shared utilities)
    if [[ -d "$SERVER_DIR/layers" ]]; then
        (cd "$SERVER_DIR/layers" && zip -qr "$zip_file" . -x "*.pyc" "__pycache__/*")
    fi

    print_message "$BLUE" "  Deploying $func_name..."
    if aws_cmd lambda update-function-code \
        --function-name "$func_name" \
        --zip-file "fileb://$zip_file" \
        --query 'FunctionName' --output text > /dev/null 2>&1; then
        print_message "$GREEN" "  ✓ $func_name updated"
    else
        print_message "$RED" "  ✗ Failed to update $func_name"
        print_message "$YELLOW" "    Check that the function exists and the IDE role has lambda:UpdateFunctionCode permission."
        return 1
    fi
}

FAILED=0
for entry in "${FUNCTIONS_TO_UPDATE[@]}"; do
    IFS='|' read -r func_name source_dir <<< "$entry"
    update_function "$func_name" "$source_dir" || ((FAILED++))
done

echo ""
if [[ $FAILED -gt 0 ]]; then
    print_message "$RED" "$FAILED function(s) failed to update."
    exit 1
fi

print_message "$GREEN" "=========================================="
print_message "$GREEN" "✓ All Lambda functions updated successfully!"
print_message "$GREEN" "=========================================="
echo ""
print_message "$BLUE" "The code changes are now live. Test them by:"
print_message "$BLUE" "  1. Opening the Lab 5 Admin application URL"
print_message "$BLUE" "  2. Logging in as admin"
print_message "$BLUE" "  3. Onboarding a new Platinum tier tenant"
echo ""
if [[ -z "${E2E_TEST_MODE:-}" ]]; then
    print_message "$BLUE" "Log file: $LOG_FILE"
fi
