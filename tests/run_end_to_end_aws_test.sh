#!/bin/bash

# End-to-End AWS Testing System - Convenient Wrapper Script
# This script provides a convenient way to run the end-to-end test suite

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
PROFILE=""
EMAIL=""
TENANT_EMAIL=""
REGION="us-east-1"
PARALLEL_MODE="--parallel"
TIMEOUT=6
VERBOSE=""

# Usage function
usage() {
    cat << EOF
Usage: $0 --profile <profile> --email <email> [OPTIONS]

Required Arguments:
  --profile <profile>        AWS CLI profile name (REQUIRED)
  --email <email>           Email address for admin and tenant accounts (REQUIRED)

Optional Arguments:
  --tenant-email <email>    Tenant admin email for Lab3-4 auto-creation
  --region <region>         AWS region (default: us-east-1)
  --sequential              Disable parallel deployment mode (parallel is default)
  --timeout <hours>         Maximum test execution time in hours (default: 6)
  --verbose                 Enable verbose logging
  -h, --help               Show this help message

Examples:
  # Run with default settings
  $0 --profile my-profile --email admin@example.com
  
  # Run with tenant auto-creation
  $0 --profile my-profile --email admin@example.com --tenant-email tenant@example.com
  
  # Run with custom region and sequential mode
  $0 --profile my-profile --email admin@example.com --region us-west-2 --sequential
  
  # Run with custom timeout and verbose logging
  $0 --profile my-profile --email admin@example.com --timeout 8 --verbose

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --tenant-email)
            TENANT_EMAIL="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --sequential)
            PARALLEL_MODE="--sequential"
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE="--verbose"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PROFILE" ]]; then
    echo -e "${RED}Error: --profile is required${NC}"
    usage
fi

if [[ -z "$EMAIL" ]]; then
    echo -e "${RED}Error: --email is required${NC}"
    usage
fi

# Display configuration
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}End-to-End AWS Testing System${NC}"
echo -e "${GREEN}========================================${NC}"
echo "AWS Profile: $PROFILE"
echo "AWS Region: $REGION"
echo "Email: $EMAIL"
echo "Tenant Email: ${TENANT_EMAIL:-Not provided}"
echo "Parallel Mode: $([ "$PARALLEL_MODE" = "--parallel" ] && echo "Enabled" || echo "Disabled")"
echo "Timeout: $TIMEOUT hours"
echo "Verbose: $([ -n "$VERBOSE" ] && echo "Enabled" || echo "Disabled")"
echo -e "${GREEN}========================================${NC}"
echo ""

# Build command
CMD="python3 test_end_to_end_aws_testing.py --profile $PROFILE --email $EMAIL --region $REGION $PARALLEL_MODE --timeout $TIMEOUT"

if [[ -n "$TENANT_EMAIL" ]]; then
    CMD="$CMD --tenant-email $TENANT_EMAIL"
fi

if [[ -n "$VERBOSE" ]]; then
    CMD="$CMD $VERBOSE"
fi

# Execute test
echo -e "${YELLOW}Starting test suite...${NC}"
echo ""

if eval "$CMD"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ TEST SUITE PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    EXIT_CODE=$?
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ TEST SUITE FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    exit $EXIT_CODE
fi
