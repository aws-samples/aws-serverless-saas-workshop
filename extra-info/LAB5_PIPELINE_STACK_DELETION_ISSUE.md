# Lab5 Pipeline Stack Deletion Issue

## Issue Summary

**Date Discovered**: January 27, 2026  
**Severity**: High  
**Status**: Documented with Workaround  
**Affected Component**: `serverless-saas-pipeline-lab5` CloudFormation stack

## Problem Description

When attempting to delete the `serverless-saas-pipeline-lab5` stack using the global cleanup script (`cleanup-all-labs.sh`), the deletion fails with the following error:

```
Service: AmazonCloudFormation, Status Code: 400, Request ID: <request-id>
An error occurred (ValidationError) when calling the DeleteStack operation: 
Role arn:aws:iam::<account-id>:role/cdk-hnb659fds-cfn-exec-role-<account-id>-us-east-1 is invalid or cannot be assumed
```

### Root Cause

The Lab5 pipeline stack was created using AWS CDK, which automatically creates an IAM execution role (`cdk-hnb659fds-cfn-exec-role-<account-id>-<region>`) for CloudFormation to use during stack operations. When this CDK execution role is deleted (either manually or through account cleanup), CloudFormation can no longer delete the stack because it requires the same role that was used to create it.

### Why This Happens

1. **CDK Stack Creation**: When Lab5 is deployed with CDK, it creates:
   - The pipeline stack (`serverless-saas-pipeline-lab5`)
   - A CDK execution role (`cdk-hnb659fds-cfn-exec-role-<account-id>-<region>`)
   - CDK bootstrap resources

2. **Role Deletion**: If the CDK execution role is deleted (e.g., through manual cleanup or account-wide IAM role cleanup), the role no longer exists

3. **Stack Deletion Failure**: When attempting to delete the stack, CloudFormation tries to assume the CDK execution role but fails because it no longer exists

### Impact

- The `cleanup-all-labs.sh` script hangs indefinitely waiting for stack deletion that never completes
- The stack remains in `CREATE_COMPLETE` or `UPDATE_COMPLETE` state and cannot be deleted
- Manual intervention is required to delete the stack
- This blocks complete cleanup of Lab5 resources

## Workaround

The Lab5 cleanup script (`workshop/Lab5/scripts/cleanup.sh`) includes logic to handle this scenario (lines 240-300):

```bash
delete_stack_with_cdk_role() {
    local stack=$1
    local role_created=false
    
    # Try to delete the stack normally first
    local delete_output=$(aws cloudformation delete-stack --stack-name $stack --region "$AWS_REGION" 2>&1)
    local delete_status=$?
    
    # Check if deletion failed due to missing CDK role
    if [[ $delete_status -ne 0 ]] && echo "$delete_output" | grep -q "is invalid or cannot be assumed"; then
        # Create temporary CDK execution role
        # Attach AdministratorAccess policy
        # Retry stack deletion
        # Wait for deletion to complete
        # Clean up temporary role
    fi
}
```

### Manual Workaround Steps

If the automated workaround doesn't work, follow these steps:

1. **Create Temporary CDK Execution Role**:
   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile serverless-saas-demo)
   ROLE_NAME="cdk-hnb659fds-cfn-exec-role-${ACCOUNT_ID}-us-east-1"
   
   aws iam create-role \
     --role-name "$ROLE_NAME" \
     --assume-role-policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Principal": {"Service": "cloudformation.amazonaws.com"},
         "Action": "sts:AssumeRole"
       }]
     }' \
     --profile serverless-saas-demo
   ```

2. **Attach Administrator Access Policy**:
   ```bash
   aws iam attach-role-policy \
     --role-name "$ROLE_NAME" \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
     --profile serverless-saas-demo
   ```

3. **Wait for Role Propagation** (3-5 seconds):
   ```bash
   sleep 5
   ```

4. **Delete the Stack**:
   ```bash
   aws cloudformation delete-stack \
     --stack-name serverless-saas-pipeline-lab5 \
     --profile serverless-saas-demo
   ```

5. **Wait for Stack Deletion**:
   ```bash
   aws cloudformation wait stack-delete-complete \
     --stack-name serverless-saas-pipeline-lab5 \
     --profile serverless-saas-demo
   ```

6. **Clean Up Temporary Role**:
   ```bash
   aws iam detach-role-policy \
     --role-name "$ROLE_NAME" \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
     --profile serverless-saas-demo
   
   aws iam delete-role \
     --role-name "$ROLE_NAME" \
     --profile serverless-saas-demo
   ```

## Investigation Needed

### Why Didn't the Automated Workaround Work?

The Lab5 cleanup script has logic to handle missing CDK roles (lines 240-300), but it didn't work when called from the global cleanup script. Possible reasons:

1. **Script Context**: The function may not be called correctly when invoked from the global cleanup script
2. **Error Detection**: The error message pattern matching may not work in all scenarios
3. **Timing Issues**: The role creation and propagation may need more time
4. **Permission Issues**: The script may not have sufficient permissions to create IAM roles

### Next Steps for Investigation

1. Add debug logging to the `delete_stack_with_cdk_role()` function to trace execution
2. Test the function in isolation to verify it works correctly
3. Verify the error message pattern matching is correct
4. Check if the function is being called at all when invoked from global cleanup script
5. Consider adding retry logic with exponential backoff for role propagation

## Prevention

To prevent this issue in the future:

1. **Don't Delete CDK Bootstrap Resources**: Avoid deleting CDK execution roles manually
2. **Use CDK Cleanup Commands**: Use `cdk destroy` to properly clean up CDK stacks
3. **Document CDK Dependencies**: Clearly document which stacks are CDK-based
4. **Improve Error Handling**: Enhance the cleanup script to better handle missing CDK roles

## Related Files

- `workshop/Lab5/scripts/cleanup.sh` (lines 240-300) - Contains CDK role handling logic
- `workshop/scripts/cleanup-all-labs.sh` - Global cleanup script that calls Lab5 cleanup
- `.kiro/specs/lab-cleanup-isolation-all-labs/tasks.md` - Task 13, Step 1 documentation

## References

- [AWS CDK Bootstrap](https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping.html)
- [CloudFormation Execution Roles](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html)
- [CDK Destroy Command](https://docs.aws.amazon.com/cdk/v2/guide/cli.html#cli-destroy)
