# End-to-End Test Failure Analysis

**Generated:** 2026-01-30
**Test Execution:** 2026-01-30T08:22:49
**Total Duration:** 4h 18m (15,477 seconds)
**Overall Result:** ❌ FAILED (8/11 steps passed, 3 failed)

---

## Executive Summary

The end-to-end test revealed a **critical cleanup isolation bug in Lab6** that cascaded into subsequent test failures. The Lab6 cleanup script only deleted 1 out of 10 Lab6 stacks, leaving 9 stacks and associated resources orphaned. This incomplete cleanup caused Lab5 deployment to fail in the redeployment step, and prevented complete final cleanup.

### Impact Assessment

- **Severity:** HIGH - Complete cleanup failure for Lab6
- **Scope:** Lab6 cleanup script, affects Lab5 deployment
- **User Impact:** Users cannot fully clean up Lab6 resources, leading to:
  - Orphaned AWS resources and ongoing costs
  - Deployment failures for subsequent labs
  - Manual cleanup required

---

## Root Cause Analysis

### Step 8 Failure: Lab6 Cleanup Incomplete

**What Happened:**
- Lab6 cleanup script ran for only 2.5 minutes (expected: 15-30 minutes)
- Only deleted `stack-lab6-pooled` (1 tenant stack)
- Failed to delete the main `serverless-saas-shared-lab6` stack and its 8 nested stacks
- Failed to delete `serverless-saas-pipeline-lab6` stack
- Left 41 Lab6 resources orphaned (9 stacks, 8 S3 buckets, 32 log groups, 2 Cognito pools)

**Resources Before Cleanup (67 total):**
- **Stacks (12):**
  - `serverless-saas-lab7`
  - `serverless-saas-pipeline-lab6` ← NOT DELETED
  - `serverless-saas-shared-lab6` ← NOT DELETED
  - `serverless-saas-shared-lab6-APIGatewayLambdaPermissions-151VNHMVSUWD` ← NOT DELETED
  - `serverless-saas-shared-lab6-APIs-1D660X1O23M5N` ← NOT DELETED
  - `serverless-saas-shared-lab6-Cognito-1SLGT6NWZT335` ← NOT DELETED
  - `serverless-saas-shared-lab6-CustomResources-1M06GPG5N2WG9` ← NOT DELETED
  - `serverless-saas-shared-lab6-DynamoDBTables-1QZJEQV5VTGE9` ← NOT DELETED
  - `serverless-saas-shared-lab6-LambdaFunctions-170TNQ3H7UHRG` ← NOT DELETED
  - `serverless-saas-shared-lab6-UserInterface-1U9USKEU0252Y` ← NOT DELETED
  - `stack-lab6-pooled` ← DELETED ✓
  - `stack-pooled-lab7`

- **S3 Buckets (8):** All Lab6 buckets remained
- **Log Groups (45):** Only 13 deleted, 32 remained
- **Cognito Pools (2):** Both Lab6 pools remained

**Resources After Cleanup (53 total):**
- **Stacks (11):** Only 1 stack deleted (stack-lab6-pooled)
- **S3 Buckets (8):** No buckets deleted
- **Log Groups (32):** 13 log groups deleted
- **Cognito Pools (2):** No pools deleted

**Root Cause Identified:**

After analyzing the Lab6 cleanup script (`workshop/Lab6/scripts/cleanup.sh`), the issue is clear:

1. **Script Structure:** The script follows the correct security-conscious deletion order:
   - Step 1: Delete tenant stacks (stack-*)
   - Step 4: Delete tenant template stack (serverless-saas-tenant-lab6)
   - Step 5: Delete shared stack (serverless-saas-shared-lab6) - **WAITS for CloudFront deletion**
   - Step 6: Delete S3 buckets (after CloudFront is gone)
   - Step 9: Delete pipeline stack (serverless-saas-pipeline-lab6)

2. **The Problem:** The script uses `aws cloudformation wait stack-delete-complete` which has a **default timeout of 120 minutes** (2 hours). However:
   - The test shows cleanup took only **2.5 minutes** before moving to the next step
   - This indicates the wait command **exited prematurely** or **failed silently**
   - The script likely encountered an error during stack deletion but continued execution

