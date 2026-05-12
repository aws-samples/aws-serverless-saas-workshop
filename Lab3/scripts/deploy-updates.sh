#!/usr/bin/env bash
# =============================================================================
# deploy-updates.sh — Lab 3
# Syncs Lambda function code AND the shared layers after the participant
# completes the TODOs.
#
# Works in both Case_A (Workshop Studio) and Case_B (self-guided).
#
# Preconditions (checked by the pre-flight step):
#   - The Lab 3 stack has already been deployed — either by Workshop Studio
#     (Case_A) or by Lab3/scripts/deployment.sh (Case_B). The script fails
#     fast with a human-readable message if the Lab 3 Lambda functions are
#     not present.
#   - The caller's AWS identity has these Lambda permissions:
#       lambda:GetFunctionConfiguration
#       lambda:UpdateFunctionConfiguration
#       lambda:UpdateFunctionCode
#       lambda:PublishLayerVersion
#       lambda:ListLayerVersions
#       lambda:DeleteLayerVersion
#
# What this script does (in order):
#   1. Validates participant's Python code with pylint.
#   2. Verifies the Lab 3 Lambda functions exist (pre-flight).
#   3. Publishes NEW versions of both Lab 3 layers from Lab3/server/layers/.
#      This is what makes the participant's edits to metrics_manager.py,
#      logger.py, auth_manager.py reach the Lambda runtime; the runtime
#      loads them from /opt/python/ (the Layer mount) and
#      update-function-code alone does not affect that path.
#   4. Rotates the Layer ARN on every Lab 3 function. Uses
#      get-function-configuration first so other layers (notably
#      LambdaInsightsExtension) are preserved in the Layers array.
#   5. Waits for each affected function's configuration update to settle
#      via a LastUpdateStatus=Successful poll loop. Lambda rejects
#      concurrent code updates on a function whose config is still
#      InProgress, so skipping this causes ResourceConflictException.
#   6. Packages and uploads the modified function source code via
#      lambda update-function-code.
#   7. Prunes old Layer versions, keeping the 3 most recent as a rollback
#      window.
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
LAYER_VERSIONS_TO_KEEP=3

# Layers to republish
LAYER_NAMES=(
    "serverless-saas-dependencies-lab3"
    "serverless-saas-dependencies-pooled-lab3"
)

# Lambda functions whose code the participant modifies in Lab 3 TODOs.
# Format: "function-name|source-subdirectory|layer-name-to-rotate"
declare -a FUNCTIONS_TO_UPDATE=(
    "serverless-saas-lab3-shared-services-authorizer|Resources|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-business-services-authorizer|Resources|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-create-product|ProductService|serverless-saas-dependencies-pooled-lab3"
)

# Functions with no code change but share the same Layer. We rotate their
# Layer ARN so the refreshed /opt/python/ content is picked up on the next
# invocation.
declare -a FUNCTIONS_LAYER_ONLY=(
    "serverless-saas-lab3-get-product|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-get-products|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-update-product|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-delete-product|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-get-order|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-get-orders|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-create-order|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-update-order|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-delete-order|serverless-saas-dependencies-pooled-lab3"
    "serverless-saas-lab3-get-user|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-get-users|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-create-user|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-update-user|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-disable-user|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-disable-users-by-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-enable-users-by-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-create-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-get-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-get-tenants|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-update-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-activate-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-deactivate-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-register-tenant|serverless-saas-dependencies-lab3"
    "serverless-saas-lab3-create-tenant-admin-user|serverless-saas-dependencies-lab3"
)

print_message() {
    echo -e "${1}${2}${NC}"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploys code changes to Lab 3 Lambda functions and the shared Lambda Layers
after the participant completes the TODOs.

Options:
  --profile <profile>           AWS CLI profile (optional; uses instance role if omitted)
  --region <region>             AWS region (default: us-east-1)
  --keep-versions <n>           Layer versions to retain after pruning (default: 3)
  --help                        Show this help message

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
        --profile)        AWS_PROFILE="$2"; shift 2 ;;
        --region)         AWS_REGION="$2"; shift 2 ;;
        --keep-versions)  LAYER_VERSIONS_TO_KEEP="$2"; shift 2 ;;
        --help|-h)        show_help ;;
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
LAYERS_DIR="$SERVER_DIR/layers"

