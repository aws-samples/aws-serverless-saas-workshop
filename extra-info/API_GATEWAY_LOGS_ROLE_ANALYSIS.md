# API Gateway CloudWatch Logs Role Analysis

## Issue Summary

During Step 13 end-to-end validation testing, discovered that the `APIGatewayCloudWatchLogsRole` IAM role is NOT being deleted by cleanup scripts, even though it's created by the workshop deployment scripts.

## Discovered Roles

Three IAM roles were found after cleanup:
1. **`APIGatewayCloudWatchLogsRole`** - Created by workshop deployment scripts
2. **`AWSServiceRoleForAPIGateway`** - AWS service-linked role (should NOT be deleted)
3. **`CloudWatch_Investigations`** - Unknown origin (needs investigation)

## Analysis

### 1. APIGatewayCloudWatchLogsRole

**Created By**: Lab1 and Lab2 deployment scripts

**Purpose**: Allows API Gateway to push execution logs to CloudWatch Logs

**Creation Location**: 
- `workshop/Lab1/scripts/deployment.sh` (lines 204-250)
- `workshop/Lab2/scripts/deployment.sh` (lines 251+)

**Creation Logic**:
```bash
ROLE_NAME="APIGatewayCloudWatchLogsRole"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Check if role exists
if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    # Create role with trust policy for apigateway.amazonaws.com
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Allows API Gateway to push logs to CloudWatch Logs"
    
    # Attach managed policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
fi
```

**Scope**: Account-level role (shared across all API Gateways in the account)

**Current Cleanup Status**: ❌ NOT deleted by any cleanup script

**Should Be Deleted**: ✅ YES - This is a workshop-created resource

**Deletion Complexity**: 
- Must be deleted AFTER all API Gateway resources are deleted
- Must detach managed policy before deletion
- Safe to delete if no other API Gateways in the account are using it

### 2. AWSServiceRoleForAPIGateway

**Created By**: AWS automatically when API Gateway is first used

**Purpose**: Service-linked role for API Gateway service operations

**Scope**: Account-level, managed by AWS

**Current Cleanup Status**: N/A (not deleted)

**Should Be Deleted**: ❌ NO - This is an AWS service-linked role

**Why NOT Delete**:
- Service-linked roles are created and managed by AWS services
- Deleting them can break AWS service functionality
- AWS automatically recreates them when needed
- They don't incur costs
- Best practice: Leave service-linked roles alone

**Documentation**: https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html

### 3. CloudWatch_Investigations

**Created By**: Unknown (needs investigation)

**Purpose**: Unknown

**Scope**: Unknown

**Current Cleanup Status**: N/A (not deleted)

**Should Be Deleted**: ❓ NEEDS INVESTIGATION

**Next Steps**:
1. Check if this role is created by any workshop deployment script
2. Check if this is an AWS-managed role
3. Determine if it's safe to delete

## Current Cleanup Script Behavior

### Labs with IAM Role Cleanup

Only **Lab4**, **Lab6**, and **Lab7** cleanup scripts delete IAM roles:

**Lab4** (`workshop/Lab4/scripts/cleanup.sh`):
```bash
# Step 8: Delete IAM roles and policies
IAM_ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'lab4')].RoleName" \
    --output text)

for role in $IAM_ROLES; do
    # Detach managed policies
    # Delete inline policies
    # Delete role
done
```

**Lab6** (`workshop/Lab6/scripts/cleanup.sh`):
```bash
# Step 13: Delete IAM roles (MUST be LAST after all stacks deleted)
IAM_ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'lab6')].RoleName" \
    --output text)

for role in $IAM_ROLES; do
    # Detach managed policies
    # Delete inline policies
    # Delete role
done
```

**Lab7** (`workshop/Lab7/scripts/cleanup.sh`):
```bash
# Step 10: Deleting IAM Roles
ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'lab7')].RoleName" \
    --output text)

for role in $ROLES; do
    # Detach managed policies
    # Delete inline policies
    # Delete role
done
```

### Labs WITHOUT IAM Role Cleanup

**Lab1**, **Lab2**, **Lab3**, and **Lab5** do NOT delete IAM roles.

### Why APIGatewayCloudWatchLogsRole is NOT Deleted

The role name `APIGatewayCloudWatchLogsRole` does NOT contain any lab identifier (`lab1`, `lab2`, etc.), so it's NOT matched by the cleanup scripts' queries:

```bash
# This query will NOT match "APIGatewayCloudWatchLogsRole"
aws iam list-roles --query "Roles[?contains(RoleName, 'lab1')].RoleName"
```

## Recommended Solution

### Option 1: Add Account-Level Role Cleanup to Global Script (RECOMMENDED)

Add a dedicated cleanup step to `workshop/scripts/cleanup-all-labs.sh` that runs AFTER all labs are cleaned up:

