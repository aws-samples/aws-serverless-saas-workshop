# Orphaned Resource Detection Fix

## Issue Summary

The cleanup-all-labs script was incorrectly flagging legitimate resources as "orphaned" after successful cleanup operations. This created confusion and false warnings about resources that had already been properly deleted.

## Root Cause Analysis

### Problem 1: Stale Stack Discovery
The script captured all lab-related stacks at the beginning (Step 1.5) before any cleanup operations. After individual lab cleanup scripts successfully deleted these stacks, the orphaned resource detection still reported them as "orphaned" because it was using the stale stack list from the beginning.

### Problem 2: Nested Stacks Not Excluded
CloudFormation/SAM creates nested stacks (e.g., `serverless-saas-shared-lab6-APIs-1STKRYVRR022R`) that are automatically managed by parent stacks. These nested stacks were being flagged as orphaned because they weren't in the expected stack name list, even though they are legitimate and automatically deleted when parent stacks are deleted.

### Problem 3: Tenant Stack Patterns Not Recognized
Tenant stacks with naming patterns like:
- `stack-lab6-pooled`
- `stack-pooled-lab7`
- `stack-lab3-<tenant-id>`

Were not included in the expected stack name lists, causing them to be flagged as orphaned even though they are legitimate tenant infrastructure stacks.

## Evidence from Logs

From `cleanup-all-labs-20260127-145441.log`:

**Lab7 Cleanup (Line 114):**
```
✓ Stack stack-pooled-lab7 deleted successfully (including CloudFront distributions)
```

**Lab6 Cleanup (Line 210):**
```
✓ Deleted: stack-lab6-pooled
```

**Orphaned Resource Detection (Line 745):**
```
WARNING: Orphaned resources detected that were not cleaned up by lab-specific cleanup scripts.
  CloudFormation Stacks:
    - stack-lab6-pooled
    - serverless-saas-shared-lab6-APIGatewayLambdaPermissions-69HT3AC69VMA (nested)
    - serverless-saas-shared-lab6-CustomResources-1EIZ9Q5HZN1A4 (nested)
    - serverless-saas-shared-lab6-APIs-1STKRYVRR022R (nested)
    - serverless-saas-shared-lab6-LambdaFunctions-103NRMGNFBOTA (nested)
    - serverless-saas-shared-lab6-Cognito-1CFITXCQCW3DD (nested)
    - serverless-saas-shared-lab6-UserInterface-GRMEJBS3SKJK (nested)
    - serverless-saas-shared-lab6-DynamoDBTables-DWNLGTQXQUKJ (nested)
    - stack-pooled-lab7
```

The stacks were already deleted but still reported as orphaned.

## Solution Implemented

### 1. Re-Query Stacks After Cleanup
Instead of using the stale stack list from Step 1.5, the script now re-queries all lab-related stacks AFTER individual lab cleanups complete. This ensures we're checking the current state, not the state from before cleanup.

```bash
# Re-query all lab-related stacks AFTER individual lab cleanups to get current state
print_message "$YELLOW" "Re-querying lab-related stacks after individual cleanups..."
CURRENT_LAB_STACKS=$(aws cloudformation list-stacks \
    ${PROFILE:+--profile "$PROFILE"} \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
    --region us-east-1 \
    --query 'StackSummaries[?contains(StackName, `lab1`) || contains(StackName, `lab2`) || contains(StackName, `lab3`) || contains(StackName, `lab4`) || contains(StackName, `lab5`) || contains(StackName, `lab6`) || contains(StackName, `lab7`)].StackName' \
    --output text 2>/dev/null || echo "")
```

### 2. Exclude Nested Stacks
Added a helper function `is_nested_stack()` that checks if a stack has a parent stack ID. Nested stacks are automatically managed by CloudFormation and should not be flagged as orphaned.

```bash
# Helper function to check if a stack is a nested stack
is_nested_stack() {
    local stack_name="$1"
    local parent_id=$(aws cloudformation describe-stacks \
        ${PROFILE:+--profile "$PROFILE"} \
        --region us-east-1 \
        --stack-name "$stack_name" \
        --query 'Stacks[0].ParentId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$parent_id" && "$parent_id" != "None" ]]; then
        return 0  # Is a nested stack
    else
        return 1  # Not a nested stack
    fi
}
```

### 3. Recognize Tenant Stack Patterns
Updated the `is_expected_stack()` helper function to include tenant stack naming patterns for each lab:

