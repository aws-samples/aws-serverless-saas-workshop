#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$(dirname "$SCRIPT_DIR")"

# Create log file
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-all-labs-$(date +%Y%m%d-%H%M%S).log"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

print_message "$BLUE" "========================================"
print_message "$BLUE" "AWS Serverless SaaS Workshop"
print_message "$BLUE" "Deploy All Labs Script"
print_message "$BLUE" "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Default parameters
LAB2_EMAIL=""
TENANT_EMAIL=""
PROFILE=""
PARALLEL=false

# Function to deploy a lab
deploy_lab() {
    local lab_num=$1
    local lab_dir="$WORKSHOP_ROOT/Lab${lab_num}"
    
    print_message "$BLUE" "========================================="
    print_message "$BLUE" "Deploying Lab${lab_num}..."
    print_message "$BLUE" "========================================="
    
    if [ ! -d "$lab_dir" ]; then
        print_message "$RED" "Lab${lab_num} directory not found, skipping..."
        return 1
    fi
    
    # Check if deployment script exists
    if [ -f "$lab_dir/scripts/deployment.sh" ]; then
        print_message "$GREEN" "Running Lab${lab_num} deployment script..."
        cd "$lab_dir/scripts"
        
        # Run deployment script with appropriate parameters
        local deploy_cmd=""
        case $lab_num in
            1)
                deploy_cmd="./deployment.sh -s -c"
                if [ -n "$PROFILE" ]; then
                    deploy_cmd="$deploy_cmd --profile $PROFILE"
                fi
                ;;
            2)
                if [ -z "$LAB2_EMAIL" ]; then
                    print_message "$RED" "Lab2 requires --email parameter"
                    cd "$WORKSHOP_ROOT"
                    return 1
                fi
                deploy_cmd="./deployment.sh -s -c --email $LAB2_EMAIL"
                if [ -n "$PROFILE" ]; then
                    deploy_cmd="$deploy_cmd --profile $PROFILE"
                fi
                print_message "$YELLOW" "Using email: $LAB2_EMAIL"
                ;;
            3|4)
                if [ -z "$LAB2_EMAIL" ]; then
                    print_message "$RED" "Lab${lab_num} requires --email parameter"
                    cd "$WORKSHOP_ROOT"
                    return 1
                fi
                deploy_cmd="./deployment.sh -s -c --email $LAB2_EMAIL"
                if [ -n "$TENANT_EMAIL" ]; then
                    deploy_cmd="$deploy_cmd --tenant-email $TENANT_EMAIL"
                    print_message "$YELLOW" "Using tenant email: $TENANT_EMAIL (auto-tenant creation enabled)"
                fi
                if [ -n "$PROFILE" ]; then
                    deploy_cmd="$deploy_cmd --profile $PROFILE"
                fi
                print_message "$YELLOW" "Using email: $LAB2_EMAIL"
                ;;
            5|6)
                deploy_cmd="./deployment.sh -s -c"
                if [ -n "$PROFILE" ]; then
                    deploy_cmd="$deploy_cmd --profile $PROFILE"
                fi
                ;;
            7)
                deploy_cmd="./deployment.sh"
                if [ -n "$PROFILE" ]; then
                    deploy_cmd="$deploy_cmd --profile $PROFILE"
                fi
                ;;
            *)
                print_message "$RED" "Unknown lab number: $lab_num"
                cd "$WORKSHOP_ROOT"
                return 1
                ;;
        esac
        
        # Run deployment script
        if eval "$deploy_cmd"; then
            print_message "$GREEN" "Lab${lab_num} deployment completed successfully!"
            cd "$WORKSHOP_ROOT"
            return 0
        else
            print_message "$RED" "Lab${lab_num} deployment failed!"
            cd "$WORKSHOP_ROOT"
            return 1
        fi
    else
        print_message "$RED" "No deployment script found for Lab${lab_num}"
        return 1
    fi
    
    echo ""
}

