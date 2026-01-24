# PROFILE_ARG Bug Fix Summary

## Critical Bug Discovered

**Date**: January 21, 2026  
**Severity**: HIGH - Deployments were going to wrong AWS account

## Problem Description

All lab deployment scripts had a critical bug where the `--profile` parameter was accepted but not actually used:

1. Scripts accepted `--profile` parameter and stored it in `AWS_PROFILE` variable ✅
2. Scripts displayed the profile in console output ✅
3. Scripts used `$PROFILE_ARG` in all AWS CLI and SAM CLI commands ✅
4. **BUG**: `PROFILE_ARG` was never set based on `AWS_PROFILE` ❌

This caused deployments to use the wrong AWS account even when `--profile` was specified.

## Example of Bug Impact

When running:
```bash
./deployment.sh -s --profile serverless-saas-demo
```

Expected account: `265098672980` (serverless-saas-demo profile)  
Actual account: `775183867997` (default profile)

## Root Cause

Missing code to set `PROFILE_ARG` based on `AWS_PROFILE`:

```bash
# This code was missing:
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi
```

## Fix Applied

Added the missing `PROFILE_ARG` initialization code to all deployment scripts after parameter validation.

### Fixed Scripts

| Lab | Script | Status | Location |
|-----|--------|--------|----------|
| Lab 1 | deployment.sh | ✅ FIXED | Line ~103 |
| Lab 2 | deployment.sh | ✅ FIXED | Line ~111 |
| Lab 3 | deployment.sh | ✅ FIXED | Line ~126 |
| Lab 4 | deployment.sh | ✅ FIXED | Line ~144 |
| Lab 5 | deployment.sh | ✅ FIXED | Line ~128 |
| Lab 6 | deployment.sh | ✅ ALREADY FIXED | Line ~60 |
| Lab 7 | deployment.sh | ✅ ALREADY FIXED | Line ~83 |

## Verification

Lab 1 deployment tested with `--profile serverless-saas-demo`:
- ✅ Deployment now targets correct account: `265098672980`
- ✅ Stack ARN shows correct account in error message
- ✅ Profile parameter is properly passed to SAM CLI

## Impact on Testing

This bug invalidates all previous deployment tests (tasks 17-26) because:
1. The `--profile` parameter wasn't actually working
2. Deployments were using wrong AWS account
3. Tests appeared to pass but were testing wrong functionality

## Required Actions

1. ✅ Fix all deployment scripts (COMPLETED)
2. ⏳ Re-run all deployment tests (tasks 27.1-27.7)
3. ⏳ Verify each lab deploys to correct account
4. ⏳ Update task statuses to reflect re-testing

## Lessons Learned

1. Always verify parameter passing works end-to-end
2. Check AWS account ID in deployment outputs
3. Test with explicit profile parameter, not just default
4. Validate CloudFormation stack ARNs contain expected account ID

## Related Tasks

- Tasks 17-26: Profile parameter implementation (needs re-verification)
- Tasks 27.1-27.7: Deployment testing (in progress)