**Lab3-4 Patterns:**
- `stack-lab3-*` or `*-lab3` (tenant stacks)
- `stack-lab4-*` or `*-lab4` (tenant stacks)

**Lab5-6 Patterns:**
- `stack-lab5-*` or `*-lab5` (tenant stacks)
- `stack-lab6-*` or `*-lab6` (tenant stacks)

**Lab7 Patterns:**
- `stack-*-lab7` or `*-lab7` (tenant stacks like `stack-pooled-lab7`)

```bash
# Helper function to check if a stack name matches expected patterns
is_expected_stack() {
    local stack_name="$1"
    local lab_num="$2"
    
    case "$lab_num" in
        3)
            [[ "$stack_name" == "serverless-saas-shared-lab3" || 
               "$stack_name" == "serverless-saas-tenant-lab3" || 
               "$stack_name" =~ ^stack-lab3- || 
               "$stack_name" =~ -lab3$ ]]
            ;;
        # ... similar patterns for other labs
    esac
}
```

### 4. Improved Detection Logic
The new logic:
1. Re-queries stacks after individual cleanups (current state)
2. Skips nested stacks (managed by parent stacks)
3. Checks if stack name matches expected patterns (including tenant stacks)
4. Only flags as orphaned if:
   - Stack name doesn't match any expected pattern, OR
   - Stack belongs to a lab that was successfully cleaned but still exists

## Benefits

1. **Eliminates False Positives**: No more warnings about resources that were already properly deleted
2. **Accurate Detection**: Only truly orphaned resources are flagged
3. **Better User Experience**: Users can trust the orphaned resource warnings
4. **Proper Tenant Stack Handling**: Tenant stacks are now recognized as legitimate infrastructure
5. **Nested Stack Awareness**: CloudFormation-managed nested stacks are properly excluded

## Testing Recommendations

To verify the fix works correctly:

1. Deploy all labs
2. Run cleanup-all-labs script
3. Verify no false orphaned resource warnings
4. Check that legitimate orphaned resources (if any) are still detected

## Related Files

- `workshop/scripts/cleanup-all-labs.sh` - Main cleanup orchestration script (fixed)
- `.kiro/specs/lab-cleanup-isolation-all-labs/tasks.md` - Task 13 validation
- `workshop/scripts/logs/cleanup-all-labs-20260127-145441.log` - Log showing the issue

## NEW ISSUE DISCOVERED: Interactive Flag Logic Backwards (January 27, 2026)

### Problem
The orphaned resource deletion prompt logic is inverted:

```bash
if [ "$INTERACTIVE" = false ]; then
    read -p "Delete orphaned resources? (yes/no): " confirm
else
    confirm="yes"
fi
```

**Current Behavior:**
- When `INTERACTIVE=false` (default): Script PROMPTS user for confirmation
- When `INTERACTIVE=true`: Script AUTO-CONFIRMS without prompting

**Expected Behavior:**
- When `INTERACTIVE=false` (default): Script should AUTO-CONFIRM (non-interactive mode)
- When `INTERACTIVE=true`: Script should PROMPT user (interactive mode)

### Impact
When running the script in default mode (non-interactive), it waits for user input that may never come, leaving orphaned resources undeleted. This is what happened in the latest cleanup run where orphaned resources were detected but not deleted.

### Evidence
From `cleanup-all-labs-20260127-154304.log`:
```
Orphaned Resources Found:
  CloudFormation Stacks:
    - serverless-saas-pipeline-lab6
    - serverless-saas-shared-lab6
  S3 Buckets:
    - sam-bootstrap-bucket-lab6-shared
    - serverless-saas-lab6-admin-376cc2f0
    - serverless-saas-lab6-app-376cc2f0
    - serverless-saas-lab6-landing-376cc2f0
    - serverless-saas-pipeline-lab6-artifacts-577618c0

WARNING: Orphaned resources detected that were not cleaned up by lab-specific cleanup scripts.
These resources may have been created outside the normal deployment process.

[Log ends abruptly - script was waiting for user input]
```

The script detected orphaned resources but the log ends without showing deletion, indicating it was waiting for user input.

### Solution Required
Fix the logic to match expected behavior:

```bash
if [ "$INTERACTIVE" = true ]; then
    read -p "Delete orphaned resources? (yes/no): " confirm
else
    confirm="yes"  # Auto-confirm in non-interactive mode
fi
```

### Workaround
Until fixed, users can:
1. Use `-i` or `--interactive` flag to auto-confirm (counterintuitive but works)
2. Manually respond "yes" when prompted
3. Use `echo "yes" | ./cleanup-all-labs.sh` to pipe confirmation

