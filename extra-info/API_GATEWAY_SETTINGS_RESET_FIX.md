# API Gateway Account Settings Reset Fix

**Date**: January 28, 2026  
**Status**: ✅ Implemented  
**Related Task**: Task 14 - Analyze CDKToolkit Dependency and API Gateway Logging Role Cleanup

## Problem Statement

After running the global cleanup script (`workshop/scripts/cleanup-all-labs.sh`), the `APIGatewayCloudWatchLogsRole` IAM role was successfully deleted, but the role ARN still appeared in the AWS console under API Gateway settings.

### Root Cause

The cleanup script deleted the IAM role but didn't reset the API Gateway account settings to remove the role ARN reference. API Gateway caches the role ARN in its account settings, and even after the IAM role is deleted, the ARN reference remains configured.

**Why This Happens**:
1. API Gateway stores the CloudWatch Logs role ARN in account-level settings
2. The cleanup script deletes the IAM role from IAM service
3. The ARN reference remains in API Gateway account settings
4. AWS console displays the ARN from API Gateway settings (not from IAM)
5. Result: Deleted role ARN still appears in console

## Solution Implemented

Added **Step 4.5: Reset API Gateway Account Settings** to the global cleanup script.

### Implementation Details

**Location**: `workshop/scripts/cleanup-all-labs.sh` (after Step 4, before Step 5)

**What It Does**:
1. Checks if API Gateway account settings have a CloudWatch Logs role configured
2. Extracts the role name from the ARN
3. Verifies if the role still exists in IAM
4. If role is deleted but ARN is still in API Gateway settings, resets the settings using:
   ```bash
   aws apigateway update-account --patch-operations op=replace,path=/cloudwatchRoleArn,value=''
   ```

**Code Added** (lines ~1296-1355):
```bash
# Step 4.5: Reset API Gateway Account Settings
# After deleting the APIGatewayCloudWatchLogsRole, we need to reset the API Gateway
# account settings to remove the role ARN reference. Otherwise, the deleted role ARN
# will still appear in the AWS console even though the IAM role no longer exists.
echo ""
print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 4.5: Resetting API Gateway Account Settings"
print_message "$BLUE" "========================================"
echo ""

# Check if API Gateway account settings have a CloudWatch Logs role configured
print_message "$YELLOW" "Checking API Gateway account settings..."
APIGW_ROLE_ARN=$(aws apigateway get-account \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --query 'cloudwatchRoleArn' \
    --output text 2>/dev/null || echo "")

if [[ -n "$APIGW_ROLE_ARN" && "$APIGW_ROLE_ARN" != "None" ]]; then
    print_message "$YELLOW" "  Found API Gateway CloudWatch Logs role ARN: $APIGW_ROLE_ARN"
    
    # Extract role name from ARN
    ROLE_NAME=$(echo "$APIGW_ROLE_ARN" | awk -F'/' '{print $NF}')
    
    # Check if the role still exists in IAM
    if ! aws iam get-role \
        ${PROFILE:+--profile "$PROFILE"} \
        --role-name "$ROLE_NAME" &>/dev/null; then
        
        print_message "$YELLOW" "  Role no longer exists in IAM - resetting API Gateway account settings"
        
        # Reset API Gateway account settings to remove the role ARN reference
        if aws apigateway update-account \
            ${PROFILE:+--profile "$PROFILE"} \
            --region us-east-1 \
            --patch-operations op=replace,path=/cloudwatchRoleArn,value='' 2>/dev/null; then
            print_message "$GREEN" "    ✓ API Gateway account settings reset successfully"
            print_message "$GREEN" "    ✓ Role ARN reference removed from API Gateway"
        else
            print_message "$RED" "    ✗ Failed to reset API Gateway account settings"
            print_message "$YELLOW" "    Note: This is cosmetic - the role is already deleted from IAM"
        fi
    else
        print_message "$GREEN" "  ✓ Role still exists in IAM - no action needed"
        print_message "$YELLOW" "    (Role ARN will be removed when the role is deleted)"
    fi
else
    print_message "$GREEN" "  ✓ No API Gateway CloudWatch Logs role configured"
fi

echo ""
print_message "$GREEN" "API Gateway account settings check complete"
echo ""
```

### Verification Added

Added verification in the `verify_complete_cleanup()` function to check if API Gateway account settings are properly reset:

