#!/usr/bin/env bash
# =============================================================================
# package-resume-upload.sh
# Resume the Workshop Studio packaging pipeline from the S3 upload step.
#
# Use when package-for-workshop-studio.sh completed the SAM + Angular builds
# but failed during upload (typically ExpiredToken when Workshop Studio
# temporary credentials expired mid-run).
#
# Reads staged artefacts from /tmp/package-for-workshop-studio-<build-id>/
# and does only: aws s3 sync + workshop-docs/static/templates/ copy + manifest.
# =============================================================================

set -euo pipefail

# ----- Config ----------------------------------------------------------------
# Match the build_id from the original package-for-workshop-studio.sh run.
BUILD_ID="${1:-2026-05-05T01-50-01Z-b7f43da}"
ASSETS_BUCKET="${ASSETS_BUCKET:-ws-assets-us-east-1}"
ASSETS_PREFIX="${ASSETS_PREFIX:-b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/}"
AWS_REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_CODE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(cd "${WORKSHOP_CODE_ROOT}/.." && pwd)"
WORKSHOP_DOCS_ROOT="${WORKSPACE_ROOT}/workshop-docs"

STAGE_DIR="/tmp/package-for-workshop-studio-${BUILD_ID}"
PACKAGED_TEMPLATES_DIR="${STAGE_DIR}/packaged-templates"
ANGULAR_DISTS_DIR="${STAGE_DIR}/angular-dists"
DOCS_TEMPLATES_DIR="${WORKSHOP_DOCS_ROOT}/static/templates"
MANIFEST_PATH="${WORKSHOP_CODE_ROOT}/scripts/packaging-manifest.json"

FULL_UPLOAD_PREFIX="${ASSETS_PREFIX}serverless-saas-workshop/${BUILD_ID}/"
TEMPLATES_S3_PREFIX="${FULL_UPLOAD_PREFIX}templates/"
UI_S3_PREFIX="${FULL_UPLOAD_PREFIX}ui/"

# ANSI colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

msg() { echo -e "${1}${2}${NC}"; }

# ----- Preflight -------------------------------------------------------------
msg "${CYAN}" "==================================================
Resume upload for build ${BUILD_ID}
=================================================="

if [[ ! -d "${PACKAGED_TEMPLATES_DIR}" ]]; then
    msg "${RED}" "✗ Packaged templates dir not found: ${PACKAGED_TEMPLATES_DIR}"
    exit 1
fi
if [[ ! -d "${ANGULAR_DISTS_DIR}" ]]; then
    msg "${RED}" "✗ Angular dists dir not found: ${ANGULAR_DISTS_DIR}"
    exit 1
fi

# Validate creds
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]] || [[ -z "${AWS_SESSION_TOKEN:-}" ]]; then
    msg "${RED}" "✗ Missing AWS credentials (env vars)"
    msg "${YELLOW}" "  Re-export from Workshop Studio 'Repository credentials' console:"
    msg "${YELLOW}" "    export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=..."
    exit 1
fi

if ! aws sts get-caller-identity --region "${AWS_REGION}" >/dev/null 2>&1; then
    msg "${RED}" "✗ AWS credentials invalid or expired"
    msg "${YELLOW}" "  Re-fetch credentials from Workshop Studio and re-export."
    exit 1
fi
caller="$(aws sts get-caller-identity --region "${AWS_REGION}" --query Arn --output text)"
msg "${GREEN}" "✓ AWS credentials valid (${caller})"