print_message "$BLUE" "=========================================="
print_message "$BLUE" "Lab 3 — Deploy Code Updates"
print_message "$BLUE" "=========================================="
echo ""
print_message "$BLUE" "Region:  $AWS_REGION"
print_message "$BLUE" "Profile: ${AWS_PROFILE:-instance profile / env credentials}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Validate Python code
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 1: Validating Python code..."
PYTHON_CMD="python3"
if [ -f "$SERVER_DIR/../../.venv_py314/bin/python" ]; then
    PYTHON_CMD="$SERVER_DIR/../../.venv_py314/bin/python"
fi

if command -v pylint &> /dev/null; then
    $PYTHON_CMD -m pylint -E -d E0401 $(find "$SERVER_DIR" -iname "*.py" -not -path "*/.aws-sam/*") || {
        print_message "$RED" "ERROR: Fix the code errors above and rerun."
        exit 1
    }
    print_message "$GREEN" "✓ Code validation passed"
else
    print_message "$YELLOW" "⚠ pylint not installed, skipping validation"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 2: Pre-flight — confirm Lab 3 is actually deployed
# -----------------------------------------------------------------------------
# We use the business-services-authorizer as the canary because it exists in
# every Lab 3 deployment (Case_A orchestration and Case_B deployment.sh).
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 2: Pre-flight — checking Lab 3 deployment..."
CANARY_FUNCTION="serverless-saas-lab3-business-services-authorizer"
if ! aws_cmd lambda get-function --function-name "$CANARY_FUNCTION" \
        --query 'Configuration.FunctionName' --output text > /dev/null 2>&1; then
    print_message "$RED" "ERROR: Lab 3 does not appear to be deployed in this account/region."
    print_message "$YELLOW" "  Could not find Lambda function: $CANARY_FUNCTION"
    print_message "$YELLOW" "  Run Lab 3 deployment first:"
    print_message "$YELLOW" "    • Workshop Studio event: the Orchestration_Template deploys Lab 3 automatically"
    print_message "$YELLOW" "    • Self-guided: cd $(dirname "$SCRIPT_DIR") && ./scripts/deployment.sh -s -c --email <your-email> --tenant-email <tenant-email> --profile <profile>"
    exit 1
fi
print_message "$GREEN" "✓ Lab 3 is deployed"
echo ""

# Temporary workspace
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# -----------------------------------------------------------------------------
# Step 3: Publish new Layer versions
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 3: Publishing new Layer versions..."

if [[ ! -d "$LAYERS_DIR" ]]; then
    print_message "$RED" "ERROR: Layers directory not found at $LAYERS_DIR"
    exit 1
fi

# Package the layer content with the required /python/ prefix that AWS
# Lambda expects for Python layers. Both source files AND pip dependencies
# go into the same /python/ directory so `import aws_lambda_powertools`
# resolves the same way the original `sam build` layer does.
LAYER_STAGE="$TEMP_DIR/layer_stage"
mkdir -p "$LAYER_STAGE/python"

# 1. Install the layer's pip dependencies (aws-lambda-powertools, simplejson,
#    jsonpickle, aws_requests_auth, python-jose). The original SAM build
#    uses `Metadata.BuildMethod: python3.12` which runs the equivalent
#    `pip install -r requirements.txt -t python/` — we do the same here.
if [[ -f "$LAYERS_DIR/requirements.txt" ]]; then
    print_message "$BLUE" "  Installing layer pip dependencies..."
    # --no-warn-conflicts silences false-positive warnings about the IDE's
    # globally-installed awscli (it pins older jmespath/dateutil than the
    # Powertools transitives). Those conflicts are against the IDE's
    # awscli, NOT against the Layer target directory, which gets its own
    # clean copies.
    if ! $PYTHON_CMD -m pip install \
            --quiet \
            --disable-pip-version-check \
            --no-color \
            --no-warn-conflicts \
            --target "$LAYER_STAGE/python" \
            -r "$LAYERS_DIR/requirements.txt" 2>&1 | tail -5; then
        print_message "$RED" "ERROR: pip install failed for $LAYERS_DIR/requirements.txt"
        print_message "$YELLOW" "  Check the Python interpreter '$PYTHON_CMD' has network + pip available."
        exit 1
    fi
fi

# 2. Copy the local utility modules (metrics_manager.py, logger.py,
#    auth_manager.py, etc.) on top of the pip payload.
cp -R "$LAYERS_DIR"/*.py "$LAYER_STAGE/python/" 2>/dev/null || true
for item in "$LAYERS_DIR"/*/; do
    [[ -d "$item" ]] || continue
    cp -R "$item" "$LAYER_STAGE/python/"
done

LAYER_ZIP="$TEMP_DIR/layer.zip"
(cd "$LAYER_STAGE" && zip -qr "$LAYER_ZIP" . -x "*.pyc" "__pycache__/*")