**Code Added** (lines ~240-265):
```bash
# Check API Gateway account settings for orphaned role ARN references
print_message "$YELLOW" "Checking API Gateway account settings..."
local apigw_role_arn=$(aws apigateway get-account \
    ${PROFILE:+--profile "$PROFILE"} \
    --region us-east-1 \
    --query 'cloudwatchRoleArn' \
    --output text 2>/dev/null || echo "")

if [[ -n "$apigw_role_arn" && "$apigw_role_arn" != "None" ]]; then
    # Extract role name from ARN
    local role_name=$(echo "$apigw_role_arn" | awk -F'/' '{print $NF}')
    
    # Check if the role still exists in IAM
    if ! aws iam get-role \
        ${PROFILE:+--profile "$PROFILE"} \
        --role-name "$role_name" &>/dev/null; then
        print_message "$RED" "  ⚠️  API Gateway references deleted role: $apigw_role_arn"
        print_message "$YELLOW" "     This is an orphaned reference - the role no longer exists in IAM"
        print_message "$YELLOW" "     Run Step 4.5 again to reset API Gateway account settings"
        remaining_resources=$((remaining_resources + 1))
    else
        print_message "$YELLOW" "  ⚠️  API Gateway references role: $apigw_role_arn"
        print_message "$YELLOW" "     This is expected if the role still exists in IAM"
    fi
else
    print_message "$GREEN" "  ✓ API Gateway account settings properly reset (no role ARN configured)"
fi
```

## How to Verify the Fix

### Before Cleanup
```bash
# Check if the IAM role exists
aws iam get-role --role-name APIGatewayCloudWatchLogsRole --profile <profile-name>
# Expected: Role details

# Check API Gateway account settings
aws apigateway get-account --profile <profile-name> --query 'cloudwatchRoleArn' --output text
# Expected: arn:aws:iam::ACCOUNT_ID:role/APIGatewayCloudWatchLogsRole
```

### After Cleanup (With Fix)
```bash
# Check if the IAM role exists
aws iam get-role --role-name APIGatewayCloudWatchLogsRole --profile <profile-name>
# Expected: NoSuchEntity error (role deleted)

# Check API Gateway account settings
aws apigateway get-account --profile <profile-name> --query 'cloudwatchRoleArn' --output text
# Expected: None or empty (ARN reference removed)
```

### Console Verification
1. Open AWS Console → API Gateway
2. Go to Settings (left sidebar)
3. Check "CloudWatch log role ARN" field
4. **Expected**: Field should be empty (no role ARN displayed)

## Testing Strategy

### Manual Testing Steps
1. Deploy Lab2-Lab6 (all labs that use API Gateway)
2. Run global cleanup script: `./cleanup-all-labs.sh --profile <profile-name>`
3. Verify Step 4.5 executes and resets API Gateway settings
4. Check IAM console: APIGatewayCloudWatchLogsRole should not exist
5. Check API Gateway console: CloudWatch log role ARN field should be empty
6. Run verification: `aws apigateway get-account --query 'cloudwatchRoleArn'` should return "None"

### Expected Output
```
========================================
Step 4.5: Resetting API Gateway Account Settings
========================================

Checking API Gateway account settings...
  Found API Gateway CloudWatch Logs role ARN: arn:aws:iam::123456789012:role/APIGatewayCloudWatchLogsRole
  Role no longer exists in IAM - resetting API Gateway account settings
    ✓ API Gateway account settings reset successfully
    ✓ Role ARN reference removed from API Gateway

API Gateway account settings check complete
```

## Impact Assessment

### Benefits
- ✅ Complete cleanup of API Gateway account settings
- ✅ No orphaned role ARN references in console
- ✅ Proper verification in final cleanup check
- ✅ Clear user feedback about API Gateway settings reset

### Risk Level
- **Low Risk**: Only affects console display, not functionality
- **Safe Operation**: Uses AWS API to reset settings (no direct manipulation)
- **Idempotent**: Can be run multiple times safely
- **Graceful Failure**: If reset fails, provides clear message that it's cosmetic

### Backward Compatibility
- ✅ No breaking changes to existing cleanup scripts
- ✅ Works with all existing lab cleanup scripts
- ✅ Compatible with parallel and sequential cleanup modes
- ✅ Preserves all existing cleanup functionality

## Related Documentation

- **Task 14**: `.kiro/specs/lab-cleanup-isolation-all-labs/tasks.md` (lines 1939-2340)
- **Global Cleanup Script**: `workshop/scripts/cleanup-all-labs.sh`
- **API Gateway Logs Cleanup**: `workshop/extra-info/API_GATEWAY_LOGS_CLEANUP_UPDATE.md`
- **API Gateway Role Analysis**: `workshop/extra-info/API_GATEWAY_LOGS_ROLE_ANALYSIS.md`

## Next Steps

1. **Test in Real AWS Environment** (Task 14 acceptance criteria)
   - Deploy labs that use API Gateway (Lab2-Lab6)
   - Run global cleanup script
   - Verify role no longer appears in console
   - Document test results

2. **Update User Documentation** (if needed)
   - Add note about API Gateway settings reset to deployment manual
   - Update troubleshooting guide with this fix

3. **Monitor for Issues**
   - Watch for any API Gateway-related errors during cleanup
   - Verify no impact on lab deployments
   - Collect user feedback

## Conclusion

The API Gateway account settings reset fix ensures complete cleanup of workshop resources by removing orphaned role ARN references from API Gateway account settings. This prevents confusion when users see deleted roles still appearing in the AWS console.

**Status**: ✅ Implementation complete, ready for testing in real AWS environment.