# Generic function to deploy two labs in parallel
deploy_two_labs_parallel() {
    local lab1_num=$1
    local lab2_num=$2
    local wave_name=$3
    
    print_message "$YELLOW" "$wave_name: Starting parallel deployment of Lab$lab1_num and Lab$lab2_num..."
    
    # Create temporary files to capture exit codes
    local lab1_status_file=$(mktemp)
    local lab2_status_file=$(mktemp)
    
    # Deploy first lab in background
    (
        if deploy_lab $lab1_num; then
            echo "0" > "$lab1_status_file"
        else
            echo "1" > "$lab1_status_file"
        fi
    ) &
    local lab1_pid=$!
    
    # Deploy second lab in background
    (
        if deploy_lab $lab2_num; then
            echo "0" > "$lab2_status_file"
        else
            echo "1" > "$lab2_status_file"
        fi
    ) &
    local lab2_pid=$!
    
    # Wait for both deployments to complete
    print_message "$YELLOW" "Waiting for Lab$lab1_num and Lab$lab2_num to complete..."
    wait $lab1_pid
    wait $lab2_pid
    
    # Check results
    local lab1_status=$(cat "$lab1_status_file")
    local lab2_status=$(cat "$lab2_status_file")
    
    # Cleanup temp files
    rm -f "$lab1_status_file" "$lab2_status_file"
    
    # Track results
    local wave_failed=false
    
    if [ "$lab1_status" -eq 0 ]; then
        SUCCESSFUL_LABS+=($lab1_num)
        print_message "$GREEN" "Lab$lab1_num parallel deployment completed successfully!"
    else
        FAILED_LABS+=($lab1_num)
        print_message "$RED" "Lab$lab1_num parallel deployment failed!"
        wave_failed=true
    fi
    
    if [ "$lab2_status" -eq 0 ]; then
        SUCCESSFUL_LABS+=($lab2_num)
        print_message "$GREEN" "Lab$lab2_num parallel deployment completed successfully!"
    else
        FAILED_LABS+=($lab2_num)
        print_message "$RED" "Lab$lab2_num parallel deployment failed!"
        wave_failed=true
    fi
    
    # Return failure if either lab failed
    if [ "$wave_failed" = true ]; then
        return 1
    fi
    
    return 0
}

# Function to deploy a single lab (for odd-numbered final wave)
deploy_single_lab() {
    local lab_num=$1
    local wave_name=$2
    
    print_message "$YELLOW" "$wave_name: Starting deployment of Lab$lab_num..."
    
    if deploy_lab $lab_num; then
        SUCCESSFUL_LABS+=($lab_num)
        print_message "$GREEN" "Lab$lab_num deployment completed successfully!"
        return 0
    else
        FAILED_LABS+=($lab_num)
        print_message "$RED" "Lab$lab_num deployment failed!"
        return 1
    fi
}

# Function to verify prerequisites
verify_prerequisites() {
    print_message "$YELLOW" "Verifying prerequisites..."
    
    local missing_tools=()
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    # Check SAM CLI
    if ! command -v sam &> /dev/null; then
        missing_tools+=("sam-cli")
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        missing_tools+=("node")
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        missing_tools+=("npm")
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_message "$RED" "Missing required tools: ${missing_tools[*]}"
        print_message "$RED" "Please install missing tools before running this script"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_message "$RED" "AWS credentials not configured or invalid"
        print_message "$RED" "Please configure AWS credentials before running this script"
        return 1
    fi
    
    print_message "$GREEN" "All prerequisites verified!"
    echo ""
    return 0
}

