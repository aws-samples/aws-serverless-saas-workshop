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
PARALLEL=true

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
        
        # Create error log file for this lab
        local lab_error_log="$LOG_DIR/lab${lab_num}-error-$(date +%Y%m%d-%H%M%S).log"
        
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
        
        # Run deployment script with enhanced error capture
        print_message "$YELLOW" "Command: $deploy_cmd"
        print_message "$YELLOW" "Error log: $lab_error_log"
        
        # Capture both stdout and stderr, with stderr going to error log
        if eval "$deploy_cmd" 2> >(tee -a "$lab_error_log" >&2); then
            print_message "$GREEN" "Lab${lab_num} deployment completed successfully!"
            cd "$WORKSHOP_ROOT"
            return 0
        else
            local exit_code=$?
            print_message "$RED" "Lab${lab_num} deployment failed with exit code: $exit_code"
            print_message "$RED" "Error details saved to: $lab_error_log"
            
            # Add error summary to main log
            echo "" >> "$LOG_FILE"
            echo "=========================================" >> "$LOG_FILE"
            echo "Lab${lab_num} Deployment Error Summary" >> "$LOG_FILE"
            echo "=========================================" >> "$LOG_FILE"
            echo "Exit Code: $exit_code" >> "$LOG_FILE"
            echo "Command: $deploy_cmd" >> "$LOG_FILE"
            echo "Error Log: $lab_error_log" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
            echo "Last 50 lines of error output:" >> "$LOG_FILE"
            tail -n 50 "$lab_error_log" >> "$LOG_FILE" 2>/dev/null || echo "No error output captured" >> "$LOG_FILE"
            echo "=========================================" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
            
            cd "$WORKSHOP_ROOT"
            return 1
        fi
    else
        print_message "$RED" "No deployment script found for Lab${lab_num}"
        return 1
    fi
    
    echo ""
}

# Generic function to deploy multiple labs in parallel
deploy_labs_parallel() {
    local labs_to_deploy=("$@")
    local wave_name="All Labs Parallel"
    
    print_message "$YELLOW" "$wave_name: Starting parallel deployment of ${#labs_to_deploy[@]} labs: ${labs_to_deploy[*]}..."
    
    # Create temporary files to capture exit codes
    local status_files=()
    local pids=()
    
    # Deploy each lab in background
    for lab in "${labs_to_deploy[@]}"; do
        local status_file=$(mktemp)
        status_files+=("$status_file")
        
        (
            if deploy_lab "$lab"; then
                echo "0" > "$status_file"
            else
                echo "1" > "$status_file"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all deployments to complete
    print_message "$YELLOW" "Waiting for all ${#labs_to_deploy[@]} labs to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Check results
    local all_success=true
    for i in "${!labs_to_deploy[@]}"; do
        local lab="${labs_to_deploy[$i]}"
        local status=$(cat "${status_files[$i]}")
        
        # Cleanup temp file
        rm -f "${status_files[$i]}"
        
        if [ "$status" -eq 0 ]; then
            SUCCESSFUL_LABS+=("$lab")
            print_message "$GREEN" "Lab${lab} parallel deployment completed successfully!"
        else
            FAILED_LABS+=("$lab")
            print_message "$RED" "Lab${lab} parallel deployment failed!"
            all_success=false
        fi
    done
    
    # Return failure if any lab failed
    if [ "$all_success" = false ]; then
        return 1
    fi
    
    return 0
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
            export LAB2_EMAIL=$2
            shift 2
            ;;
        --tenant-email)
            export TENANT_EMAIL=$2
            shift 2
            ;;
        --profile)
            export PROFILE=$2
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --sequential)
            PARALLEL=false
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
                echo "  --parallel                  Enable parallel deployment (DEFAULT)"
                echo "  --sequential                Disable parallel deployment (deploy labs one by one)"
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
                echo "  Parallel deployment is ENABLED BY DEFAULT for faster deployment."
                echo "  Use --sequential to disable parallel mode and deploy labs one by one."
                echo "  When parallel is enabled:"
                echo "    All 7 labs deploy concurrently for maximum speed"
                echo "  This significantly reduces total deployment time from ~70-90 minutes to ~15-20 minutes"
                echo "  All labs are self-contained and infrastructure-independent"
                echo "  Lab3 creates its own complete infrastructure (Cognito, tenant management, shared services)"
                echo "  Lab7 is completely independent and generates its own sample data"
                echo ""
                echo "Examples:"
                echo "  $0 --email user@example.com"
                echo "  $0 --email user@example.com --tenant-email tenant@example.com"
                echo "  $0 --email user@example.com --profile serverless-saas-demo"
                echo "  $0 --email user@example.com --sequential  # Disable parallel mode"
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
    print_message "$YELLOW" "  Parallel Mode: Enabled (all 7 labs deploy concurrently)"
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
    # Parallel mode: Deploy all 7 labs concurrently
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "Parallel Deployment Mode (All 7 Labs)"
    print_message "$BLUE" "========================================"
    
    # Deploy all labs in parallel
    if ! deploy_labs_parallel 1 2 3 4 5 6 7; then
        if [ "$STOP_ON_ERROR" = true ]; then
            print_message "$RED" "Stopping deployment due to failures"
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