```bash
# Step N: Clean up account-level workshop roles
print_message "$BLUE" "=========================================="
print_message "$BLUE" "Step N: Cleaning up account-level workshop roles"
print_message "$BLUE" "=========================================="

# List of workshop-created account-level roles
WORKSHOP_ROLES=(
    "APIGatewayCloudWatchLogsRole"
)

for role_name in "${WORKSHOP_ROLES[@]}"; do
    if aws iam get-role --role-name "$role_name" ${PROFILE:+--profile "$PROFILE"} &> /dev/null; then
        print_message "$YELLOW" "  Found workshop role: $role_name"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            ${PROFILE:+--profile "$PROFILE"} \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            print_message "$YELLOW" "    Detaching policy: $policy_arn"
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" \
                ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role_name" \
            ${PROFILE:+--profile "$PROFILE"} \
            --query "PolicyNames[]" \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            print_message "$YELLOW" "    Deleting inline policy: $policy_name"
            aws iam delete-role-policy \
                --role-name "$role_name" \
                --policy-name "$policy_name" \
                ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        done
        
        # Delete the role
        print_message "$YELLOW" "    Deleting role: $role_name"
        aws iam delete-role \
            --role-name "$role_name" \
            ${PROFILE:+--profile "$PROFILE"} 2>/dev/null || true
        
        print_message "$GREEN" "  ✓ Workshop role deleted: $role_name"
    else
        print_message "$YELLOW" "  Workshop role not found: $role_name (already deleted or never created)"
    fi
done

print_message "$GREEN" "Account-level workshop roles cleanup complete"
```

**Advantages**:
- Centralized cleanup of account-level resources
- Runs AFTER all labs are cleaned up (ensuring no API Gateways are using the role)
- Easy to add more account-level roles in the future
- Doesn't modify individual lab cleanup scripts

**Disadvantages**:
- Only works when using global cleanup script
- Individual lab cleanups won't delete the role

### Option 2: Add to Each Lab Cleanup Script

Add role cleanup to Lab1 and Lab2 cleanup scripts (the labs that create the role).

**Advantages**:
- Role is deleted when the lab that created it is cleaned up
- Works with individual lab cleanup

**Disadvantages**:
- Role is shared across labs, so deleting it in Lab1 cleanup might break Lab2 if it's still deployed
- Requires modifying multiple scripts
- More complex logic needed to check if other labs are still using the role

### Option 3: Hybrid Approach

- Add role cleanup to global script (Option 1)
- Add a check in Lab1/Lab2 cleanup to warn if role exists but other labs are still deployed

**Advantages**:
- Best of both worlds
- Provides user feedback

**Disadvantages**:
- More complex implementation

## Recommendation

**Implement Option 1**: Add account-level role cleanup to `workshop/scripts/cleanup-all-labs.sh`

**Reasoning**:
1. `APIGatewayCloudWatchLogsRole` is an account-level resource shared across labs
2. It should only be deleted when ALL labs are cleaned up
3. The global cleanup script is the right place for account-level resource cleanup
4. This approach is consistent with how we handle other shared resources (SAM buckets, orphaned log groups)
5. Easy to extend for future account-level resources

## Implementation Steps

1. ✅ Document the issue (this file)
2. ⏳ Add account-level role cleanup to `workshop/scripts/cleanup-all-labs.sh`
3. ⏳ Test the fix by:
   - Deploy all labs
   - Run global cleanup
   - Verify `APIGatewayCloudWatchLogsRole` is deleted
4. ⏳ Update verification step in cleanup script to check for remaining IAM roles
5. ⏳ Document the fix in `DEPLOYMENT_CLEANUP_MANUAL.md`

## Testing Plan

### Test Case 1: Global Cleanup
1. Deploy Lab1 and Lab2 (creates `APIGatewayCloudWatchLogsRole`)
2. Verify role exists: `aws iam get-role --role-name APIGatewayCloudWatchLogsRole`
3. Run global cleanup: `./workshop/scripts/cleanup-all-labs.sh --profile <profile>`
4. Verify role is deleted: `aws iam get-role --role-name APIGatewayCloudWatchLogsRole` (should fail)

### Test Case 2: Individual Lab Cleanup
1. Deploy Lab1 (creates `APIGatewayCloudWatchLogsRole`)
2. Deploy Lab2 (reuses existing role)
3. Cleanup Lab1: `./workshop/Lab1/scripts/cleanup.sh --profile <profile>`
4. Verify role still exists (Lab2 might still need it)
5. Cleanup Lab2: `./workshop/Lab2/scripts/cleanup.sh --profile <profile>`
6. Verify role still exists (individual lab cleanups don't delete account-level roles)
7. Run global cleanup to delete account-level roles

### Test Case 3: Service-Linked Role Safety
1. Verify `AWSServiceRoleForAPIGateway` exists
2. Run global cleanup
3. Verify `AWSServiceRoleForAPIGateway` is NOT deleted (service-linked roles should be preserved)

## Related Files

- `workshop/Lab1/scripts/deployment.sh` - Creates APIGatewayCloudWatchLogsRole
- `workshop/Lab2/scripts/deployment.sh` - Creates APIGatewayCloudWatchLogsRole
- `workshop/Lab1/scripts/cleanup.sh` - Does NOT delete IAM roles
- `workshop/Lab2/scripts/cleanup.sh` - Does NOT delete IAM roles
- `workshop/Lab4/scripts/cleanup.sh` - Deletes lab4-specific IAM roles
- `workshop/Lab6/scripts/cleanup.sh` - Deletes lab6-specific IAM roles
- `workshop/Lab7/scripts/cleanup.sh` - Deletes lab7-specific IAM roles
- `workshop/scripts/cleanup-all-labs.sh` - Global cleanup script (needs update)

## Status

- **Issue Discovered**: 2026-01-28 during Step 13 end-to-end validation
- **Analysis Complete**: 2026-01-28
- **Fix Implemented**: ⏳ Pending
- **Fix Tested**: ⏳ Pending
- **Documentation Updated**: ⏳ Pending
