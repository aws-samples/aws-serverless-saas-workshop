# IAM Role Deletion Order Fix

## Problem Statement

**Critical Issue**: IAM roles are being deleted before CloudFormation stacks, causing stack deletion failures.

### Affected Stacks
1. `serverless-saas-pipeline-lab5` - Failed with error:
   ```
   Role arn:aws:iam::265098672980:role/cdk-hnb659fds-cfn-exec-role-265098672980-us-east-1 
   is invalid or cannot be assumed
   (Service: AWSSecurityTokenService; Status Code: 403; Error Code: AccessDenied)
   ```

2. `serverless-saas-pipeline-lab6` - Never deleted (same root cause)

### Root Cause

The CDK execution role (`cdk-hnb659fds-cfn-exec-role-*`) is required by CloudFormation to delete CDK-created stacks. When this role is deleted before the stack, CloudFormation cannot assume the role to perform the deletion, resulting in a failed deletion.

**Current Deletion Order** (INCORRECT):
1. CloudWatch Log Groups
2. S3 Buckets
3. CloudFormation Stacks
4. IAM Roles ← **PROBLEM: Deleted too early**

**Correct Deletion Order** (REQUIRED):
1. CloudWatch Log Groups
2. CloudFormation Stacks ← **Must delete BEFORE IAM roles**
3. S3 Buckets (after CloudFront is deleted)
4. IAM Roles ← **Must be LAST**

## Solution

### Principle: IAM Roles Must Be Deleted LAST

**Rule**: IAM roles should ALWAYS be deleted as the FINAL step in cleanup scripts, after ALL CloudFormation stacks have been deleted.

### Why This Matters

1. **CloudFormation Dependency**: CloudFormation stacks may require IAM roles to perform deletion operations
2. **CDK Stacks**: CDK-created stacks specifically require the CDK execution role to be present during deletion
3. **Service Roles**: Lambda functions, ECS tasks, and other services may have roles that are referenced by CloudFormation

### Implementation Strategy

For each lab cleanup script:

1. **Identify all deletion steps**
2. **Move IAM role deletion to the LAST step**
3. **Ensure all CloudFormation stacks are deleted BEFORE IAM roles**
4. **Add explicit wait for stack deletion completion**

## Labs Requiring Updates

### Lab5 (`workshop/Lab5/scripts/cleanup.sh`)

**Current Issue**: No explicit IAM role deletion step, but CDK roles are being deleted by CDKToolkit stack deletion (Step 8) BEFORE pipeline stack deletion (Step 7).

**Fix Required**:
1. Move CDKToolkit stack deletion to AFTER pipeline stack deletion
2. Add explicit IAM role cleanup as the FINAL step
3. Ensure `delete_stack_with_cdk_role()` function waits for complete deletion before cleaning up temporary roles

**Current Order**:
- Step 7: Delete pipeline stack (uses `delete_stack_with_cdk_role`)
- Step 8: Delete CDKToolkit stack ← **PROBLEM: Deletes CDK roles too early**
- Step 9: Clean up SAM artifacts
- Step 10: Clean up CDK assets bucket

**Correct Order**:
- Step 7: Delete pipeline stack (uses `delete_stack_with_cdk_role`)
- Step 8: Clean up SAM artifacts
- Step 9: Clean up CDK assets bucket
- Step 10: Delete CDKToolkit stack
- Step 11: Delete IAM roles (NEW - FINAL STEP)

### Lab6 (`workshop/Lab6/scripts/cleanup.sh`)

**Current Issue**: Same as Lab5 - no explicit IAM role deletion step, CDK roles deleted too early.

**Fix Required**: Same as Lab5

### Lab7 (`workshop/Lab7/scripts/cleanup.sh`)

**Current Status**: ✅ CORRECT - IAM roles are deleted in Step 10 (LAST step)

**Current Order**:
- Step 1-9: Various cleanup operations including stack deletions
- Step 10: Delete IAM Roles ← **CORRECT: Last step**

### Other Labs (Lab1-Lab4)

**Status**: Need verification - check if IAM role deletion (if present) occurs AFTER all stack deletions

## Testing Strategy

### Verification Steps

For each lab:

1. **Deploy the lab**
2. **Run cleanup script**
3. **Verify deletion order**:
   ```bash
   # Check that stacks are deleted first
   aws cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS DELETE_COMPLETE
   
   # Check that IAM roles still exist during stack deletion
   aws iam list-roles --query 'Roles[?contains(RoleName, `lab`)].RoleName'
   
   # After all stacks are deleted, verify IAM roles are then deleted
   aws iam list-roles --query 'Roles[?contains(RoleName, `lab`)].RoleName'
   ```

4. **Verify no deletion failures**:
   ```bash
   aws cloudformation describe-stacks --stack-name <stack-name> --query 'Stacks[0].StackStatus'
   ```

### Expected Behavior

- All CloudFormation stacks should delete successfully
- No "Role is invalid or cannot be assumed" errors
- IAM roles should be deleted only after all stacks are gone
- No orphaned resources remaining

## Implementation Checklist

- [ ] Update Lab5 cleanup script
  - [ ] Reorder steps: Move CDKToolkit deletion after pipeline deletion
  - [ ] Add explicit IAM role cleanup as final step
  - [ ] Test with full deployment and cleanup cycle

- [ ] Update Lab6 cleanup script
  - [ ] Apply same fixes as Lab5
  - [ ] Test with full deployment and cleanup cycle

- [ ] Verify Lab1-Lab4 cleanup scripts
  - [ ] Check IAM role deletion order
  - [ ] Fix if necessary

- [ ] Verify Lab7 cleanup script
  - [ ] Confirm IAM roles are deleted last (already correct)

- [ ] Update global cleanup script (`cleanup-all-labs.sh`)
  - [ ] Ensure IAM role cleanup happens AFTER all lab cleanups
  - [ ] Add explicit IAM role deletion step if missing

- [ ] Update documentation
  - [ ] Add IAM role deletion order to cleanup best practices
  - [ ] Update DEPLOYMENT_CLEANUP_MANUAL.md
  - [ ] Update CLEANUP_ISOLATION.md

## Related Documentation

- `workshop/extra-info/LAB5_PIPELINE_STACK_DELETION_ISSUE.md` - Original CDK role issue
- `workshop/extra-info/CLOUDFRONT_SECURITY_FIX.md` - Secure deletion order for CloudFront
- `workshop/extra-info/DEPLOYMENT_CLEANUP_MANUAL.md` - Deployment and cleanup manual

## References

- AWS CloudFormation Service Role: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html
- CDK Bootstrap Resources: https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html