## NEW ISSUE DISCOVERED: Pipeline Stack Won't Delete Due to Missing CDK Role (January 27, 2026)

### Problem
The `serverless-saas-pipeline-lab6` stack cannot be deleted because its CDK execution role was already deleted by a previous cleanup operation.

**Stack Details:**
- Stack Name: `serverless-saas-pipeline-lab6`
- Stack Status: `CREATE_COMPLETE`
- Role ARN: `arn:aws:iam::265098672980:role/cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1`
- Role Status: **DOES NOT EXIST** (NoSuchEntity error)

**Symptoms:**
- `aws cloudformation delete-stack` returns success (exit code 0)
- Stack remains in `CREATE_COMPLETE` status
- No actual deletion occurs
- CloudFormation silently fails because it can't assume the execution role

### Root Cause
When a CloudFormation stack is created with a specific execution role (common with CDK stacks), CloudFormation requires that role to exist when deleting the stack. If the role is deleted before the stack, CloudFormation cannot proceed with deletion even though the delete command appears to succeed.

This is a known CloudFormation behavior: the service validates the role exists before attempting deletion, but the AWS CLI doesn't surface this validation failure to the user.

### Solution Implemented
The Lab6 cleanup script already has a `delete_stack_with_cdk_role()` function that handles this scenario, but it wasn't being triggered properly. The manual fix involved:

1. **Create temporary CDK execution role:**
   ```bash
   aws iam create-role \
     --role-name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 \
     --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
   ```

2. **Attach AdministratorAccess policy:**
   ```bash
   aws iam attach-role-policy \
     --role-name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

3. **Wait for role propagation (5 seconds)**

4. **Delete the stack:**
   ```bash
   aws cloudformation delete-stack --stack-name serverless-saas-pipeline-lab6
   ```
   
   Result: Stack status changed to `DELETE_IN_PROGRESS` ✓

5. **Wait for deletion to complete:**
   ```bash
   aws cloudformation wait stack-delete-complete --stack-name serverless-saas-pipeline-lab6
   ```

6. **Clean up temporary role:**
   ```bash
   aws iam detach-role-policy \
     --role-name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   
   aws iam delete-role \
     --role-name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1
   ```

### Why the Lab6 Cleanup Script Didn't Handle This
The `delete_stack_with_cdk_role()` function in Lab6's cleanup script checks for a specific error message pattern:
```bash
if echo "$delete_output" | grep -q "is invalid or cannot be assumed"; then
```

However, when the role doesn't exist, CloudFormation doesn't return this error message - it just silently fails to delete the stack. The delete command returns success, but no deletion occurs.

### Recommended Fix for Lab6 Cleanup Script
The `delete_stack_with_cdk_role()` function should be enhanced to:
1. Check if the CDK role exists BEFORE attempting deletion
2. If role doesn't exist, create it proactively
3. Then proceed with deletion
4. Clean up the temporary role after deletion completes

This would prevent the silent failure scenario.

### Verification
After applying the fix:
- ✓ `serverless-saas-pipeline-lab6` stack successfully deleted
- ✓ `serverless-saas-shared-lab6` stack already deleted
- ✓ All Lab6 S3 buckets successfully deleted:
  - `sam-bootstrap-bucket-lab6-shared`
  - `serverless-saas-lab6-admin-376cc2f0`
  - `serverless-saas-lab6-app-376cc2f0`
  - `serverless-saas-lab6-landing-376cc2f0`
  - `serverless-saas-pipeline-lab6-artifacts-577618c0`
- ✓ No remaining Lab6 CloudFormation stacks
- ✓ No remaining Lab6 S3 buckets

### Impact
This issue affects any CDK-deployed stack where the execution role is deleted before the stack. It's particularly problematic because:
1. The delete command appears to succeed (no error)
2. The stack remains in a "zombie" state
3. Users may not realize the stack wasn't actually deleted
4. Orphaned resources accumulate

### Related Files
- `workshop/Lab6/scripts/cleanup.sh` - Contains `delete_stack_with_cdk_role()` function (needs enhancement)
- `workshop/scripts/cleanup-all-labs.sh` - Orchestration script that detected the orphaned stack
- `workshop/scripts/logs/cleanup-all-labs-20260127-154304.log` - Log showing orphaned resources

## Spec Task Reference

This fix addresses the orphaned resource warning discovered during Task 13 (Final Checkpoint - End-to-End Validation) of the lab-cleanup-isolation-all-labs spec.

**Update (January 27, 2026)**: Three critical issues were discovered during Task 13 validation:
1. Interactive flag logic was backwards in cleanup-all-labs script (FIXED)
2. Pipeline stack won't delete due to missing CDK execution role (FIXED)
3. **CDKToolkit stack is shared between labs but deleted by individual lab cleanup scripts (CRITICAL BUG)**

## CRITICAL BUG #3: CDKToolkit Stack Deletion Breaks Other Labs (January 27, 2026)

### Problem
Both Lab5 and Lab6 cleanup scripts delete the **CDKToolkit stack**, which is a **SHARED resource** across all labs in the same AWS account+region. This causes a cascading failure:

**Stack Details:**
- CDKToolkit stack: Created once per AWS account+region (not per lab)
- CDK Execution Role: `arn:aws:iam::265098672980:role/cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1`
- This role is created by CDKToolkit and used by ALL CDK-deployed stacks (Lab5 and Lab6 pipelines)

**Failure Scenario:**
1. Lab5 cleanup runs and deletes CDKToolkit stack (Step 10, line 755 in `workshop/Lab5/scripts/cleanup.sh`)
2. CloudFormation deletes CDKToolkit stack and all its resources, including the CDK execution role
3. Lab6 pipeline stack (`serverless-saas-pipeline-lab6`) still references the deleted CDK execution role
4. Lab6 cleanup tries to delete the pipeline stack but fails silently because the role doesn't exist
5. Pipeline stack remains in CREATE_COMPLETE state (zombie stack)

**Evidence:**
```bash
# Lab6 pipeline stack still references deleted role
$ aws cloudformation describe-stacks --stack-name serverless-saas-pipeline-lab6 --query 'Stacks[0].RoleARN'
arn:aws:iam::265098672980:role/cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1