# Parse command line arguments
LABS_TO_DEPLOY=()
DEPLOY_ALL=false
SKIP_VERIFICATION=false
STOP_ON_ERROR=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DEPLOY_ALL=true
            shift
            ;;
        --lab)
            LABS_TO_DEPLOY+=("$2")
            shift 2
            ;;
        --email)
            LAB2_EMAIL=$2
            shift 2
            ;;
        --tenant-email)
            TENANT_EMAIL=$2
            shift 2
            ;;
        --profile)
            PROFILE=$2
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --skip-verification)
            SKIP_VERIFICATION=true
            shift
            ;;
        --continue-on-error)
            STOP_ON_ERROR=false
            shift
            ;;
        --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --lab <number>              Deploy specific lab (can be used multiple times)"
                echo "                              If no --lab is specified, all labs are deployed by default"
                echo "  --email <email>             Email address for Lab2-4 (required if deploying these labs)"
                echo "  --tenant-email <email>      Tenant admin email for Lab3-4 (optional, enables auto-tenant creation)"
                echo "  --profile <profile>         AWS profile to use (optional, uses default if not provided)"
                echo "  --parallel                  Enable parallel deployment of independent labs"
                echo "  --skip-verification         Skip prerequisite verification"
                echo "  --continue-on-error         Continue deploying next lab even if current fails"
                echo "  --help                      Show this help message"
                echo ""
                echo "Lab-Specific Requirements:"
                echo "  Lab1: No additional parameters required"
                echo "  Lab2-4: Requires --email parameter"
                echo "  Lab3-4: Optional --tenant-email parameter (enables auto-tenant creation)"
                echo "  Lab5-7: No additional parameters required"
                echo ""
                echo "Parallel Deployment:"
                echo "  When --parallel is enabled:"
                echo "    Wave 1: Lab1 and Lab2 deploy concurrently"
                echo "    Wave 2: Lab3 and Lab4 deploy concurrently"
                echo "    Wave 3: Lab5 and Lab6 deploy concurrently"
                echo "    Wave 4: Lab7 deploys independently"
                echo "  This significantly reduces total deployment time"
                echo "  All labs are self-contained and infrastructure-independent"
                echo "  Lab3 creates its own complete infrastructure (Cognito, tenant management, shared services)"
                echo "  Lab7 is completely independent and generates its own sample data"
                echo ""
                echo "Examples:"
                echo "  $0 --email user@example.com"
                echo "  $0 --email user@example.com --tenant-email tenant@example.com"
                echo "  $0 --email user@example.com --profile serverless-saas-demo"
                echo "  $0 --email user@example.com --parallel"
                echo "  $0 --lab 1"
                echo "  $0 --lab 2 --email user@example.com --profile my-profile"
                echo "  $0 --lab 3 --email user@example.com --tenant-email tenant@example.com"
                echo "  $0 --lab 5 --lab 6"
                echo "  $0 --email user@example.com --continue-on-error"
                exit 0
                ;;
            *)
                print_message "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

