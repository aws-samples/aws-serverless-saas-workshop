# API Gateway CloudWatch Role Cleanup Fix

## Issue Summary

**Date**: January 29, 2026  
**Status**: ✅ Fixed  
**Priority**: High  
**Affected Script**: `workshop/scripts/cleanup-all-labs.sh`

## Problem Description

The `apigateway-cloudwatch-publish-role` IAM role was not being deleted by the cleanup-all-labs script, even though the script claimed to clean up account-level IAM roles. After running the cleanup script, the role still existed in IAM and the API Gateway account settings still referenced the deleted role ARN.

### Symptoms

1. After running `cleanup-all-labs.sh`, the IAM role `apigateway-cloudwatch-publish-role` still existed
2. The API Gateway account settings still showed the role ARN: `arn:aws:iam::265098672980:role/apigateway-cloudwatch-publish-role`
3. The cleanup script reported "no action needed" for the role

## Root Cause Analysis

The cleanup script had a **hardcoded role name mismatch**:

**Expected Role Name** (in cleanup script):
```bash
ACCOUNT_LEVEL_ROLES=(
    "APIGatewayCloudWatchLogsRole"  # ❌ WRONG - This role doesn't exist
)
```

**Actual Role Name** (created by deployment scripts):
```bash
ROLE_NAME="apigateway-cloudwatch-publish-role"  # ✅ CORRECT
```

### Why This Happened

The deployment scripts (Lab1-Lab6) all create a role named `apigateway-cloudwatch-publish-role`:

```bash
# From workshop/Lab1/scripts/deployment.sh (line 205)
ROLE_NAME="apigateway-cloudwatch-publish-role"
```

However, the cleanup script was looking for a role named `APIGatewayCloudWatchLogsRole`, which never existed. This caused the cleanup script to skip the role deletion entirely.

## Solution

### Fix Applied

**File**: `workshop/scripts/cleanup-all-labs.sh`  
**Line**: ~1180 (Step 4: Cleaning Up Account-Level IAM Roles)

**Before**:
```bash
ACCOUNT_LEVEL_ROLES=(
    "APIGatewayCloudWatchLogsRole"
)
```

**After**:
```bash
ACCOUNT_LEVEL_ROLES=(
    "apigateway-cloudwatch-publish-role"
)
```

### How It Works

The cleanup script now follows this workflow:

1. **Step 4: Clean Up Account-Level IAM Roles**
   - Checks if `apigateway-cloudwatch-publish-role` exists
   - Detaches all managed policies
   - Deletes all inline policies
   - Deletes the IAM role

2. **Step 4.5: Reset API Gateway Account Settings**
   - Checks if API Gateway account settings have a CloudWatch role ARN configured
   - If the role no longer exists in IAM, resets the API Gateway account settings
   - Sets `cloudwatchRoleArn` to empty string to remove the orphaned reference

## Verification

### Test 1: Role Deletion

```bash
$ aws iam get-role --role-name apigateway-cloudwatch-publish-role --profile serverless-saas-demo

An error occurred (NoSuchEntity) when calling the GetRole operation: The role with name apigateway-cloudwatch-publish-role cannot be found.
```

✅ **Result**: Role successfully deleted

### Test 2: API Gateway Account Settings Reset

```bash
$ aws apigateway get-account --region us-east-1 --profile serverless-saas-demo --query 'cloudwatchRoleArn' --output text

None
```

✅ **Result**: API Gateway account settings properly reset (no role ARN configured)

### Test 3: Complete Cleanup Verification

```bash
$ cd workshop/scripts && echo "yes" | ./cleanup-all-labs.sh --profile serverless-saas-demo

========================================
Step 4: Cleaning Up Account-Level IAM Roles
========================================

Checking for workshop-created account-level IAM roles...
  Found account-level role: apigateway-cloudwatch-publish-role
    Detaching managed policies...
    Deleting inline policies...
    Deleting role: apigateway-cloudwatch-publish-role
      ✓ Role deleted: apigateway-cloudwatch-publish-role

Account-level IAM roles cleanup complete


========================================
Step 4.5: Resetting API Gateway Account Settings
========================================

Checking API Gateway account settings...
  Found API Gateway CloudWatch Logs role ARN: arn:aws:iam::265098672980:role/apigateway-cloudwatch-publish-role
  Role no longer exists in IAM - resetting API Gateway account settings
    ✓ API Gateway account settings reset successfully
    ✓ Role ARN reference removed from API Gateway

API Gateway account settings check complete
```

✅ **Result**: Complete cleanup successful

## Impact

### Before Fix
- ❌ IAM role `apigateway-cloudwatch-publish-role` remained after cleanup
- ❌ API Gateway account settings contained orphaned role ARN reference
- ❌ Incomplete cleanup left account-level resources

### After Fix
- ✅ IAM role `apigateway-cloudwatch-publish-role` is deleted
- ✅ API Gateway account settings are properly reset
- ✅ Complete cleanup of all workshop resources

## Related Files

- `workshop/scripts/cleanup-all-labs.sh` - Fixed cleanup script
- `workshop/Lab1/scripts/deployment.sh` - Creates the role (line 205)
- `workshop/Lab2/scripts/deployment.sh` - Creates the role (line 304)
- `workshop/Lab3/scripts/deployment.sh` - Creates the role (line 321)
- `workshop/Lab4/scripts/deployment.sh` - Creates the role (line 314)
- `workshop/Lab5/scripts/deployment.sh` - Creates the role (line 440)
- `workshop/Lab6/scripts/deployment.sh` - Creates the role (line 176)

## Testing Recommendations

1. **Deploy any lab** (Lab1-Lab6) to create the role
2. **Run cleanup-all-labs script** to verify role deletion
3. **Verify role is deleted** using AWS CLI
4. **Verify API Gateway settings are reset** using AWS CLI

## Lessons Learned

1. **Always verify resource names** match between deployment and cleanup scripts
2. **Test cleanup scripts** after deployment to ensure complete cleanup
3. **Use consistent naming conventions** across all scripts
4. **Document account-level resources** that are shared across labs

## References

- [API Gateway CloudWatch Logs Role Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)
- [IAM Role Deletion Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_manage_delete.html)
- Workshop Cleanup Documentation: `workshop/extra-info/DEPLOYMENT_CLEANUP_MANUAL.md`
