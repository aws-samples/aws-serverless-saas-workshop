#!/bin/bash
#
# Wrapper script to run the end-to-end cleanup isolation test
#
# This script provides a convenient way to run the automated test suite
# for the lab cleanup isolation feature.
#
# Usage:
#   ./run_end_to_end_test.sh [OPTIONS]
#
# Options:
#   --dry-run              Run in dry-run mode (no AWS operations, fast)
#   --real-aws             Run against real AWS environment (requires --profile)
#   --profile <profile>    AWS CLI profile to use (required for --real-aws)
#   --email <email>        Email address for lab deployments (default: test@example.com)
#   -v, --verbose          Enable verbose pytest output
#   -h, --help             Show this help message
#
# Examples:
#   # Dry-run mode (fast, no AWS required)
#   ./run_end_to_end_test.sh --dry-run
#
#   # Real AWS mode (requires AWS credentials)
#   ./run_end_to_end_test.sh --real-aws --profile serverless-saas-demo --email admin@example.com
#
#   # Verbose output
#   ./run_end_to_end_test.sh --real-aws --profile serverless-saas-demo -v

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=true
AWS_PROFILE=""
EMAIL="test@example.com"
VERBOSE=""

# Function to print colored messages
print_message() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Wrapper script to run the end-to-end cleanup isolation test.

Options:
  --dry-run              Run in dry-run mode (no AWS operations, fast) [DEFAULT]
  --real-aws             Run against real AWS environment (requires --profile)
  --profile <profile>    AWS CLI profile to use (required for --real-aws)
  --email <email>        Email address for lab deployments (default: test@example.com)
  -v, --verbose          Enable verbose pytest output
  -h, --help             Show this help message

Examples:
  # Dry-run mode (fast, no AWS required)
  $0 --dry-run

  # Real AWS mode (requires AWS credentials)
  $0 --real-aws --profile serverless-saas-demo --email admin@example.com

  # Verbose output
  $0 --real-aws --profile serverless-saas-demo -v

Test Modes:
  Dry-run mode:
    - Simulates the workflow without actual AWS operations
    - Fast execution (~1-2 minutes)
    - No AWS credentials required
    - Useful for validating test logic

  Real AWS mode:
    - Executes actual deployment and cleanup operations
    - Slow execution (~60-90 minutes)
    - Requires AWS credentials and profile
    - Deploys and deletes real AWS resources
    - Incurs AWS costs

EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --real-aws)
            DRY_RUN=false
            shift
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_message "$RED" "Error: Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ "$DRY_RUN" == false && -z "$AWS_PROFILE" ]]; then
    print_message "$RED" "Error: Real AWS mode requires --profile option"
    show_usage
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print configuration
print_message "$BLUE" "========================================"
print_message "$BLUE" "End-to-End Cleanup Isolation Test"
print_message "$BLUE" "========================================"
echo ""
print_message "$YELLOW" "Configuration:"
if [[ "$DRY_RUN" == true ]]; then
    print_message "$GREEN" "  Mode: Dry-run (no AWS operations)"
else
    print_message "$YELLOW" "  Mode: Real AWS (actual deployment and cleanup)"
    print_message "$YELLOW" "  AWS Profile: $AWS_PROFILE"
    print_message "$YELLOW" "  Email: $EMAIL"
    print_message "$RED" "  ⚠️  WARNING: This will deploy and delete real AWS resources!"
    print_message "$RED" "  ⚠️  WARNING: This will incur AWS costs!"
    print_message "$RED" "  ⚠️  WARNING: Estimated runtime: 60-90 minutes"
fi
echo ""

# Confirm if running in real AWS mode
if [[ "$DRY_RUN" == false ]]; then
    read -p "Continue with real AWS deployment? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_message "$YELLOW" "Test cancelled by user"
        exit 0
    fi
    echo ""
fi

# Check if pytest is installed
if ! command -v pytest &> /dev/null; then
    print_message "$RED" "Error: pytest is not installed"
    print_message "$YELLOW" "Install pytest with: pip install pytest"
    exit 1
fi

# Check if test file exists
TEST_FILE="$SCRIPT_DIR/test_end_to_end_cleanup_isolation.py"
if [[ ! -f "$TEST_FILE" ]]; then
    print_message "$RED" "Error: Test file not found: $TEST_FILE"
    exit 1
fi

# Build pytest command as array to handle spaces in paths
PYTEST_CMD=("pytest" "$TEST_FILE")

# Add verbose flag if requested
if [[ -n "$VERBOSE" ]]; then
    PYTEST_CMD+=("-v")
fi

# Add real AWS mode flags if not dry-run
if [[ "$DRY_RUN" == false ]]; then
    PYTEST_CMD+=("--real-aws" "--aws-profile=$AWS_PROFILE" "--email=$EMAIL")
fi

# Add markers to show slow tests
PYTEST_CMD+=("-m" "slow or integration")

# Print command
print_message "$BLUE" "Running command:"
print_message "$GREEN" "  ${PYTEST_CMD[*]}"
echo ""

# Record start time
START_TIME=$(date +%s)

# Run the test
cd "$SCRIPT_DIR"
if "${PYTEST_CMD[@]}"; then
    TEST_RESULT=0
else
    TEST_RESULT=$?
fi

# Record end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# Print results
echo ""
print_message "$BLUE" "========================================"
if [[ $TEST_RESULT -eq 0 ]]; then
    print_message "$GREEN" "✓ Test Passed"
else
    print_message "$RED" "✗ Test Failed (exit code: $TEST_RESULT)"
fi
print_message "$BLUE" "Duration: ${DURATION_MIN}m ${DURATION_SEC}s"
print_message "$BLUE" "========================================"
echo ""

# Check for test report and organize outputs
REPORT_FILE="$SCRIPT_DIR/end_to_end_test_report.json"
REPORT_DIR="$SCRIPT_DIR/end_to_end_test_report"

if [[ -f "$REPORT_FILE" ]]; then
    print_message "$GREEN" "Test report generated: $REPORT_FILE"
    print_message "$YELLOW" "View report with: cat $REPORT_FILE | jq ."
    
    # Move report to report directory
    if [[ -d "$REPORT_DIR" ]]; then
        print_message "$BLUE" "Moving report to: $REPORT_DIR/"
        mv "$REPORT_FILE" "$REPORT_DIR/"
        
        # Extract individual step logs
        if [[ -f "$REPORT_DIR/extract_step_logs.py" ]]; then
            print_message "$BLUE" "Extracting individual step logs..."
            cd "$REPORT_DIR"
            python3 extract_step_logs.py
            
            # Generate summary report
            if [[ -f "generate_summary_report.py" ]]; then
                print_message "$BLUE" "Generating summary report..."
                python3 generate_summary_report.py
            fi
            cd "$SCRIPT_DIR"
        fi
        
        print_message "$GREEN" "All reports saved to: $REPORT_DIR/"
        print_message "$YELLOW" "View summary: cat $REPORT_DIR/SUMMARY.md"
        print_message "$YELLOW" "View logs: ls $REPORT_DIR/logs/"
    fi
fi

exit $TEST_RESULT