3. **Likely Failure Point:** Step 5 (Delete shared stack) - Lines 649-672:
   ```bash
   if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION"; then
       print_message "$GREEN" "✓ Stack serverless-saas-shared-lab6 deleted successfully (including CloudFront distributions)"
   else
       print_message "$RED" "Stack deletion failed or timed out"
       print_message "$RED" "Please check AWS Console for stack status"
       exit 1  # ← Script should exit here but didn't
   fi
   ```

4. **Why It Failed:**
   - The `set -e` at the top of the script should cause it to exit on any error
   - However, the `wait stack-delete-complete` command may have returned a non-zero exit code
   - The script's error handling may not have caught this properly
   - The test framework may have continued despite the script failure

**Evidence from Logs:**
- Step 8 duration: 151 seconds (2.5 minutes) - Far too short for CloudFront deletion
- No error message in the test report (error field is "None")
- Only 1 stack deleted (stack-lab6-pooled) out of 10 total Lab6 stacks
- All subsequent steps show Lab6 resources still present

---

### Step 10 Failure: Lab5 Deployment Failed

**What Happened:**
- Redeployment of all labs was attempted after Lab6 cleanup
- Labs 1, 2, 3, 4, and 7 deployed successfully
- **Lab5 failed to deploy** - `serverless-saas-pipeline-lab5` stack missing from resources_after
- Orphaned Lab6 resources (9 stacks, 8 S3 buckets) were still present during deployment

**Resources Before Deployment (41 total):**
- 9 Lab6 stacks (orphaned from Step 8 failure)
- 5 S3 buckets (3 Lab6 buckets + 2 Lab7 buckets)
- 25 log groups (mostly Lab6)
- 2 Cognito pools (both Lab6)

**Resources After Deployment (184 total):**
- 35 stacks (Lab1, Lab2, Lab3, Lab4, Lab7 deployed + 9 orphaned Lab6 stacks)
- 23 S3 buckets
- 118 log groups
- 8 Cognito pools

**Missing Stack:**
- `serverless-saas-pipeline-lab5` - NOT present in resources_after

**Root Cause:**
The Lab5 deployment failure is likely caused by one of these issues:

1. **Resource Conflicts:** Orphaned Lab6 resources may have conflicting names or exports with Lab5
2. **CDK Bootstrap Conflict:** Lab6 cleanup script has logic to skip CDKToolkit deletion if Lab5 is deployed (lines 711-745), but the reverse scenario (Lab5 deploying when Lab6 resources exist) may not be handled
3. **Deployment Script Error:** The parallel deployment script may have encountered an error specific to Lab5

**Evidence:**
- Warning message: "Labs not deployed: lab5"
- All other labs deployed successfully
- Lab6 resources still present during deployment
- Lab5 uses CDK for pipeline deployment (same as Lab6)

---

### Step 11 Failure: Final Cleanup Incomplete

**What Happened:**
- Final cleanup attempted to remove all remaining resources
- Successfully cleaned up Labs 1, 2, 3, 4, and 7
- **Failed to clean up Lab6 resources** (same 9 stacks + 2 Cognito pools remained)
- 11 resources still exist after final cleanup

**Resources Before Final Cleanup (184 total):**
- 35 stacks (including 9 orphaned Lab6 stacks)
- 23 S3 buckets
- 118 log groups
- 8 Cognito pools

**Resources After Final Cleanup (11 total):**
- **9 Lab6 stacks** (same ones from Step 8 failure):
  - `serverless-saas-pipeline-lab6`
  - `serverless-saas-shared-lab6`
  - `serverless-saas-shared-lab6-APIGatewayLambdaPermissions-151VNHMVSUWD`
  - `serverless-saas-shared-lab6-APIs-1D660X1O23M5N`
  - `serverless-saas-shared-lab6-Cognito-1SLGT6NWZT335`
  - `serverless-saas-shared-lab6-CustomResources-1M06GPG5N2WG9`
  - `serverless-saas-shared-lab6-DynamoDBTables-1QZJEQV5VTGE9`
  - `serverless-saas-shared-lab6-LambdaFunctions-170TNQ3H7UHRG`
  - `serverless-saas-shared-lab6-UserInterface-1U9USKEU0252Y`
