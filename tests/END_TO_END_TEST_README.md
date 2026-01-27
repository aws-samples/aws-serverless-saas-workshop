# End-to-End Cleanup Isolation Test

## Overview

This comprehensive test validates the cleanup isolation workflow across all labs (Lab1-Lab7). It ensures that each lab's cleanup script only deletes its own resources and does not affect other labs.

**Test File**: `test_end_to_end_cleanup_isolation.py`

**Validates**: Requirements 8.1-8.15 from the lab-cleanup-isolation-all-labs spec

## Test Workflow

The test executes an 11-step workflow:

1. **Step 1**: Run cleanup-all-labs script to ensure clean state
2. **Step 2**: Run deploy-all-labs script to deploy all labs (Lab1-Lab7)
3. **Step 3**: Run Lab1 cleanup, verify Lab2-Lab7 resources remain intact
4. **Step 4**: Run Lab2 cleanup, verify Lab3-Lab7 resources remain intact
5. **Step 5**: Run Lab3 cleanup, verify Lab4-Lab7 resources remain intact
6. **Step 6**: Run Lab4 cleanup, verify Lab5-Lab7 resources remain intact
7. **Step 7**: Run Lab5 cleanup, verify Lab6-Lab7 resources remain intact
   - **CRITICAL**: Verifies `stack-lab6-pooled` and `stack-pooled-lab7` are NOT deleted
8. **Step 8**: Run Lab6 cleanup, verify Lab7 resources remain intact
9. **Step 9**: Run Lab7 cleanup, verify all labs are cleaned up
10. **Step 10**: Run deploy-all-labs script again to redeploy all labs
11. **Step 11**: Run cleanup-all-labs script and verify complete cleanup

## Test Modes

### Dry-Run Mode (Default)

Simulates the workflow without actual AWS operations. Fast and safe for development.

```bash
# Run the complete test
pytest test_end_to_end_cleanup_isolation.py -v

# Run directly with Python
python test_end_to_end_cleanup_isolation.py
```

**Expected Behavior in Dry-Run Mode**:
- Steps 1, 3-9, 11: PASS (cleanup steps work with empty resources)
- Steps 2, 10: FAIL (deployment steps fail because no resources are created)
- This is expected - dry-run mode doesn't create actual AWS resources

### Real AWS Mode

Executes actual deployment and cleanup operations against a real AWS account.

**⚠️ WARNING**: This mode takes 60-90 minutes and creates/deletes real AWS resources!

**Prerequisites**:
1. AWS CLI configured with valid credentials
2. AWS profile with permissions to create/delete resources
3. Email address for Cognito user pools (Labs 2-4)
4. Sufficient time (60-90 minutes for full test)

```bash
# Run with pytest
pytest test_end_to_end_cleanup_isolation.py -v \
    --real-aws \
    --aws-profile=<your-profile-name> \
    --email=<your-email@example.com>

# Run directly with Python
python test_end_to_end_cleanup_isolation.py \
    --real-aws \
    --aws-profile=<your-profile-name> \
    --email=<your-email@example.com>
```

**Example**:
```bash
pytest test_end_to_end_cleanup_isolation.py -v \
    --real-aws \
    --aws-profile=serverless-saas-demo \
    --email=admin@example.com
```

## Running Individual Steps

You can run individual test steps for faster validation:

```bash
# Test Step 1: Cleanup all labs
pytest test_end_to_end_cleanup_isolation.py::test_step_1_cleanup_all_labs -v

# Test Step 2: Deploy all labs
pytest test_end_to_end_cleanup_isolation.py::test_step_2_deploy_all_labs -v

# Test Step 3-9: Cleanup individual labs
pytest test_end_to_end_cleanup_isolation.py::test_step_cleanup_single_lab[5] -v

# Test Step 10: Redeploy all labs
pytest test_end_to_end_cleanup_isolation.py::test_step_10_redeploy_all_labs -v

# Test Step 11: Final cleanup
pytest test_end_to_end_cleanup_isolation.py::test_step_11_cleanup_all_labs_final -v

# Test critical bug fix (Lab5 doesn't delete Lab6/Lab7 resources)
pytest test_end_to_end_cleanup_isolation.py::test_lab5_does_not_delete_lab6_lab7_resources -v
```

## Test Output

### Console Output

The test provides detailed console output for each step:

```
================================================================================
STEP 3: Cleanup Lab1 (Verify Lab2-Lab7 Intact)
================================================================================
[DRY-RUN] Would execute: /path/to/Lab1/scripts/cleanup.sh --stack-name=serverless-saas-lab1

✓ PASS - Step 3: Cleanup Lab1
Duration: 0.10 seconds
Resources before: 15
Resources after: 10
Resources deleted: 5

Warnings:
  - Warning: 2 Lab1 resources still exist after cleanup
```

### Final Report

At the end of the test, a comprehensive report is generated:

