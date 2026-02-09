#!/bin/bash
# Renames TenantId -> TenantIdParameter in Lab3, Lab4 tenant templates
# and updates callers (main-template.yaml, Lab4 deployment script).
#
# Only renames:
#   - Parameter declaration:  "  TenantId:" -> "  TenantIdParameter:"
#   - !Ref references:        "!Ref TenantId" -> "!Ref TenantIdParameter"
#   - !Sub references:        "${TenantId}" -> "${TenantIdParameter}"
#   - Parameter overrides:    "TenantId=" -> "TenantIdParameter="
#   - YAML key pass-through:  "TenantId: pooled" -> "TenantIdParameter: pooled"
#   - YAML key ref:           "TenantId: !Ref" -> "TenantIdParameter: !Ref"
#
# Does NOT rename:
#   - Tag keys:  "- Key: TenantId" (these are literal AWS tag names)
#
# Usage:
#   ./scripts/rename-tenantid-parameter.sh --dry-run   # Preview
#   ./scripts/rename-tenantid-parameter.sh              # Apply

set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

rename_in_file() {
    local file="$1"
    local label="$2"

    if [[ ! -f "$file" ]]; then
        echo "SKIP: $label (not found)"
        return
    fi

    # Build a temp file with replacements
    local tmp="${file}.tmp"
    sed \
        -e 's/\${TenantId}/\${TenantIdParameter}/g' \
        -e 's/!Ref TenantId$/!Ref TenantIdParameter/' \
        -e 's/!Ref TenantId /!Ref TenantIdParameter /g' \
        -e '/^  TenantId:$/s/TenantId/TenantIdParameter/' \
        -e '/TenantId:.*!Ref/s/TenantId:/TenantIdParameter:/' \
        -e '/TenantId:.*pooled/s/TenantId:/TenantIdParameter:/' \
        -e 's/TenantId=\$/TenantIdParameter=\$/g' \
        -e 's/--parameter-overrides TenantId=/--parameter-overrides TenantIdParameter=/g' \
        "$file" > "$tmp"

    local changes=$(diff "$file" "$tmp" | grep "^[<>]" | wc -l | tr -d '[:space:]')

    if [[ "$changes" == "0" ]]; then
        echo "SKIP: $label — no changes needed"
        rm -f "$tmp"
        return
    fi

    echo ""
    echo "=== $label ($((changes / 2)) line(s) changed) ==="

    if [[ "$DRY_RUN" == true ]]; then
        diff "$file" "$tmp" || true
        rm -f "$tmp"
    else
        mv "$tmp" "$file"
        echo "  ✓ Applied"
    fi
}

echo "Renaming TenantId -> TenantIdParameter"
echo "========================================"

rename_in_file "$WORKSHOP_ROOT/Lab3/server/tenant-template.yaml" "Lab3 tenant-template"
rename_in_file "$WORKSHOP_ROOT/Lab4/server/tenant-template.yaml" "Lab4 tenant-template"
rename_in_file "$WORKSHOP_ROOT/orchestration/main-template.yaml" "main-template"
rename_in_file "$WORKSHOP_ROOT/Lab4/scripts/deployment.sh" "Lab4 deployment.sh"

echo ""
if [[ "$DRY_RUN" == true ]]; then
    echo "DRY RUN complete. Run without --dry-run to apply."
else
    echo "Done. Verifying no bare TenantId refs remain (tag keys excluded)..."
    echo ""
    for f in Lab3/server/tenant-template.yaml Lab4/server/tenant-template.yaml orchestration/main-template.yaml Lab4/scripts/deployment.sh; do
        leftover=$(grep "TenantId" "$WORKSHOP_ROOT/$f" 2>/dev/null | grep -v "TenantIdParameter" | grep -v "Key: TenantId" || true)
        if [[ -n "$leftover" ]]; then
            echo "WARNING: $(basename "$f") still has bare TenantId:"
            echo "$leftover"
        fi
    done
    echo "✓ Verification complete"
fi