- **2 Lab6 Cognito pools:**
  - `OperationUsers-ServerlessSaas-lab6-UserPool`
  - `PooledTenant-ServerlessSaaS-lab6-UserPool`
- **0 S3 buckets** (all deleted successfully)
- **0 log groups** (all deleted successfully)

**Root Cause:**
- The global cleanup script (`workshop/scripts/cleanup-all-labs.sh`) calls individual lab cleanup scripts
- Lab6 cleanup script failed again (same issue as Step 8)
- The global script continued despite Lab6 failure (likely has `--continue-on-error` behavior)

**Evidence:**
- Same 9 Lab6 stacks remain as in Step 8
- Same 2 Lab6 Cognito pools remain
- All other labs cleaned up successfully
- Error message: "CRITICAL: 11 resources still exist after final cleanup"

---

## Cascading Failure Chain

```
Step 8: Lab6 Cleanup Fails
    ↓
9 Lab6 stacks + resources orphaned
    ↓
Step 10: Lab5 Deployment Fails
    ↓
Lab5 pipeline stack not created
    ↓
Step 11: Final Cleanup Fails
    ↓
11 Lab6 resources remain
```

---

## Technical Details

### Lab6 Cleanup Script Analysis

**File:** `workshop/Lab6/scripts/cleanup.sh`

**Critical Sections:**

1. **Step 5: Delete Shared Stack (Lines 649-672)**
   ```bash
   if aws cloudformation $PROFILE_ARG describe-stacks --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION" &>/dev/null; then
       print_message "$YELLOW" "  Deleting stack: serverless-saas-shared-lab6"
       aws cloudformation $PROFILE_ARG delete-stack --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION"
       
       print_message "$YELLOW" "Waiting for stack serverless-saas-shared-lab6 to be deleted..."
       print_message "$YELLOW" "⏳ This may take 15-30 minutes for CloudFront distributions to fully delete"
       
       # Use AWS CLI wait command for reliable stack deletion monitoring
       if aws cloudformation wait stack-delete-complete $PROFILE_ARG --stack-name "serverless-saas-shared-lab6" --region "$AWS_REGION"; then
           print_message "$GREEN" "✓ Stack serverless-saas-shared-lab6 deleted successfully"
       else
           print_message "$RED" "Stack deletion failed or timed out"
           print_message "$RED" "Please check AWS Console for stack status"
           exit 1  # ← Should exit here but didn't
       fi
   fi
   ```

2. **Step 9: Delete Pipeline Stack (Lines 723-729)**
   ```bash
   # Use the CDK role-aware deletion function for pipeline stack
   delete_stack_with_cdk_role "serverless-saas-pipeline-lab6"
   ```

**Potential Issues:**

1. **Silent Failure:** The `wait stack-delete-complete` command may have failed but the script continued
2. **Error Handling:** The `set -e` may not catch all error conditions
3. **Test Framework:** The test framework may have a timeout that killed the script before completion
4. **AWS API Issues:** Transient AWS API errors during stack deletion

### Expected vs Actual Behavior

| Aspect | Expected | Actual |
|--------|----------|--------|
| Duration | 15-30 minutes (CloudFront deletion) | 2.5 minutes |
| Stacks Deleted | 10 (all Lab6 stacks) | 1 (stack-lab6-pooled only) |
| S3 Buckets Deleted | 3 (after CloudFront) | 0 |
| Log Groups Deleted | 45 | 13 |
| Cognito Pools Deleted | 2 | 0 |
| Script Exit Code | 0 (success) | Unknown (likely non-zero) |

---

## Recommendations

### Immediate Actions (Critical)

1. **Fix Lab6 Cleanup Script Error Handling**
   - Add explicit error checking after each critical operation
   - Add timeout handling for long-running operations
   - Add retry logic for transient failures
   - Improve logging to capture actual error messages

