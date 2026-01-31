# End-to-End AWS Testing System

Comprehensive testing framework for validating deployment, isolation, and cleanup operations across all 7 labs of the Serverless SaaS Workshop.

## Overview

This testing system executes a complete 10-step workflow to validate:

1. **Initial Cleanup** - Ensures clean starting state
2. **Full Deployment** - Deploys all 7 labs in parallel
3-9. **Lab Isolation Tests** - Verifies each lab can be deleted independently without affecting others
10. **Final Cleanup** - Removes all remaining resources

The system captures comprehensive metrics including:
- Resource state changes (CloudFormation stacks, S3 buckets, CloudWatch logs, Cognito pools, DynamoDB tables, IAM roles)
- Timing metrics for all operations
- AWS API call statistics
- Lab isolation verification results
- Detailed logs for all operations

## Prerequisites

### Required Software

- **Python 3.14+** - The testing framework is written for Python 3.14
- **AWS CLI** - Configured with appropriate credentials
- **AWS SAM CLI** - For deploying serverless applications
- **Docker** - Required by SAM for building Lambda functions
- **Bash** - For executing deployment and cleanup scripts

### AWS Account Requirements

- Valid AWS account with appropriate permissions
- AWS CLI profile configured with credentials
- Sufficient service quotas for deploying all 7 labs simultaneously

### Python Dependencies

Install required Python packages:

```bash
cd workshop/tests
pip install -r requirements.txt
```

## Installation

1. Clone the repository and navigate to the tests directory:

```bash
cd workshop/tests
```

2. Install Python dependencies:

```bash
pip install -r requirements.txt
```

3. Verify AWS CLI configuration:

```bash
aws sts get-caller-identity --profile <your-profile>
```

## Usage

### Quick Start

Run the test suite with default settings:

```bash
./run_end_to_end_aws_test.sh --profile my-profile --email admin@example.com
```

### Python Script

Run the Python script directly:

```bash
python3 test_end_to_end_aws_testing.py --profile my-profile --email admin@example.com
```

### Command-Line Options

#### Required Arguments

- `--profile <profile>` - AWS CLI profile name (REQUIRED)
- `--email <email>` - Email address for admin and tenant accounts (REQUIRED)

#### Optional Arguments

- `--tenant-email <email>` - Tenant admin email for Lab3-4 auto-creation
- `--region <region>` - AWS region (default: us-east-1)
- `--sequential` - Disable parallel deployment mode (parallel is default)
- `--timeout <hours>` - Maximum test execution time in hours (default: 6)
- `--log-dir <path>` - Directory for log files
- `--report-dir <path>` - Directory for test reports
- `--verbose` - Enable verbose logging

### Examples

#### Basic Usage

```bash
# Run with default settings
./run_end_to_end_aws_test.sh --profile my-profile --email admin@example.com
```

#### With Tenant Auto-Creation

```bash
# Enable automatic tenant creation for Lab3-4
./run_end_to_end_aws_test.sh \
  --profile my-profile \
  --email admin@example.com \
  --tenant-email tenant@example.com
```

#### Custom Region and Sequential Mode

```bash
# Deploy to us-west-2 in sequential mode
./run_end_to_end_aws_test.sh \
  --profile my-profile \
  --email admin@example.com \
  --region us-west-2 \
  --sequential
```

#### Extended Timeout with Verbose Logging

```bash
# Run with 8-hour timeout and verbose logging
./run_end_to_end_aws_test.sh \
  --profile my-profile \
  --email admin@example.com \
  --timeout 8 \
  --verbose
```

## Test Workflow

### Step 1: Initial Cleanup

Executes `workshop/scripts/cleanup-all-labs.sh` to ensure a clean starting state.

**Purpose**: Remove any existing resources from previous test runs.

**Verification**: Captures resource snapshot before and after cleanup.

### Step 2: Full Deployment

Executes `workshop/scripts/deploy-all-labs.sh` with parallel mode enabled.

**Purpose**: Deploy all 7 labs simultaneously to verify parallel deployment works correctly.

**Verification**: 
- All CloudFormation stacks reach CREATE_COMPLETE status
- All expected resources are created
- No deployment conflicts occur

### Steps 3-9: Lab Isolation Tests

For each lab (Lab1 through Lab7):

1. Execute lab-specific cleanup script
2. Capture resource state before and after deletion
3. Verify isolation:
   - Deleted lab's resources are removed
   - Other labs remain unaffected
   - No orphaned resources are left behind

