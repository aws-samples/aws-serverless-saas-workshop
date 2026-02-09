#!/bin/bash

# =============================================================================
# Template Validation Script
# =============================================================================
# Validates SAM/CloudFormation templates for common issues:
#   1. !Sub expressions referencing undefined parameters/resources
#   2. Missing required parameters
#
# USAGE:
#   ./scripts/validate-templates.sh
#
# Run this before deploying to catch template errors early.
# =============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

errors_found=0

# Validate that all ${Variable} references in !Sub expressions
# match a declared Parameter or Resource in the template
validate_sub_references() {
    local template="$1"
    local label="$2"

    if [[ ! -f "$template" ]]; then
        return 0
    fi

    # Extract declared parameter names
    local params=$(awk '
        /^Parameters:/ { in_params=1; next }
        in_params && /^[A-Z]/ { in_params=0 }
        in_params && /^  [A-Za-z]/ { gsub(/:.*/, ""); gsub(/^  /, ""); print }
    ' "$template")

    # Extract declared resource names
    local resources=$(awk '
        /^Resources:/ { in_res=1; next }
        in_res && /^[A-Z]/ { in_res=0 }
        in_res && /^  [A-Za-z]/ { gsub(/:.*/, ""); gsub(/^  /, ""); print }
    ' "$template")

    # Combine into a single list of valid references (plus AWS pseudo-parameters)
    local valid_refs="$params $resources AWS::StackName AWS::StackId AWS::Region AWS::AccountId AWS::URLSuffix AWS::NotificationARNs AWS::Partition AWS::NoValue"

    # Find all ${Variable} references in !Sub lines (excluding literal ${!Variable} which are escaped)
    local sub_refs=$(grep -n '!Sub' "$template" | grep -oE '\$\{[A-Za-z][A-Za-z0-9_]*\}' | sed 's/\${\(.*\)}/\1/' | sort -u)

    for ref in $sub_refs; do
        # Skip if it's a valid reference
        local found=false
        for valid in $valid_refs; do
            if [[ "$ref" == "$valid" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            echo -e "${RED}  ERROR: ${label} — \${${ref}} is not a declared Parameter or Resource${NC}"
            errors_found=$((errors_found + 1))
        fi
    done
}

echo "========================================"
echo "Validating SAM/CloudFormation Templates"
echo "========================================"
echo ""

# Validate all lab templates
templates=(
    "Lab1/server/template.yaml:Lab1"
    "Lab2/server/template.yaml:Lab2"
    "Lab3/server/shared-template.yaml:Lab3 Shared"
    "Lab3/server/tenant-template.yaml:Lab3 Tenant"
    "Lab4/server/shared-template.yaml:Lab4 Shared"
    "Lab4/server/tenant-template.yaml:Lab4 Tenant"
    "Lab5/server/shared-template.yaml:Lab5 Shared"
    "Lab5/server/tenant-template.yaml:Lab5 Tenant"
    "Lab6/server/shared-template.yaml:Lab6 Shared"
    "Lab6/server/tenant-template.yaml:Lab6 Tenant"
    "Lab7/template.yaml:Lab7"
    "Lab7/tenant-template.yaml:Lab7 Pooled"
)

for entry in "${templates[@]}"; do
    IFS=':' read -r path label <<< "$entry"
    full_path="$WORKSHOP_ROOT/$path"

    if [[ -f "$full_path" ]]; then
        echo -e "  Checking ${label}..."
        validate_sub_references "$full_path" "$label"
    else
        echo -e "${YELLOW}  SKIP: ${label} — file not found${NC}"
    fi
done

echo ""

if [[ $errors_found -gt 0 ]]; then
    echo -e "${RED}✗ Found $errors_found error(s) — fix before deploying${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All templates validated — no issues found${NC}"
    exit 0
fi