2. **Add Stack Deletion Verification**
   - After initiating stack deletion, verify it entered DELETE_IN_PROGRESS state
   - Poll stack status during wait to detect failures early
   - Add fallback logic if wait times out

3. **Improve Test Framework Integration**
   - Capture script exit codes properly
   - Set appropriate timeouts for long-running operations
   - Add better error message propagation from scripts to test framework

### Short-term Fixes

1. **Add Pre-deletion Checks**
   - Verify stack exists before attempting deletion
   - Check for stack dependencies before deletion
   - Validate CloudFormation stack status

2. **Enhance Logging**
   - Log AWS CLI command outputs (not just success/failure)
   - Add timestamps for each operation
   - Log stack status changes during wait operations

3. **Add Cleanup Verification**
   - After each deletion step, verify resources are actually gone
   - Add explicit checks for orphaned resources
   - Fail fast if critical resources remain

### Long-term Improvements

1. **Implement Idempotent Cleanup**
   - Make cleanup script safe to run multiple times
   - Skip already-deleted resources gracefully
   - Add resume capability for interrupted cleanups

2. **Add Parallel Deletion with Dependencies**
   - Delete independent resources in parallel
   - Respect dependency order (CloudFront before S3)
   - Add progress tracking for parallel operations

3. **Create Cleanup Health Check**
   - Add a separate verification script
   - Run after cleanup to detect orphaned resources
   - Provide manual cleanup instructions for stuck resources

---

## Testing Recommendations

### Before Fix Deployment

1. **Manual Reproduction**
   - Deploy Lab6 in a test account
   - Run cleanup script with verbose logging
   - Capture exact error messages and stack states

2. **Identify Exact Failure Point**
   - Add debug logging to cleanup script
   - Run step-by-step to isolate failure
   - Check CloudFormation events for stack deletion errors

### After Fix Deployment

1. **Unit Test Cleanup Script**
   - Test each cleanup step independently
   - Mock AWS API responses for error scenarios
   - Verify error handling paths

2. **Integration Test**
   - Run full Lab6 deployment and cleanup cycle
   - Verify all resources are deleted
   - Check for orphaned resources

3. **Re-run End-to-End Test**
   - Execute full test suite with fixed script
   - Verify all 11 steps pass
   - Confirm no orphaned resources remain

---

## Impact on Users

### Current State

Users running Lab6 cleanup will experience:
- Incomplete resource deletion
- Orphaned CloudFormation stacks
- Ongoing AWS costs for orphaned resources
- Manual cleanup required via AWS Console
- Potential conflicts with subsequent lab deployments

### After Fix

Users will experience:
- Complete resource deletion
- No orphaned resources
- Proper cleanup of all Lab6 resources
- Reliable cleanup for subsequent test runs

---

## Related Files

- `workshop/Lab6/scripts/cleanup.sh` - Lab6 cleanup script (needs fix)
- `workshop/scripts/cleanup-all-labs.sh` - Global cleanup script
- `workshop/tests/test_end_to_end_cleanup_isolation.py` - End-to-end test
- `workshop/tests/end_to_end_test_report/logs/step_08_cleanup_lab6.log` - Failure log
- `workshop/tests/end_to_end_test_report/SUMMARY.md` - Test summary

---

## Conclusion

The end-to-end test successfully identified a critical bug in the Lab6 cleanup script that causes incomplete resource deletion. The root cause is a silent failure during CloudFormation stack deletion, likely due to inadequate error handling or timeout issues. This bug has cascading effects on subsequent operations and leaves users with orphaned AWS resources.

The fix requires improving error handling, adding explicit verification steps, and enhancing logging in the Lab6 cleanup script. Once fixed, the end-to-end test should pass all 11 steps and verify complete cleanup isolation across all labs.

---

**Next Steps:**
1. Create a spec for fixing the Lab6 cleanup script
2. Implement the fix with proper error handling
3. Add verification steps to prevent silent failures
4. Re-run the end-to-end test to verify the fix
5. Update documentation with lessons learned