**Lab Stack Architecture**:

- **Lab1**: 1 stack (`serverless-saas-lab1`)
- **Lab2**: 1 stack (`serverless-saas-lab2`)
- **Lab3**: 2 stacks (`serverless-saas-shared-lab3`, `serverless-saas-tenant-lab3`)
- **Lab4**: 2 stacks (`serverless-saas-shared-lab4`, `serverless-saas-tenant-lab4`)
- **Lab5**: 2 base stacks + dynamic tenant stacks (`serverless-saas-shared-lab5`, `serverless-saas-pipeline-lab5`, `stack-<tenantId>-lab5`)
- **Lab6**: 3+ stacks (`serverless-saas-shared-lab6`, `serverless-saas-pipeline-lab6`, `stack-lab6-pooled`, dynamic tenant stacks `stack-.*-lab6`)
- **Lab7**: 2 stacks (`serverless-saas-lab7`, `stack-pooled-lab7`)

**Important Notes**:
- Lab5 creates tenant stacks dynamically with pattern `stack-<tenantId>-lab5` via pipeline Lambda function
- Lab6 creates tenant stacks dynamically with pattern `stack-.*-lab6` (e.g., `stack-lab6-pooled`, `stack-basic-lab6`)
- Lab7 creates a single tenant stack `stack-pooled-lab7`
- Lab5 and Lab6 pipeline stacks are DISTINCT and independent

### Step 10: Final Cleanup

Executes `workshop/scripts/cleanup-all-labs.sh` to remove all remaining resources.

**Purpose**: Verify complete cleanup of all resources.

**Verification**: Final state matches initial state (no resources remaining).

## Output Files

### Test Reports

The test suite generates comprehensive reports in two formats:

#### Markdown Report

**Location**: `workshop/tests/end_to_end_test_report/test_report_<timestamp>.md`

**Contents**:
- Executive summary with overall status
- Configuration details
- Timing metrics with slowest operations
- Step-by-step results with logs
- Resource state changes
- API call statistics by service
- Lab isolation verification results
- Failure highlighting (if any)

#### JSON Report

**Location**: `workshop/tests/end_to_end_test_report/test_report_<timestamp>.json`

**Contents**: Machine-parseable version of all test data for automated analysis.

### Log Files

**Location**: `workshop/tests/end_to_end_test_report/logs/`

**Files**:
- `initial_cleanup_<timestamp>.log` - Step 1 logs
- `full_deployment_<timestamp>.log` - Step 2 logs
- `lab1_cleanup_<timestamp>.log` through `lab7_cleanup_<timestamp>.log` - Steps 3-9 logs
- `final_cleanup_<timestamp>.log` - Step 10 logs

Each log file contains:
- Script execution output (stdout and stderr)
- Exit codes
- Timestamps
- Environment context

### Resource Snapshots

**Location**: `workshop/tests/end_to_end_test_report/snapshots/`

**Files**: JSON snapshots of AWS resources captured before and after each operation.

## Architecture

### Components

#### 1. TestOrchestrator

Coordinates the entire test workflow and manages all components.

**Responsibilities**:
- Execute 10-step test workflow
- Coordinate component interactions
- Handle errors and generate reports
- Enforce timeout limits

#### 2. ResourceTracker

Captures snapshots of AWS resources at specific points in time.

**Tracked Resources**:
- CloudFormation stacks
- S3 buckets
- CloudWatch log groups
- Cognito user pools
- DynamoDB tables
- IAM roles

#### 3. StateComparator

Compares resource snapshots to identify changes.

**Capabilities**:
- Identify created, deleted, and modified resources
- Verify lab isolation
- Detect orphaned resources
- Generate diff reports

#### 4. LogCollector

Manages log file creation and organization.

**Features**:
- Structured log directory organization
- Real-time console output with timestamps
- Script output capture (stdout/stderr)
- Environment context in logs

#### 5. ScriptExecutor

Executes deployment and cleanup scripts safely.

**Features**:
- Direct script execution (./script.sh format)
- Execute permission verification
- Shebang line validation
- Exit code and error capture

#### 6. APIMonitor

Tracks AWS API calls during test execution.

**Capabilities**:
- Automatic API call tracking via boto3 events
- Success rate calculation per service
- Retry tracking
- Error capture with codes and messages

#### 7. TimingRecorder

Records timing metrics for all operations.