# But the role doesn't exist
$ aws iam get-role --role-name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1
NoSuchEntity: The role with name cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 cannot be found

# CDKToolkit stack was deleted
$ aws cloudformation describe-stacks --stack-name CDKToolkit
ValidationError: Stack with id CDKToolkit does not exist
```

### Root Cause
**Design Flaw:** Individual lab cleanup scripts delete shared CDK resources (CDKToolkit stack) without considering that other labs may still need them.

**Why This Happens:**
1. CDK creates a single CDKToolkit stack per account+region, not per lab
2. All CDK-deployed stacks (Lab5 pipeline, Lab6 pipeline) share the same CDK execution role
3. Lab cleanup scripts assume they own all CDK resources they use
4. No coordination between lab cleanup scripts to check if other labs are still using CDK resources

### Solution Implemented (January 27, 2026)

**User's Solution Approach:**
Each lab checks if the other lab is deployed before deleting CDKToolkit. This ensures CDKToolkit is only deleted when it's safe to do so.

**Lab5 Cleanup Script Changes (Lines 730-790):**
```bash
# CRITICAL: Check if Lab6 is deployed before deleting CDKToolkit
# CDKToolkit is a SHARED resource between Lab5 and Lab6
# We can only delete it if Lab6 is NOT deployed
LAB6_DEPLOYED=false

# Check for Lab6 pipeline stack (uses CDK)
LAB6_PIPELINE=$(aws cloudformation describe-stacks --stack-name "serverless-saas-pipeline-lab6" 2>/dev/null)
if [[ $? -eq 0 ]]; then
  LAB6_DEPLOYED=true
  echo "⚠️  Lab6 pipeline stack detected - CDKToolkit is still in use"
fi