template_count=$(find "${PACKAGED_TEMPLATES_DIR}" -name '*.yaml' -type f | wc -l | tr -d ' ')
dist_count=$(find "${ANGULAR_DISTS_DIR}" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
msg "${CYAN}" "Staged: ${template_count} templates, ${dist_count} angular dists"

# ----- 1. Upload packaged templates to S3 ------------------------------------
msg "${CYAN}" "
[1/4] Uploading packaged CloudFormation templates..."
if ! aws s3 sync \
        "${PACKAGED_TEMPLATES_DIR}" \
        "s3://${ASSETS_BUCKET}/${TEMPLATES_S3_PREFIX}" \
        --region "${AWS_REGION}" \
        --only-show-errors; then
    msg "${RED}" "✗ aws s3 sync failed for templates"
    exit 1
fi
msg "${GREEN}" "  ✓ Templates uploaded to s3://${ASSETS_BUCKET}/${TEMPLATES_S3_PREFIX}"

# ----- 2. Copy templates into workshop-docs/static/templates/ ---------------
msg "${CYAN}" "
[2/4] Copying packaged templates into workshop-docs/static/templates/..."
mkdir -p "${DOCS_TEMPLATES_DIR}"
for packaged in "${PACKAGED_TEMPLATES_DIR}"/*.yaml; do
    base=$(basename "${packaged}" .yaml)
    dest="${DOCS_TEMPLATES_DIR}/serverless-saas-workshop-${base}.yaml"
    cp "${packaged}" "${dest}"
done
msg "${GREEN}" "  ✓ ${template_count} templates copied to ${DOCS_TEMPLATES_DIR}"

# ----- 3. Upload Angular dists to S3 -----------------------------------------
msg "${CYAN}" "
[3/4] Uploading Angular dists (with Placeholder_Tokens baked in)..."
if ! aws s3 sync \
        "${ANGULAR_DISTS_DIR}" \
        "s3://${ASSETS_BUCKET}/${UI_S3_PREFIX}" \
        --region "${AWS_REGION}" \
        --only-show-errors; then
    msg "${RED}" "✗ aws s3 sync failed for UI dists"
    exit 1
fi
msg "${GREEN}" "  ✓ ${dist_count} dists uploaded to s3://${ASSETS_BUCKET}/${UI_S3_PREFIX}"

# ----- 4. Emit Packaging_Manifest --------------------------------------------
msg "${CYAN}" "
[4/4] Emitting Packaging_Manifest..."
export BUILD_ID
export SOURCE_COMMIT="$(git -C "${WORKSHOP_CODE_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')"
export ASSETS_BUCKET
export FULL_UPLOAD_PREFIX
export PACKAGED_TEMPLATES_DIR_OUT="${PACKAGED_TEMPLATES_DIR}"
export ANGULAR_DISTS_DIR_OUT="${ANGULAR_DISTS_DIR}"
export DOCS_TEMPLATES_DIR_OUT="${DOCS_TEMPLATES_DIR}"
export WORKSHOP_DOCS_ROOT
export MANIFEST_PATH

python3.14 <<'PYEOF'
import hashlib, json, os, sys
from datetime import datetime, timezone
from pathlib import Path

def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def emit() -> None:
    build_id = os.environ["BUILD_ID"]
    source_commit = os.environ["SOURCE_COMMIT"]
    assets_bucket = os.environ["ASSETS_BUCKET"]
    full_upload_prefix = os.environ["FULL_UPLOAD_PREFIX"]
    packaged_templates_dir = Path(os.environ["PACKAGED_TEMPLATES_DIR_OUT"])
    angular_dists_dir = Path(os.environ["ANGULAR_DISTS_DIR_OUT"])
    docs_templates_dir = Path(os.environ["DOCS_TEMPLATES_DIR_OUT"])
    workshop_docs_root = Path(os.environ["WORKSHOP_DOCS_ROOT"])
    manifest_path = Path(os.environ["MANIFEST_PATH"])

    artefacts: list[dict] = []

    # CFN templates
    for yaml_file in sorted(packaged_templates_dir.glob("*.yaml")):
        lab = yaml_file.stem
        s3_key = f"{full_upload_prefix}templates/{yaml_file.name}"
        local_copy = docs_templates_dir / f"serverless-saas-workshop-{lab}.yaml"
        try:
            local_copy_rel = str(local_copy.relative_to(workshop_docs_root.parent))
        except ValueError:
            local_copy_rel = str(local_copy)
        artefacts.append({
            "kind": "cfn-template",
            "lab": lab,
            "s3_key": s3_key,
            "local_copy": local_copy_rel,
            "sha256": sha256_of(yaml_file),
            "size_bytes": yaml_file.stat().st_size,
            "referenced_by": [
                f"serverless-saas-workshop-main.yaml::Lab{lab.replace('-', '_').capitalize()}Stack"
            ],
        })

    # Lambda zips (referenced by CodeUri in packaged templates)
    for yaml_file in sorted(packaged_templates_dir.glob("*.yaml")):
        lab = yaml_file.stem
        content = yaml_file.read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if not stripped.startswith("CodeUri:"):
                continue
            uri = stripped.split("CodeUri:", 1)[1].strip().strip("'\"")
            if not uri.startswith(f"s3://{assets_bucket}/"):
                continue
            s3_key = uri[len(f"s3://{assets_bucket}/"):]
            artefacts.append({
                "kind": "lambda-zip",
                "lab": lab,
                "function_logical_id": None,
                "s3_key": s3_key,
                "sha256": None,
                "size_bytes": None,
                "referenced_by": [f"templates/{yaml_file.name}::CodeUri"],
            })

    # Angular dists
    known_placeholders = (
        "__API_GATEWAY_URL__", "__ADMIN_API_GATEWAY_URL__", "__TENANT_API_GATEWAY_URL__",
        "__USER_POOL_ID__", "__USER_POOL_CLIENT_ID__", "__AWS_REGION__",
        "__CLOUDFRONT_DISTRIBUTION_DOMAIN__",
    )
    for app_dir in sorted(angular_dists_dir.iterdir()):
        if not app_dir.is_dir():
            continue
        app_id = app_dir.name
        s3_key_prefix = f"{full_upload_prefix}ui/{app_id}/"
        object_count = 0
        total_size = 0
        found_tokens: set[str] = set()
        for f in app_dir.rglob("*"):
            if not f.is_file():
                continue
            object_count += 1
            total_size += f.stat().st_size
            if f.suffix in (".js", ".html", ".css", ".json", ".ts"):
                try:
                    text = f.read_text(errors="ignore")
                    for tok in known_placeholders:
                        if tok in text:
                            found_tokens.add(tok)
                except (OSError, UnicodeDecodeError):
                    pass
        artefacts.append({
            "kind": "angular-dist",
            "app": app_id,
            "s3_key_prefix": s3_key_prefix,
            "object_count": object_count,
            "total_size_bytes": total_size,
            "placeholder_tokens": sorted(found_tokens),
            "referenced_by": [f"AngularConfigLambda::Apps[{app_id}]"],
        })

    manifest = {
        "schema_version": "1.0",
        "build_id": build_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_commit": source_commit,
        "assets_bucket": assets_bucket,
        "assets_prefix": full_upload_prefix,
        "artefacts": artefacts,
    }

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")

    counts: dict[str, int] = {}
    for a in artefacts:
        counts[a["kind"]] = counts.get(a["kind"], 0) + 1
    print(f"manifest written to {manifest_path}")
    print(f"  total artefacts: {len(artefacts)}")
    for kind, n in sorted(counts.items()):
        print(f"    {kind}: {n}")


if __name__ == "__main__":
    try:
        emit()
    except Exception as exc:
        print(f"ERROR: manifest emit failed: {exc}", file=sys.stderr)
        sys.exit(1)
PYEOF

if [[ -f "${MANIFEST_PATH}" ]]; then
    msg "${GREEN}" "  ✓ Manifest written to ${MANIFEST_PATH}"
else
    msg "${RED}" "  ✗ Manifest was not written"
    exit 1
fi

msg "${GREEN}" "
==================================================
✓ Resume upload complete for build ${BUILD_ID}
==================================================
  Templates:  s3://${ASSETS_BUCKET}/${TEMPLATES_S3_PREFIX}
  UI:         s3://${ASSETS_BUCKET}/${UI_S3_PREFIX}
  Docs copy:  ${DOCS_TEMPLATES_DIR}
  Manifest:   ${MANIFEST_PATH}
=================================================="