**Metrics**:
- Total test duration
- Per-step duration
- Per-operation duration
- Slowest/fastest operations

#### 8. TestReportGenerator

Generates comprehensive test reports.

**Formats**:
- Markdown (human-readable)
- JSON (machine-parseable)

### Data Flow

```
TestOrchestrator
    ├── ResourceTracker → Captures snapshots
    ├── StateComparator → Compares snapshots
    ├── LogCollector → Manages logs
    ├── ScriptExecutor → Runs scripts
    ├── APIMonitor → Tracks API calls
    ├── TimingRecorder → Records timing
    └── TestReportGenerator → Generates reports
```

## Configuration

### TestConfig

The `TestConfig` class manages all test configuration:

```python
from end_to_end.config import TestConfig

config = TestConfig(
    aws_profile="my-profile",
    aws_region="us-east-1",
    email="admin@example.com",
    tenant_email="tenant@example.com",  # Optional
    parallel_mode=True,
    timeout_hours=6,
    log_directory=Path("logs"),
    report_directory=Path("reports")
)
```

### Environment Variables

The test suite respects standard AWS environment variables:

- `AWS_PROFILE` - AWS CLI profile (overridden by --profile)
- `AWS_REGION` - AWS region (overridden by --region)
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key

## Troubleshooting

### Common Issues

#### 1. Script Execution Errors

**Problem**: Scripts fail with "Permission denied" error.

**Solution**: Ensure scripts are executable:

```bash
chmod +x workshop/scripts/*.sh
chmod +x workshop/Lab*/scripts/*.sh
```

#### 2. AWS Credential Errors

**Problem**: "Unable to locate credentials" error.

**Solution**: Verify AWS CLI configuration:

```bash
aws configure list --profile <your-profile>
aws sts get-caller-identity --profile <your-profile>
```

#### 3. Timeout Errors

**Problem**: Test suite times out before completion.

**Solution**: Increase timeout:

```bash
./run_end_to_end_aws_test.sh --profile my-profile --email admin@example.com --timeout 8
```

#### 4. Deployment Failures

**Problem**: CloudFormation stacks fail to deploy.

**Solution**: Check deployment logs in `workshop/tests/end_to_end_test_report/logs/` for specific error messages.

#### 5. Isolation Test Failures

**Problem**: Lab isolation tests fail.

**Solution**: Review the test report to identify which resources were not properly isolated. Check the state diff section for details.

### Debug Mode

Enable verbose logging for detailed debug information:

```bash
./run_end_to_end_aws_test.sh --profile my-profile --email admin@example.com --verbose
```

### Partial Reports

If the test suite fails, a partial report is generated with all data collected up to the failure point. This helps diagnose issues without losing test progress.

## Best Practices

### 1. Clean State

Always start with a clean AWS account state. Run initial cleanup manually if needed:

```bash
cd workshop/scripts
echo "yes" | ./cleanup-all-labs.sh --profile <your-profile>
```

### 2. Sufficient Quotas

Ensure your AWS account has sufficient service quotas for deploying all 7 labs simultaneously:

- CloudFormation stacks: 200+ (default is 2000)
- S3 buckets: 100+ (default is 100)
- Lambda functions: 1000+ (default is 1000)
- DynamoDB tables: 256+ (default is 2500)

### 3. Timeout Configuration

Adjust timeout based on your AWS region and account:

- **Fast regions** (us-east-1): 6 hours (default)
- **Slower regions**: 8-10 hours
- **First-time deployment**: 8-10 hours (resource provisioning takes longer)

### 4. Parallel vs Sequential

- **Parallel mode** (default): Faster but requires more AWS API capacity
- **Sequential mode**: Slower but more reliable for accounts with API throttling

### 5. Log Retention

Test logs and reports can consume significant disk space. Clean up old test runs periodically:

```bash
rm -rf workshop/tests/end_to_end_test_report/old_runs/
```

## Contributing

When contributing to the end-to-end testing system:

1. Follow Python 3.14 syntax and features
2. Add comprehensive docstrings to all classes and methods
3. Include type hints for all function parameters and return values
4. Write unit tests for new components
5. Update this README with any new features or changes

## License

This testing framework is part of the AWS Serverless SaaS Workshop and follows the same license terms.

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review test reports and logs for specific error messages
3. Consult the workshop documentation at `workshop/README.md`
4. Open an issue in the repository with:
   - Test configuration used
   - Error messages from logs
   - Partial test report (if available)
