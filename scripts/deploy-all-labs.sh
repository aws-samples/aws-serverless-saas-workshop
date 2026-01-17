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

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "AWS Serverless SaaS Workshop"
echo "Deploy All Labs Script"
echo "========================================"
echo "Log file: $LOG_FILE"
echo ""

# Default parameters
LAB1_STACK_NAME="serverless-saas-workshop-lab1"
LAB2_EMAIL=""

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

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
                deploy_cmd="./deployment.sh -s -c --stack-name $LAB1_STACK_NAME"
                print_message "$YELLOW" "Using stack name: $LAB1_STACK_NAME"
                ;;
            2)
                if [ -z "$LAB2_EMAIL" ]; then
                    print_message "$RED" "Lab2 requires --email parameter"
                    cd "$WORKSHOP_ROOT"
                    return 1
                fi
                deploy_cmd="./deployment.sh -s -c --email $LAB2_EMAIL"
                print_message "$YELLOW" "Using email: $LAB2_EMAIL"
                ;;
            3|4)
                deploy_cmd="./deployment.sh -s -c"
                ;;
            5|6)
                deploy_cmd="./deployment.sh -s -c"
                ;;
            7)
                deploy_cmd="./deployment.sh"
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

if [ $# -eq 0 ]; then
    DEPLOY_ALL=true
else
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
            --lab1-stack-name)
                LAB1_STACK_NAME=$2
                shift 2
                ;;
            --email)
                LAB2_EMAIL=$2
                shift 2
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
                echo "  --all                       Deploy all labs (default if no options provided)"
                echo "  --lab <number>              Deploy specific lab (can be used multiple times)"
                echo "  --lab1-stack-name <name>    Stack name for Lab1 (default: serverless-saas-workshop-lab1)"
                echo "  --email <email>             Email address for Lab2 (required if deploying Lab2)"
                echo "  --skip-verification         Skip prerequisite verification"
                echo "  --continue-on-error         Continue deploying next lab even if current fails"
                echo "  --help                      Show this help message"
                echo ""
                echo "Lab-Specific Requirements:"
                echo "  Lab1: Requires --lab1-stack-name (default provided)"
                echo "  Lab2: Requires --email parameter"
                echo "  Lab3-7: No additional parameters required"
                echo ""
                echo "Examples:"
                echo "  $0 --all --email user@example.com"
                echo "  $0 --lab 1 --lab1-stack-name my-stack"
                echo "  $0 --lab 2 --email user@example.com"
                echo "  $0 --lab 5 --lab 6"
                echo "  $0 --all --email user@example.com --continue-on-error"
                exit 0
                ;;
            *)
                print_message "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
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
        print_message "$RED" "Error: --email parameter is required for Lab2"
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
        if [ "$lab" == "2" ] && [ -z "$LAB2_EMAIL" ]; then
            print_message "$RED" "Error: --email parameter is required for Lab2"
            print_message "$YELLOW" "Please provide email with: --email user@example.com"
            exit 1
        fi
    done
fi

# Display configuration
echo ""
print_message "$YELLOW" "Configuration:"
print_message "$YELLOW" "  Lab1 Stack Name: $LAB1_STACK_NAME"
if [ -n "$LAB2_EMAIL" ]; then
    print_message "$YELLOW" "  Lab2 Email: $LAB2_EMAIL"
fi

echo ""

# Record start time
START_TIME=$(date +%s)

# Track deployment results
SUCCESSFUL_LABS=()
FAILED_LABS=()

# Deploy each lab
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
