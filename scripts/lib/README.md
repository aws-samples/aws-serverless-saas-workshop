# Parameter Parsing Template Library

This directory contains reusable bash function templates for cleanup scripts across all workshop labs.

## Overview

The parameter parsing template provides a consistent, well-tested approach to handling command-line parameters in cleanup scripts, with support for optional stack names and sensible defaults.

## Files

- **parameter-parsing-template.sh** - Main template with reusable functions
- **README.md** - This documentation file

## Features

### Core Functions

1. **parse_cleanup_parameters** - Main parameter parsing function
   - Handles optional `--stack-name` with default values
   - Requires `--profile` parameter
   - Supports optional `--region` (default: us-east-1)
   - Supports `-y/--yes` for non-interactive mode
   - Displays help with `-h/--help`
   - Validates all inputs and provides clear error messages

2. **validate_stack_name** - Stack name validation
   - Checks for empty values
   - Checks for whitespace-only values
   - Returns appropriate error codes

3. **assign_default_stack_name** - Default value assignment
   - Assigns default when stack name is not provided
   - Logs informative message when default is used
   - Preserves explicit values

4. **show_cleanup_help** - Help text display
   - Shows usage information
   - Displays default stack name
   - Includes security notes
   - Provides examples

5. **display_cleanup_configuration** - Configuration display
   - Shows current cleanup configuration
   - Displays stack name, profile, and region
   - Useful for user confirmation

## Usage

### Basic Integration

```bash
#!/bin/bash

# Source the parameter parsing template
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/parameter-parsing-template.sh"

# Set lab-specific defaults
DEFAULT_STACK_NAME="serverless-saas-lab1"
LAB_NUMBER="1"

# Parse parameters
parse_cleanup_parameters "$@"

# Display configuration
display_cleanup_configuration

# Your cleanup logic here...
```

### Prerequisites

Before calling `parse_cleanup_parameters`, you must set:

- `DEFAULT_STACK_NAME` - The default stack name for your lab
- `LAB_NUMBER` - The lab number (optional, for help text)

### Available Variables After Parsing

After calling `parse_cleanup_parameters`, these variables are available:

- `STACK_NAME` - Stack name (from parameter or default)
- `AWS_PROFILE` - AWS CLI profile name (required)
- `AWS_REGION` - AWS region (default: us-east-1)
- `SKIP_CONFIRMATION` - Whether to skip confirmation (0 or 1)
- `PROFILE_ARG` - Formatted profile argument for AWS CLI commands

### Command-Line Examples

```bash
# Use default stack name
./cleanup.sh --profile my-profile

# Use explicit stack name
./cleanup.sh --stack-name custom-stack --profile my-profile

# Non-interactive mode
echo "yes" | ./cleanup.sh --profile my-profile

# Custom region
./cleanup.sh --profile my-profile --region us-west-2

# All options together
./cleanup.sh --stack-name my-stack --profile my-profile --region us-west-2 -y

# Display help
./cleanup.sh --help
```

## Validation Logic

### Stack Name Validation

The template validates stack names according to these rules:

1. **Non-empty**: Stack name cannot be empty string
2. **No whitespace-only**: Stack name cannot contain only whitespace
3. **Default assignment**: If not provided, uses `DEFAULT_STACK_NAME`
4. **Logging**: Logs when default value is used

### Parameter Validation

- `--profile` is **REQUIRED** - script exits with error if not provided
- `--stack-name` is **OPTIONAL** - uses default if not provided
- `--region` is **OPTIONAL** - defaults to us-east-1
- Unknown parameters trigger error and display help text

## Error Handling

The template provides clear error messages for common issues:

```bash
# Missing required parameter
Error: --profile parameter is required

# Empty stack name
Error: Stack name cannot be empty

# Unknown parameter
Error: Unknown option: --unknown-param

# Missing parameter value
Error: --stack-name requires a value
```

## Testing

Unit tests are provided in `workshop/tests/unit/test-parameter-parsing.bats`.

### Running Tests

```bash
# Install BATS if not already installed
# On macOS: brew install bats-core
# On Linux: apt-get install bats

# Run tests
bats workshop/tests/unit/test-parameter-parsing.bats
```

### Test Coverage

The test suite covers:

- Stack name validation (empty, whitespace, valid values)
- Default stack name assignment
- Parameter parsing (all options)
- AWS profile requirement
- AWS region handling
- Confirmation flag handling
- Help text display
- Error handling (unknown parameters, missing values)
- Complex scenarios (multiple parameters, different orders)

## Design Principles

1. **Consistency** - Same pattern across all labs
2. **Safety** - Validates all inputs before use
3. **Clarity** - Clear error messages and help text
4. **Flexibility** - Supports both default and explicit values
5. **Backward Compatibility** - Maintains existing behavior

## Security Considerations

The template includes security notes in help text about CloudFront origin hijacking prevention:

1. Delete CloudFormation stack (includes CloudFront distributions)
2. Wait for stack DELETE_COMPLETE (15-30 minutes)
3. Delete S3 buckets (safe after CloudFront is deleted)

For more information, see: `workshop/CLOUDFRONT_SECURITY_FIX.md`

## Requirements Validation

This template validates the following requirements:

- **Requirement 1.1**: Uses default stack name when not provided
- **Requirement 1.2**: Uses provided stack name when specified
- **Requirement 1.3**: Validates stack name is not empty
- **Requirement 1.4**: Exits with error on invalid stack name
- **Requirement 3.1-3.4**: Help text shows default values
- **Requirement 4.1-4.4**: Maintains backward compatibility
- **Requirement 7.1-7.4**: Consistent implementation pattern

## Contributing

When modifying the template:

1. Update all affected cleanup scripts
2. Update unit tests to cover new functionality
3. Update this README with new features
4. Ensure backward compatibility
5. Test with all 7 lab cleanup scripts

## Related Documentation

- [Requirements Document](../../.kiro/specs/cleanup-stack-name-optional/requirements.md)
- [Design Document](../../.kiro/specs/cleanup-stack-name-optional/design.md)
- [CloudFront Security Fix](../../CLOUDFRONT_SECURITY_FIX.md)
- [Deployment & Cleanup Manual](../../DEPLOYMENT_CLEANUP_MANUAL.md)