# Check for Lab6 shared stack (might have CDK dependencies)
if [[ "$LAB6_DEPLOYED" == false ]]; then
  LAB6_SHARED=$(aws cloudformation describe-stacks --stack-name "serverless-saas-shared-lab6" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    LAB6_DEPLOYED=true
    echo "⚠️  Lab6 shared stack detected - CDKToolkit might still be in use"
  fi
fi

# Delete CDKToolkit stack only if Lab6 is NOT deployed
if [[ "$LAB6_DEPLOYED" == true ]]; then
  echo "⚠️  Skipping CDKToolkit stack deletion - Lab6 is still deployed"
  echo "   Lab6 pipeline stack uses the shared CDK execution role from CDKToolkit"
  echo "   CDKToolkit will be deleted when Lab6 is cleaned up"
else
  echo "✓ Lab6 is not deployed - safe to delete CDKToolkit"
  if delete_stack "CDKToolkit"; then
    wait_for_deletion "CDKToolkit"
  fi
fi
```

**Lab6 Cleanup Script Changes (Lines 708-768):**
```bash
# CRITICAL: Check if Lab5 is deployed before deleting CDKToolkit
# CDKToolkit is a SHARED resource between Lab5 and Lab6
# We can only delete it if Lab5 is NOT deployed
LAB5_DEPLOYED=false

# Check for Lab5 pipeline stack (uses CDK)
LAB5_PIPELINE=$(aws cloudformation describe-stacks --stack-name "serverless-saas-pipeline-lab5" 2>/dev/null)
if [[ $? -eq 0 ]]; then
  LAB5_DEPLOYED=true
  print_message "$YELLOW" "⚠️  Lab5 pipeline stack detected - CDKToolkit is still in use"
fi

# Check for Lab5 shared stack (might have CDK dependencies)
if [[ "$LAB5_DEPLOYED" == false ]]; then
  LAB5_SHARED=$(aws cloudformation describe-stacks --stack-name "serverless-saas-shared-lab5" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    LAB5_DEPLOYED=true
    print_message "$YELLOW" "⚠️  Lab5 shared stack detected - CDKToolkit might still be in use"
  fi
fi

# Delete CDKToolkit stack only if Lab5 is NOT deployed
if [[ "$LAB5_DEPLOYED" == true ]]; then
  print_message "$YELLOW" "⚠️  Skipping CDKToolkit stack deletion - Lab5 is still deployed"
  print_message "$YELLOW" "   Lab5 pipeline stack uses the shared CDK execution role from CDKToolkit"
  print_message "$YELLOW" "   CDKToolkit will be deleted when Lab5 is cleaned up"
else
  print_message "$GREEN" "✓ Lab5 is not deployed - safe to delete CDKToolkit"
  if delete_stack "CDKToolkit"; then
    wait_for_deletion "CDKToolkit"
  fi
fi
```

**Test Cases Added (workshop/tests/test_end_to_end_cleanup_isolation.py):**
1. `test_lab5_skips_cdktoolkit_when_lab6_deployed()` - Verifies Lab5 cleanup skips CDKToolkit when Lab6 is deployed
2. `test_lab6_skips_cdktoolkit_when_lab5_deployed()` - Verifies Lab6 cleanup skips CDKToolkit when Lab5 is deployed
3. `test_lab5_deletes_cdktoolkit_when_lab6_not_deployed()` - Verifies Lab5 cleanup deletes CDKToolkit when Lab6 is NOT deployed
4. `test_lab6_deletes_cdktoolkit_when_lab5_not_deployed()` - Verifies Lab6 cleanup deletes CDKToolkit when Lab5 is NOT deployed

**Behavior Matrix:**

| Scenario | Lab5 Cleanup | Lab6 Cleanup | CDKToolkit Deleted By |
|----------|--------------|--------------|----------------------|
| Both labs deployed, Lab5 cleaned first | Skips CDKToolkit | Deletes CDKToolkit | Lab6 |
| Both labs deployed, Lab6 cleaned first | Deletes CDKToolkit | Skips CDKToolkit | Lab5 |
| Only Lab5 deployed | Deletes CDKToolkit | N/A | Lab5 |
| Only Lab6 deployed | N/A | Deletes CDKToolkit | Lab6 |

**Benefits:**
1. No orphaned pipeline stacks - CDKToolkit is only deleted when safe
2. No manual intervention required - scripts automatically detect other lab deployments
3. Works regardless of cleanup order - Lab5 or Lab6 can be cleaned first
4. Maintains cleanup isolation - each lab only cleans its own resources

### Impact
This bug affects any deployment where:
1. Multiple labs use CDK-deployed resources (Lab5 and Lab6 pipelines)
2. Labs are cleaned up individually rather than all at once
3. Lab5 is cleaned up before Lab6

**Severity:** CRITICAL - Causes orphaned resources and prevents proper cleanup
**Status:** FIXED (January 27, 2026)

### Related Files
- `workshop/Lab5/scripts/cleanup.sh` - Lines 730-790: CDKToolkit check implementation (FIXED)
- `workshop/Lab6/scripts/cleanup.sh` - Lines 708-768: CDKToolkit check implementation (FIXED)
- `workshop/Lab6/scripts/cleanup.sh` - Lines 220-310: Enhanced delete_stack_with_cdk_role function (WORKAROUND)
- `workshop/tests/test_end_to_end_cleanup_isolation.py` - Lines 890-1010: CDKToolkit test cases (ADDED)
