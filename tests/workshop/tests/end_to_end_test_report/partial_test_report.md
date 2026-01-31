# End-to-End AWS Testing Report

**Generated:** 2026-01-31 17:47:32

## Summary

**Status:** ✅ All 1 test steps completed successfully in 0:05:32.748452

- **Start Time:** 2026-01-31 17:41:59
- **End Time:** 2026-01-31 17:47:32
- **Total Duration:** 0:05:32.748452
- **Total Steps:** 1
- **Successful Steps:** 1
- **Failed Steps:** 0

## Configuration

```yaml
aws_profile: serverless-saas-demo
aws_region: us-east-1
email: lancdieg@amazon.com
tenant_email: None
parallel_mode: True
timeout_hours: 6
log_directory: workshop/tests/end_to_end_test_report/logs
report_directory: workshop/tests/end_to_end_test_report
```

## Timing Metrics

| Operation | Duration | Duration (seconds) |
|-----------|----------|--------------------|
| Step 1: Initial Cleanup | 0:03:32.735475 | 212.74s |

### Slowest Operations

1. **Step 1: Initial Cleanup**: 0:03:32.735475 (212.74s)

## Test Steps

### ✅ Step 1: Initial Cleanup

- **Status:** Success
- **Duration:** 0:03:27.724840
- **Start Time:** 2026-01-31 17:42:02
- **End Time:** 2026-01-31 17:45:30

## Resource State Changes

### Step 1: Initial Cleanup

**Deleted Resources:** 8
- CloudFormation::Stack: serverless-saas-pipeline-lab5
- IAM::Role: serverless-saas-pipeline--deploytenantstackServiceR-v7yXm6mJukks
- IAM::Role: serverless-saas-pipeline--PipelineBuildBuildServerl-Oxkd9iyw08qr
- IAM::Role: serverless-saas-pipeline--PipelineDeployDeployTenan-9g9JeErMwqDC
- IAM::Role: serverless-saas-pipeline--PipelineEventsRole46BEEA7-rFHh0Rp8sMVU
- IAM::Role: serverless-saas-pipeline--PipelineSourceCodeCommitS-5L9mQblslG03
- IAM::Role: serverless-saas-pipeline-lab5-BuildRoleB7C66CB2-YMxK7xwgAFV0
- IAM::Role: serverless-saas-pipeline-lab5-PipelineRoleD68726F7-RiF4W89yfHwS

## API Call Statistics

- **Total API Calls:** 0
- **Successful Calls:** 0
- **Failed Calls:** 0