```
================================================================================
END-TO-END CLEANUP ISOLATION TEST - FINAL REPORT
================================================================================

Total Steps: 11
Passed: 11
Failed: 0
Total Duration: 4523.45 seconds (75.39 minutes)

--------------------------------------------------------------------------------
Step-by-Step Summary:
--------------------------------------------------------------------------------
✓ Step 1: Cleanup All Labs (Ensure Clean State) (120.50s, 0 resources deleted)
✓ Step 2: Deploy All Labs (1800.25s, 45 resources created)
✓ Step 3: Cleanup Lab1 (180.30s, 5 resources deleted)
...
```

### JSON Report

A detailed JSON report is saved to `workshop/tests/end_to_end_test_report.json`:

```json
{
  "test_name": "End-to-End Cleanup Isolation Test",
  "timestamp": "2025-01-15T10:30:00",
  "dry_run": false,
  "aws_profile": "serverless-saas-demo",
  "total_steps": 11,
  "passed_steps": 11,
  "failed_steps": 0,
  "total_duration_seconds": 4523.45,
  "steps": [
    {
      "step_number": 1,
      "step_name": "Cleanup All Labs (Ensure Clean State)",
      "success": true,
      "duration_seconds": 120.50,
      "resources_before": {...},
      "resources_after": {...},
      "resources_deleted": {...}
    },
    ...
  ]
}
```

## Resource Tracking

The test tracks the following AWS resource types:

- **CloudFormation Stacks**: All stacks with lab identifiers (lab1-lab7)
- **S3 Buckets**: All buckets with lab identifiers
- **CloudWatch Log Groups**: All log groups with lab identifiers
- **Cognito User Pools**: All user pools with lab identifiers (Lab2)

For each step, the test records:
- Resources before the operation
- Resources after the operation
- Resources deleted during the operation

## Critical Validations

### Lab5 Bug Fix Validation

Step 7 includes critical validation for the Lab5 cleanup bug fix:

```python
# Verify Lab5 cleanup does NOT delete Lab6 or Lab7 resources
assert "stack-lab6-pooled" not in deleted_stacks
assert "stack-pooled-lab7" not in deleted_stacks
```

This ensures the bug where Lab5 cleanup was deleting Lab6 and Lab7 tenant stacks is fixed.

### Cross-Lab Deletion Detection

Each cleanup step verifies that no resources from other labs are deleted:

```python
# For each remaining lab
for remaining_lab_id in remaining_labs:
    # Verify resources count hasn't changed
    assert resources_after[remaining_lab_id].count() == resources_before[remaining_lab_id].count()
```

## Troubleshooting

### Test Fails in Dry-Run Mode

**Expected**: Steps 2 and 10 (deployment steps) will fail in dry-run mode because no resources are created. This is normal behavior.

**Solution**: Run in real AWS mode to validate actual deployments.

### Test Fails in Real AWS Mode

**Common Issues**:

1. **AWS Credentials**: Ensure your AWS profile is configured correctly
   ```bash
   aws configure --profile <your-profile-name>
   aws sts get-caller-identity --profile <your-profile-name>
   ```

2. **Permissions**: Ensure your AWS user/role has permissions to:
   - Create/delete CloudFormation stacks
   - Create/delete S3 buckets
   - Create/delete CloudWatch log groups
   - Create/delete Cognito user pools
   - Create/delete Lambda functions
   - Create/delete API Gateways
   - Create/delete DynamoDB tables

3. **Timeout**: If deployment takes longer than expected, increase timeout values in the test

4. **Resource Limits**: Check AWS service quotas for your account

### Test Hangs or Times Out

**Possible Causes**:
- CloudFormation stack creation/deletion is slow
- Network connectivity issues
- AWS API throttling

**Solution**:
- Check CloudFormation console for stack status
- Increase timeout values in test configuration
- Run test during off-peak hours to avoid throttling

## Best Practices

1. **Use Dry-Run Mode First**: Always test in dry-run mode before running against real AWS
2. **Use Test AWS Account**: Run real AWS tests in a dedicated test account, not production
3. **Monitor Costs**: Real AWS tests create resources that may incur costs
4. **Clean Up After Failures**: If test fails, manually verify all resources are cleaned up
5. **Save Reports**: Keep JSON reports for historical analysis and debugging

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: End-to-End Cleanup Isolation Test

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Run End-to-End Test
        run: |
          cd workshop/tests
          pytest test_end_to_end_cleanup_isolation.py -v \
            --real-aws \
            --aws-profile=default \
            --email=${{ secrets.TEST_EMAIL }}
      
      - name: Upload Test Report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-report
          path: workshop/tests/end_to_end_test_report.json
```

## Related Documentation

- **Spec**: `.kiro/specs/lab-cleanup-isolation-all-labs/`
- **Requirements**: `.kiro/specs/lab-cleanup-isolation-all-labs/requirements.md`
- **Design**: `.kiro/specs/lab-cleanup-isolation-all-labs/design.md`
- **Tasks**: `.kiro/specs/lab-cleanup-isolation-all-labs/tasks.md`
- **Deployment Manual**: `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
- **CloudFront Security**: `workshop/CLOUDFRONT_SECURITY_FIX.md`

## Support

For issues or questions:
1. Check the test output and JSON report for detailed error messages
2. Review the spec requirements and design documents
3. Verify AWS credentials and permissions
4. Check CloudFormation console for stack status
5. Review cleanup script logs for detailed error messages