# If no specific labs were selected, deploy all labs by default
if [ ${#LABS_TO_DEPLOY[@]} -eq 0 ] && [ "$DEPLOY_ALL" = false ]; then
    DEPLOY_ALL=true
fi

# Verify prerequisites unless skipped
if [ "$SKIP_VERIFICATION" = false ]; then
    if ! verify_prerequisites; then
        exit 1
    fi
fi

# Determine which labs to deploy
if [ "$DEPLOY_ALL" = true ]; then
    LABS_TO_DEPLOY=(1 2 3 4 5 6 7)
    print_message "$GREEN" "Deploying all labs in order..."
    
    # Validate required parameters for all labs
    if [ -z "$LAB2_EMAIL" ]; then
        print_message "$RED" "Error: --email parameter is required for Lab2-4"
        print_message "$YELLOW" "Please provide email with: --email user@example.com"
        exit 1
    fi
else
    # Sort labs in order
    IFS=$'\n' LABS_TO_DEPLOY=($(sort -n <<<"${LABS_TO_DEPLOY[*]}"))
    unset IFS
    print_message "$GREEN" "Deploying selected labs: ${LABS_TO_DEPLOY[*]}"
    
    # Validate required parameters for selected labs
    for lab in "${LABS_TO_DEPLOY[@]}"; do
        if [[ "$lab" =~ ^[234]$ ]] && [ -z "$LAB2_EMAIL" ]; then
            print_message "$RED" "Error: --email parameter is required for Lab${lab}"
            print_message "$YELLOW" "Please provide email with: --email user@example.com"
            exit 1
        fi
    done
fi

# Display configuration
echo ""
print_message "$YELLOW" "Configuration:"
if [ -n "$LAB2_EMAIL" ]; then
    print_message "$YELLOW" "  Admin Email: $LAB2_EMAIL"
fi
if [ -n "$TENANT_EMAIL" ]; then
    print_message "$YELLOW" "  Tenant Email: $TENANT_EMAIL (auto-tenant creation enabled)"
fi
if [ -n "$PROFILE" ]; then
    print_message "$YELLOW" "  AWS Profile: $PROFILE"
fi
if [ "$PARALLEL" = true ]; then
    print_message "$YELLOW" "  Parallel Mode: Enabled (4 waves of 2 labs each)"
fi
print_message "$YELLOW" "  Stop on Error: $STOP_ON_ERROR"

echo ""

# Record start time
START_TIME=$(date +%s)

# Track deployment results
SUCCESSFUL_LABS=()
FAILED_LABS=()

# Deploy labs based on mode
if [ "$DEPLOY_ALL" = true ] && [ "$PARALLEL" = true ]; then
    # Parallel mode: Deploy labs in waves of 2
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "Parallel Deployment Mode (Waves of 2)"
    print_message "$BLUE" "========================================"
    
    continue_deployment=true
    
    # Wave 1: Lab1 + Lab2
    if [ "$continue_deployment" = true ]; then
        if ! deploy_two_labs_parallel 1 2 "Wave 1"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping deployment due to Wave 1 failure"
                continue_deployment=false
            fi
        fi
    fi
    
    # Wave 2: Lab3 + Lab4
    if [ "$continue_deployment" = true ]; then
        if ! deploy_two_labs_parallel 3 4 "Wave 2"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping deployment due to Wave 2 failure"
                continue_deployment=false
            fi
        fi
    fi
    
    # Wave 3: Lab5 + Lab6
    if [ "$continue_deployment" = true ]; then
        if ! deploy_two_labs_parallel 5 6 "Wave 3"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping deployment due to Wave 3 failure"
                continue_deployment=false
            fi
        fi
    fi
    
    # Wave 4: Lab7 (single lab)
    if [ "$continue_deployment" = true ]; then
        if ! deploy_single_lab 7 "Wave 4"; then
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping deployment due to Wave 4 failure"
            fi
        fi
    fi
    
    # Clear the list since all labs are processed
    LABS_TO_DEPLOY=()
else
    # Sequential mode: Deploy all labs one by one
    for lab in "${LABS_TO_DEPLOY[@]}"; do
        if deploy_lab "$lab"; then
            SUCCESSFUL_LABS+=("$lab")
        else
            FAILED_LABS+=("$lab")
            if [ "$STOP_ON_ERROR" = true ]; then
                print_message "$RED" "Stopping deployment due to Lab${lab} failure"
                break
            fi
        fi
    done
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Print summary
print_message "$BLUE" "========================================"
print_message "$BLUE" "Deployment Summary"
print_message "$BLUE" "========================================"

if [ ${#SUCCESSFUL_LABS[@]} -gt 0 ]; then
    print_message "$GREEN" "Successfully deployed labs: ${SUCCESSFUL_LABS[*]}"
fi

if [ ${#FAILED_LABS[@]} -gt 0 ]; then
    print_message "$RED" "Failed to deploy labs: ${FAILED_LABS[*]}"
fi

print_message "$BLUE" "Duration: ${DURATION} seconds"
print_message "$BLUE" "Log file: $LOG_FILE"
print_message "$BLUE" "========================================"

# Exit with error if any labs failed
if [ ${#FAILED_LABS[@]} -gt 0 ]; then
    exit 1
fi

print_message "$GREEN" "All labs deployed successfully!"