# Associative array: layer-name -> freshly-published ARN
declare -A LAYER_ARNS

for layer_name in "${LAYER_NAMES[@]}"; do
    print_message "$BLUE" "  Publishing $layer_name..."
    new_arn=$(aws_cmd lambda publish-layer-version \
        --layer-name "$layer_name" \
        --description "Lab 3 shared utilities — participant update" \
        --zip-file "fileb://$LAYER_ZIP" \
        --compatible-runtimes python3.14 python3.13 python3.12 \
        --query 'LayerVersionArn' --output text 2>/dev/null) || {
        print_message "$RED" "  ✗ Failed to publish $layer_name"
        print_message "$YELLOW" "    Check that the IDE role has lambda:PublishLayerVersion permission."
        exit 1
    }
    LAYER_ARNS["$layer_name"]="$new_arn"
    version_suffix=":${new_arn##*:}"
    print_message "$GREEN" "  ✓ $layer_name → $version_suffix"
done
echo ""

# -----------------------------------------------------------------------------
# Step 4: Rotate the Layer ARN on every Lab 3 function, preserving any
# other layers (notably LambdaInsightsExtension) that the template attached.
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 4: Updating Lambda function Layer ARNs..."

rotate_function_layer() {
    local func_name="$1"
    local layer_name="$2"
    local new_layer_arn="${LAYER_ARNS[$layer_name]}"

    if [[ -z "$new_layer_arn" ]]; then
        print_message "$RED" "  ✗ $func_name: no ARN captured for layer $layer_name"
        return 1
    fi

    # Read current layers; if the function does not exist, skip with warning.
    local current_layers_json
    current_layers_json=$(aws_cmd lambda get-function-configuration \
        --function-name "$func_name" \
        --query 'Layers[].Arn' --output json 2>/dev/null) || {
        print_message "$YELLOW" "  ⚠ $func_name: not found — skipping"
        return 0
    }

    # Build a new layer list:
    #   - drop any existing ARN whose layer-name matches $layer_name
    #     (regardless of version), so we don't accumulate duplicates
    #   - keep every other layer ARN unchanged (LambdaInsightsExtension etc.)
    #   - append the new ARN
    local new_layers_json
    new_layers_json=$(python3 -c "
import json, sys
current = json.loads('''$current_layers_json''')
drop_name = '$layer_name'
new_arn = '$new_layer_arn'

def layer_name_from_arn(arn: str) -> str:
    # ARN shape: arn:aws:lambda:REGION:ACCOUNT:layer:NAME:VERSION
    parts = arn.split(':')
    return parts[6] if len(parts) > 6 else ''

keep = [a for a in current if layer_name_from_arn(a) != drop_name]
keep.append(new_arn)
print(' '.join(keep))
")

    # shellcheck disable=SC2086
    if aws_cmd lambda update-function-configuration \
        --function-name "$func_name" \
        --layers $new_layers_json \
        --query 'FunctionName' --output text > /dev/null 2>&1; then
        print_message "$GREEN" "  ✓ $func_name → $layer_name (other layers preserved)"
    else
        print_message "$RED" "  ✗ $func_name: update-function-configuration failed"
        return 1
    fi
}

# First pass: code-edited functions
for entry in "${FUNCTIONS_TO_UPDATE[@]}"; do
    IFS='|' read -r func_name source_dir layer_name <<< "$entry"
    rotate_function_layer "$func_name" "$layer_name"
done

# Second pass: layer-only rotations
for entry in "${FUNCTIONS_LAYER_ONLY[@]}"; do
    IFS='|' read -r func_name layer_name <<< "$entry"
    rotate_function_layer "$func_name" "$layer_name"
done
echo ""

# -----------------------------------------------------------------------------
# Step 5: Wait for every affected function's configuration to settle.
# Lambda returns ResourceConflictException on update-function-code if
# LastUpdateStatus is still InProgress, so we poll explicitly instead of
# relying on CLI waiters that may not be available in older bundled CLIs.
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 5: Waiting for function configurations to settle..."

wait_for_function() {
    local func_name="$1"
    local attempt=0
    local status
    while (( attempt < 30 )); do
        status=$(aws_cmd lambda get-function-configuration \
            --function-name "$func_name" \
            --query 'LastUpdateStatus' --output text 2>/dev/null) || {
            # Function went missing mid-flight — don't hang, just move on
            return 0
        }
        case "$status" in
            Successful) return 0 ;;
            Failed)
                print_message "$RED" "  ✗ $func_name: LastUpdateStatus=Failed"
                return 1
                ;;
            InProgress|*)
                sleep 2
                ((attempt++))
                ;;
        esac
    done
    print_message "$YELLOW" "  ⚠ $func_name: still InProgress after 60s — continuing anyway"
    return 0
}

