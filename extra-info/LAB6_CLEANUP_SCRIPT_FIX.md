# Lab6 Cleanup Script Fix

## Issue Summary

The Lab6 cleanup script (`workshop/Lab6/scripts/cleanup.sh`) had a critical bug that caused it to fail when run via orchestration scripts or when CDKToolkit was missing.

## Problems Identified

### 1. PROFILE_ARG Variable Not Initialized Early

**Symptom**: Script would hang or fail with undefined variable errors when run via orchestration scripts.

**Root Cause**: The `PROFILE_ARG` variable was set at line 456 (inside Step 4), but it was used much earlier at line 115:

```bash
# Line 115 - PROFILE_ARG used but not yet defined
REGION=$(aws configure get region $PROFILE_ARG)
```

**Impact**: 
- When `$PROFILE_ARG` was undefined, AWS CLI commands would fail silently or hang
- The script would appear to work when run manually (because shell might have AWS_PROFILE set)
- But would fail when run via orchestration scripts that don't export AWS_PROFILE

### 2. Missing CDK Execution Role

**Symptom**: Error when trying to delete Lab6 pipeline stack:
```
Role arn:aws:iam::265098672980:role/cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 is invalid or cannot be assumed
```

**Root Cause**: 
- CDKToolkit stack was deleted (along with its IAM roles) during a previous cleanup
- Lab6 pipeline stack still existed and referenced the deleted CDK execution role
- CloudFormation couldn't delete the stack without the execution role

**Impact**:
- Lab6 pipeline stack became "orphaned" and couldn't be deleted
- Cleanup script would hang trying to delete the stack
- Manual deletion via AWS CLI also failed

## Fixes Applied

### Fix 1: Initialize PROFILE_ARG Early

**File**: `workshop/Lab6/scripts/cleanup.sh`

**Change**: Moved `PROFILE_ARG` initialization to right after parameter parsing (line 68):

```bash
# Parse command line parameters
parse_cleanup_parameters "$@"

# For Lab6, we use STACK_NAME_PREFIX for backward compatibility with existing logic
STACK_NAME_PREFIX="$STACK_NAME"

# Function to build AWS CLI profile argument
get_profile_arg() {
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# Set PROFILE_ARG early so it's available throughout the script
PROFILE_ARG=$(get_profile_arg)
```

**Removed**: Duplicate `PROFILE_ARG=$(get_profile_arg)` assignments at:
- Line 456 (Step 4)
- Line 491 (Step 5)

### Fix 2: Recreate CDKToolkit Before Deleting CDK-Based Stacks

**Solution**: When CDK execution role is missing, run `cdk bootstrap` to recreate it:

```bash
cdk bootstrap aws://265098672980/us-east-1 --profile serverless-saas-demo
```

This recreates:
- CDKToolkit CloudFormation stack
- CDK execution role: `cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1`
- CDK staging bucket: `cdk-hnb659fds-assets-265098672980-us-east-1`

After bootstrap, the orphaned pipeline stack can be deleted normally:

```bash
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab6 --profile serverless-saas-demo --region us-east-1
```

## Prevention Recommendations

### 1. CDKToolkit Dependency Management

The cleanup scripts should implement one of these strategies:

**Option A: Check for CDK-based stacks before deleting CDKToolkit**
```bash
# Before deleting CDKToolkit, check if any CDK-based stacks exist
lab5_pipeline=$(aws cloudformation describe-stacks --stack-name serverless-saas-pipeline-lab5 2>/dev/null || echo "")
lab6_pipeline=$(aws cloudformation describe-stacks --stack-name serverless-saas-pipeline-lab6 2>/dev/null || echo "")

if [[ -z "$lab5_pipeline" ]] && [[ -z "$lab6_pipeline" ]]; then
    # Safe to delete CDKToolkit
    aws cloudformation delete-stack --stack-name CDKToolkit
else
    echo "⚠ Skipping CDKToolkit deletion - Lab5 or Lab6 pipeline stacks still exist"
fi
```

**Option B: Recreate CDKToolkit if needed before deleting CDK-based stacks**
```bash
# Before deleting Lab5/Lab6 pipeline stacks, ensure CDKToolkit exists
if ! aws cloudformation describe-stacks --stack-name CDKToolkit &>/dev/null; then
    echo "ℹ️  CDKToolkit missing - recreating for stack deletion"
    cdk bootstrap aws://${ACCOUNT_ID}/${AWS_REGION} --profile ${AWS_PROFILE}
fi
```

### 2. Variable Initialization Pattern

All cleanup scripts should follow this pattern:

```bash
#!/bin/bash
set -e

# 1. Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Source modules
source "$SCRIPT_DIR/../../scripts/lib/parameter-parsing-template.sh"
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"

# 3. Parse parameters
parse_cleanup_parameters "$@"

# 4. Initialize derived variables IMMEDIATELY after parsing
PROFILE_ARG=$(get_profile_arg)
REGION=${AWS_REGION:-us-east-1}

# 5. Now safe to use variables throughout script
```

## Testing

### Test 1: Script Starts Properly
```bash
cd workshop/Lab6/scripts
echo "no" | ./cleanup.sh --profile serverless-saas-demo
```

**Expected**: Script should start, show configuration, and exit cleanly when user cancels.

### Test 2: Profile Argument Works
```bash
cd workshop/Lab6/scripts
echo "yes" | ./cleanup.sh --profile serverless-saas-demo
```

**Expected**: Script should use the specified profile for all AWS CLI commands.

### Test 3: CDK Stack Deletion Works
```bash
# If CDKToolkit is missing, recreate it
cdk bootstrap aws://265098672980/us-east-1 --profile serverless-saas-demo

# Then delete pipeline stack
aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab6 --profile serverless-saas-demo --region us-east-1
```

**Expected**: Stack deletion should succeed without role errors.

## Related Files

- `workshop/Lab6/scripts/cleanup.sh` - Fixed script
- `workshop/scripts/lib/parameter-parsing-template.sh` - Parameter parsing module
- `workshop/scripts/lib/cleanup-verification.sh` - Cleanup verification module
- `workshop/scripts/cleanup-all-labs.sh` - Orchestration script

## Status

✅ **FIXED** - Lab6 cleanup script now initializes PROFILE_ARG early and works correctly when run via orchestration scripts or manually.

✅ **RESOLVED** - CDKToolkit recreation procedure documented for handling orphaned CDK-based stacks.

## Date

January 30, 2026
