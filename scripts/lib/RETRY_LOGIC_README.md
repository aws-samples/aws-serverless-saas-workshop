# Retry Logic Module

## Overview

The retry logic module provides robust error handling for AWS CLI commands with automatic retry on transient failures. It implements exponential backoff to avoid overwhelming AWS services during temporary issues like throttling or network errors.

## Features

- **Automatic Error Detection**: Identifies retryable errors (throttling, network issues, service unavailability)
- **Exponential Backoff**: Implements 2s, 4s, 8s backoff pattern for retries
- **Comprehensive Logging**: Logs each retry attempt with reason and backoff duration
- **Max Retry Enforcement**: Limits retries to 3 attempts by default
- **Non-Retryable Error Handling**: Fails immediately on permanent errors (validation, access denied, etc.)

## Usage

### Basic Usage

```bash
# Source the module
source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"

# Execute a command with automatic retry
if execute_with_retry aws cloudformation describe-stacks --stack-name my-stack; then
    echo "Command succeeded"
else
    echo "Command failed after retries: $LAST_ERROR_OUTPUT"
fi
```

### AWS CLI Convenience Wrapper

```bash
# Use the AWS-specific wrapper (automatically adds 'aws' prefix)
if execute_aws_command_with_retry cloudformation describe-stacks --stack-name my-stack; then
    echo "AWS command succeeded"
else
    echo "AWS command failed: $LAST_ERROR_OUTPUT"
fi
```

### Check if Error is Retryable

```bash
# Check if an error message indicates a retryable failure
if is_retryable_error "$error_message"; then
    echo "This error can be retried"
else
    echo "This is a permanent failure"
fi
```

### Calculate Backoff Duration

```bash
# Calculate exponential backoff for a given attempt
backoff=$(calculate_backoff 2)  # Returns 4 (seconds)
echo "Waiting $backoff seconds before retry"
```

## Retryable Error Types

The module automatically detects and retries these error types:

### Throttling Errors
- `Throttling`
- `TooManyRequests`
- `Rate exceeded`
- `RequestLimitExceeded`

### Network Errors
- `Connection timeout`
- `Could not connect`
- `Network error`
- `Connection reset`
- `Connection refused`
- `timed out`

### Service Unavailability
- `ServiceUnavailable`
- `Service temporarily unavailable`
- `InternalError`
- `Internal error`

## Non-Retryable Errors

These errors cause immediate failure without retry:

- `ValidationError` - Invalid parameters or missing resources
- `AccessDenied` - Insufficient permissions
- `InvalidParameterValue` - Invalid parameter values
- `ResourceInUseException` - Resource conflicts

## Configuration

### Global Variables

```bash
# Maximum number of retry attempts (default: 3)
RETRY_MAX_ATTEMPTS=3

# Base backoff duration in seconds (default: 2)
RETRY_BASE_BACKOFF=2
```

### Exponential Backoff Formula

```
backoff = base_backoff * (2 ^ (attempt - 1))
```

For `base_backoff=2` seconds:
- Attempt 1: 2 seconds
- Attempt 2: 4 seconds
- Attempt 3: 8 seconds

## Output Variables

After executing a command with retry, these global variables are set:

- `LAST_COMMAND`: The command that was executed
- `LAST_ERROR_OUTPUT`: Error output from the last failed attempt
- `LAST_ERROR_CODE`: Exit code from the last failed attempt

## Examples

### Example 1: Delete Stack with Retry

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"

# Delete a CloudFormation stack with automatic retry on throttling
if execute_aws_command_with_retry cloudformation delete-stack \
    --stack-name "my-stack" \
    --region "us-east-1"; then
    echo "Stack deletion initiated"
else
    echo "Failed to delete stack: $LAST_ERROR_OUTPUT"
    exit 1
fi
```

### Example 2: Custom Retry Logic

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"

# Set custom retry parameters
RETRY_MAX_ATTEMPTS=5
RETRY_BASE_BACKOFF=1

# Execute with custom retry settings
execute_with_retry aws s3 ls s3://my-bucket/

# Reset to defaults
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_BACKOFF=2
```

### Example 3: Manual Retry Loop

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    
    # Execute command
    output=$(aws cloudformation describe-stacks --stack-name my-stack 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "Success!"
        break
    fi
    
    # Check if retryable
    if [ $attempt -lt $max_attempts ] && is_retryable_error "$output"; then
        backoff=$(calculate_backoff $attempt)
        log_retry_attempt $attempt $max_attempts $backoff "$output"
        sleep $backoff
    else
        echo "Failed: $output"
        exit 1
    fi
done
```

## Testing

The module includes comprehensive unit tests:

```bash
# Run unit tests
./workshop/scripts/lib/retry-logic.test.sh
```

Test coverage includes:
- Error detection (throttling, network, service unavailability)
- Non-retryable error handling
- Exponential backoff calculation
- Retry attempt logging
- Max retry enforcement
- Integration tests with timing verification

## Integration with Other Modules

The retry logic module integrates seamlessly with other cleanup modules:

```bash
# Source both modules
source "$(dirname "${BASH_SOURCE[0]}")/lib/retry-logic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/stack-deletion.sh"

# Use retry logic in stack deletion
if execute_with_retry aws cloudformation delete-stack --stack-name my-stack; then
    wait_for_stack_deletion "my-stack" 30 "$PROFILE_ARG"
fi
```

## Best Practices

1. **Always check return codes**: Don't assume commands succeed
2. **Use appropriate retry limits**: 3 attempts is usually sufficient
3. **Log retry attempts**: Helps with debugging and monitoring
4. **Reset retry state**: Call `reset_retry_state()` between independent operations
5. **Handle non-retryable errors**: Don't retry validation or permission errors
6. **Use exponential backoff**: Prevents overwhelming AWS services during issues

## Troubleshooting

### Command Always Fails After Retries

Check if the error is actually retryable:
```bash
if is_retryable_error "$error_message"; then
    echo "Error is retryable"
else
    echo "Error is permanent: $error_message"
fi
```

### Retries Take Too Long

Reduce the base backoff or max attempts:
```bash
RETRY_BASE_BACKOFF=1  # Faster retries
RETRY_MAX_ATTEMPTS=2  # Fewer attempts
```

### Need More Retries

Increase the max attempts:
```bash
RETRY_MAX_ATTEMPTS=5  # More attempts for flaky operations
```

## Requirements

- Bash 4.0 or higher
- AWS CLI installed and configured
- Proper IAM permissions for AWS operations

## Related Modules

- `stack-deletion.sh` - Stack deletion with verification
- `error-logging.sh` - Enhanced error logging (integrated in stack-deletion.sh)

## Version History

- **v1.0.0** (2025-01-19): Initial implementation
  - Retryable error detection
  - Exponential backoff (2s, 4s, 8s)
  - Max retry limit (3 attempts)
  - Comprehensive logging
  - Unit test coverage

## License

This module is part of the AWS Serverless SaaS Workshop and follows the same license.