# Only the code-edited functions need the strict wait; a layer-only rotation
# is idempotent and doesn't conflict with anything we do later.
for entry in "${FUNCTIONS_TO_UPDATE[@]}"; do
    IFS='|' read -r func_name source_dir layer_name <<< "$entry"
    wait_for_function "$func_name"
done
print_message "$GREEN" "✓ Functions ready for code update"
echo ""

# -----------------------------------------------------------------------------
# Step 6: Package and update each function's code
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 6: Updating Lambda function code..."

update_function_code() {
    local func_name="$1"
    local source_dir="$2"
    local zip_file="$TEMP_DIR/${func_name}.zip"

    print_message "$BLUE" "  Packaging $func_name..."

    # Zip only the service directory. We intentionally do NOT bundle
    # Lab3/server/layers/ into /var/task/ any more — that would create two
    # competing copies of metrics_manager.py (one in /var/task, one in
    # /opt/python) and sys.path ordering would decide which one wins,
    # masking layer-update bugs.
    (cd "$SERVER_DIR/$source_dir" && zip -qr "$zip_file" . -x "*.pyc" "__pycache__/*" ".aws-sam/*")

    print_message "$BLUE" "  Deploying $func_name..."
    if aws_cmd lambda update-function-code \
        --function-name "$func_name" \
        --zip-file "fileb://$zip_file" \
        --query 'FunctionName' --output text > /dev/null 2>&1; then
        print_message "$GREEN" "  ✓ $func_name code updated"
    else
        print_message "$RED" "  ✗ Failed to update $func_name code"
        print_message "$YELLOW" "    Check that the IDE role has lambda:UpdateFunctionCode permission."
        return 1
    fi
}

FAILED=0
for entry in "${FUNCTIONS_TO_UPDATE[@]}"; do
    IFS='|' read -r func_name source_dir layer_name <<< "$entry"
    update_function_code "$func_name" "$source_dir" || ((FAILED++))
done

echo ""
if [[ $FAILED -gt 0 ]]; then
    print_message "$RED" "$FAILED function(s) failed to update code."
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 7: Prune old Layer versions
# -----------------------------------------------------------------------------
# Keep a 3-version rollback window so quick experimentation doesn't hit the
# 75-version-per-layer AWS soft cap after dozens of iterations.
# -----------------------------------------------------------------------------
print_message "$YELLOW" "Step 7: Pruning old Layer versions (keeping $LAYER_VERSIONS_TO_KEEP most recent)..."

prune_layer() {
    local layer_name="$1"
    local versions_json
    versions_json=$(aws_cmd lambda list-layer-versions \
        --layer-name "$layer_name" \
        --query 'LayerVersions[].Version' --output json 2>/dev/null) || {
        print_message "$YELLOW" "  ⚠ $layer_name: list-layer-versions failed — skipping prune"
        return 0
    }
    # Descending sort, drop the top N, delete the rest.
    local to_delete
    to_delete=$(python3 -c "
import json
vs = sorted(json.loads('''$versions_json'''), reverse=True)
for v in vs[$LAYER_VERSIONS_TO_KEEP:]:
    print(v)
")
    if [[ -z "$to_delete" ]]; then
        print_message "$GREEN" "  ✓ $layer_name: nothing to prune"
        return 0
    fi
    local count=0
    while IFS= read -r version; do
        [[ -z "$version" ]] && continue
        aws_cmd lambda delete-layer-version \
            --layer-name "$layer_name" \
            --version-number "$version" > /dev/null 2>&1 \
            && ((count++)) || true
    done <<< "$to_delete"
    print_message "$GREEN" "  ✓ $layer_name: pruned $count old version(s)"
}

for layer_name in "${LAYER_NAMES[@]}"; do
    prune_layer "$layer_name"
done
echo ""

print_message "$GREEN" "=========================================="
print_message "$GREEN" "✓ All Lambda functions and Layers updated successfully!"
print_message "$GREEN" "=========================================="
echo ""
print_message "$BLUE" "The code changes are now live. Test them by:"
print_message "$BLUE" "  1. Opening the Lab 3 Application URL"
print_message "$BLUE" "  2. Logging in as tenant1-admin"
print_message "$BLUE" "  3. Adding a product and verifying multi-tenant data partitioning"
echo ""
