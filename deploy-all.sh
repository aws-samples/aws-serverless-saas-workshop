#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# =============================================================================
# AWS Serverless SaaS Workshop - Deploy All Labs Script
# =============================================================================
# This script deploys all 7 labs of the AWS Serverless SaaS Workshop using
# the main orchestration CloudFormation template with nested stacks.
# 
# The orchestration template deploys all labs in TRUE PARALLEL using nested stacks.
# The APIGatewayCloudWatchRole and APIGatewayAccount are created FIRST, then
# all 8 lab stacks (Lab1-7 + Lab7Pooled) deploy simultaneously.
#
# LOG GROUP RETENTION STRATEGY:
#   Instead of creating log groups in CloudFormation (which has a race condition
#   with RetentionInDays), we let Lambda create log groups automatically on first
#   invocation. The set-log-retention.sh script runs AFTER deployment to set
#   60-day retention policies on all log groups. This eliminates the race condition
#   entirely and removes the need for any stabilization delay.
#
# RETRY LOGIC (Improved February 2026):
#   The script automatically retries deployment once if it fails. This handles
#   transient failures like CloudWatch Log Group eventual consistency issues.
#   
#   KEY IMPROVEMENT: On failure, the script does NOT delete the entire stack.
#   Instead, it uses update-stack to retry ONLY the failed nested stacks while
#   preserving successfully deployed resources.
#   
#   - Max retries: 2 (initial + 1 retry)
#   - Retry delay: 30 seconds
#   - Successfully deployed nested stacks are PRESERVED on retry
#   - Only ROLLBACK_COMPLETE state requires full stack deletion
#   - Detailed failure analysis shows which nested stacks failed
#
# This reduces total deployment time from ~70-90 minutes (sequential) to ~15-20 minutes
# (parallel deployment without stabilization delay).
#
# PROCESS:
#   1. Create S3 bucket for templates and artifacts
#   2. Package each lab's SAM template in parallel (uploads code to S3)
#   3. Generate main template with S3 URLs for nested stacks
#   4. Deploy the orchestration stack (with automatic retry on failure)
#   5. Set log retention on all Lambda log groups (60 days)
#   6. Build and deploy frontend applications
#   7. Create Cognito users (if --email provided)
#
# USAGE:
#   ./deploy-all.sh --profile <aws-profile> [--email <admin-email>]
#
# AUTOMATIC USER CREATION:
#   When --email is provided, the script automatically creates Cognito admin users
#   after deployment completes by calling create-workshop-users.sh internally.
#
# TWO-PHASE DEPLOYMENT (alternative):
#   Phase 1: ./deploy-all.sh --profile <aws-profile>
#   Phase 2: ./orchestration/create-workshop-users.sh --email <admin-email> --profile <aws-profile>
#
# CRITICAL: Execute this script directly (./deploy-all.sh), NEVER with bash command
# =============================================================================

set -e

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# SCRIPT DIRECTORY DETECTION
# =============================================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSHOP_ROOT="$SCRIPT_DIR"
ORCHESTRATION_DIR="$SCRIPT_DIR/orchestration"

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================
DEFAULT_STACK_NAME="serverless-saas-lab"
DEFAULT_REGION="us-east-1"
DEFAULT_PASSWORD="SaaS#Workshop2026"
DEFAULT_ENVIRONMENT="dev"

# =============================================================================
# VARIABLES
# =============================================================================
STACK_NAME=""
PROFILE=""
REGION="$DEFAULT_REGION"
EMAIL=""
TENANT_EMAIL=""
PASSWORD="$DEFAULT_PASSWORD"
ENVIRONMENT="$DEFAULT_ENVIRONMENT"
S3_BUCKET=""
DISABLE_ROLLBACK=true

# =============================================================================
# LOGGING SETUP
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$ORCHESTRATION_DIR/logs/$TIMESTAMP"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-orchestration.log"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "INFO") print_message "$GREEN" "$message" ;;
        "WARN") print_message "$YELLOW" "$message" ;;
        "ERROR") print_message "$RED" "$message" ;;
        "DEBUG") print_message "$CYAN" "$message" ;;
        *) echo "$message" ;;
    esac
}

# =============================================================================
# GET MAIN LAB STACK NAME
# =============================================================================
# CloudFormation nested stacks have names like:
#   serverless-saas-lab-Lab2Stack-J7RUWRILQCA2 (main lab stack - what we want)
#   serverless-saas-lab-Lab2Stack-J7RUWRILQCA2-APIs-14TNZA5EC8N1C (nested-nested - NOT what we want)
# This function returns the shortest matching stack name (the main lab stack)
get_main_lab_stack() {
    local lab_pattern=$1
    aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --profile "$PROFILE" --region "$REGION" \
        --query "StackSummaries[?contains(StackName, '${lab_pattern}')].StackName" \
        --output text 2>/dev/null | tr '\t' '\n' | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2- || echo ""
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
show_help() {
    cat << EOF
AWS Serverless SaaS Workshop - Deploy All Labs Script

USAGE:
    ./deploy-all.sh --profile <aws-profile> [OPTIONS]

REQUIRED:
    --profile <profile>         AWS CLI profile name (REQUIRED)

OPTIONS:
    --email <email>             Admin email address for Labs 2-6 (triggers automatic user creation)
    --tenant-email <email>      Tenant email for auto-tenant creation in Labs 3-4
    --password <password>       Admin temporary password (default: $DEFAULT_PASSWORD)
    --environment <env>         Deployment environment: dev, staging, prod (default: $DEFAULT_ENVIRONMENT)
    --stack-name <name>         Main orchestration stack name (default: $DEFAULT_STACK_NAME)
    --region <region>           AWS region (default: $DEFAULT_REGION)
    --disable-rollback          Disable CloudFormation rollback on failure (DEFAULT - enabled by default)
                                If deployment fails, fix the issue and re-run - the script
                                will automatically update the existing stack instead of
                                requiring cleanup first.
    --enable-rollback           Enable CloudFormation rollback on failure (use for production)
    --help                      Show this help message

AUTOMATIC USER CREATION (recommended):
    When --email is provided, the script automatically creates Cognito admin users
    after deployment completes. This is the simplest approach:
    
        ./deploy-all.sh --email admin@example.com --profile my-profile
    
    This will:
    1. Deploy all infrastructure (CloudFormation stacks)
    2. Build and deploy frontend applications
    3. Automatically create admin users in Cognito for Labs 2-6

TWO-PHASE DEPLOYMENT (alternative):
    You can also deploy without --email and create users separately:
    
    Phase 1: Deploy infrastructure without users
        ./deploy-all.sh --profile my-profile
    
    Phase 2: Create users after deployment
        ./orchestration/create-workshop-users.sh --email admin@example.com --profile my-profile
    
    This approach allows:
    - Faster infrastructure deployment without email dependency
    - Flexibility to create users with different emails later
    - Separation of infrastructure and user management

DEBUGGING WITH --disable-rollback (recommended for troubleshooting):
    When using --disable-rollback, failed stacks are preserved for analysis:
    
    1. First deployment attempt:
        ./deploy-all.sh --profile my-profile --disable-rollback
    
    2. If it fails, investigate the error and fix the template/code
    
    3. Re-run the SAME command - it will UPDATE the existing stack:
        ./deploy-all.sh --profile my-profile --disable-rollback
    
    This avoids the need to run cleanup between attempts, saving significant time.
    The script automatically detects the stack state and uses update-stack when appropriate.

DEPLOYMENT DETAILS:
    This script deploys all 7 labs in TRUE PARALLEL using CloudFormation nested stacks.
    The APIGatewayCloudWatchRole is created FIRST, then all 8 lab stacks deploy
    simultaneously.
    
    LOG GROUP RETENTION:
    Instead of creating log groups in CloudFormation (which has a race condition with
    RetentionInDays), Lambda creates log groups automatically on first invocation.
    The set-log-retention.sh script runs AFTER deployment to set 60-day retention.
    
    AUTOMATIC RETRY:
    The script automatically retries deployment once if it fails. This handles transient
    failures like CloudWatch Log Group eventual consistency issues:
    - Max retries: 2 (initial attempt + 1 retry)
    - Retry delay: 30 seconds between attempts
    - Failed stacks are automatically cleaned up before retry
    
    Process:
    1. Creates S3 bucket for templates and code artifacts
    2. Packages each lab's SAM template in parallel (uploads Lambda code to S3)
    3. Generates orchestration template with S3 URLs
    4. Deploys single CloudFormation stack with all labs as nested stacks (parallel)
       - Automatically retries once on failure
    5. Sets log retention on all Lambda log groups (60 days)
    6. Builds and deploys frontend applications
    7. Creates Cognito users (if --email provided)

    Total deployment time: ~15-20 minutes (parallel deployment)

CRITICAL:
    - Execute this script directly: ./deploy-all.sh
    - NEVER run with bash command: bash deploy-all.sh (WILL FAIL)

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --email requires a value"; exit 1; }
                EMAIL="$2"; shift 2 ;;
            --tenant-email)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --tenant-email requires a value"; exit 1; }
                TENANT_EMAIL="$2"; shift 2 ;;
            --profile)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --profile requires a value"; exit 1; }
                PROFILE="$2"; shift 2 ;;
            --password)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --password requires a value"; exit 1; }
                PASSWORD="$2"; shift 2 ;;
            --environment)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --environment requires a value"; exit 1; }
                [[ "$2" != "dev" && "$2" != "staging" && "$2" != "prod" ]] && { print_message "$RED" "ERROR: --environment must be: dev, staging, prod"; exit 1; }
                ENVIRONMENT="$2"; shift 2 ;;
            --stack-name)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --stack-name requires a value"; exit 1; }
                STACK_NAME="$2"; shift 2 ;;
            --region)
                [[ -z "$2" || "$2" == --* ]] && { print_message "$RED" "ERROR: --region requires a value"; exit 1; }
                REGION="$2"; shift 2 ;;
            --disable-rollback) DISABLE_ROLLBACK=true; shift ;;
            --enable-rollback) DISABLE_ROLLBACK=false; shift ;;
            --help) show_help ;;
            *) print_message "$RED" "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Validate required parameters
    [[ -z "$PROFILE" ]] && { print_message "$RED" "ERROR: --profile is required"; exit 1; }
    
    # Validate email format only if email is provided (email is now optional)
    if [[ -n "$EMAIL" ]]; then
        [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && { print_message "$RED" "ERROR: Invalid email format"; exit 1; }
    fi
    
    [[ -z "$STACK_NAME" ]] && STACK_NAME="$DEFAULT_STACK_NAME"
}

# =============================================================================
# PREREQUISITE VERIFICATION
# =============================================================================

verify_prerequisites() {
    log_message "INFO" "========================================"
    log_message "INFO" "Verifying Prerequisites"
    log_message "INFO" "========================================"
    echo ""
    
    local prereqs_met=true
    
    # Check AWS CLI
    if command -v aws &> /dev/null; then
        log_message "INFO" "✓ AWS CLI: $(aws --version 2>&1 | head -n1)"
    else
        log_message "ERROR" "✗ AWS CLI not found"
        prereqs_met=false
    fi
    
    # Check SAM CLI
    if command -v sam &> /dev/null; then
        log_message "INFO" "✓ SAM CLI: $(sam --version 2>&1)"
    else
        log_message "ERROR" "✗ SAM CLI not found"
        prereqs_met=false
    fi
    
    # Verify AWS profile
    if aws sts get-caller-identity --profile "$PROFILE" &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
        log_message "INFO" "✓ AWS Profile: $PROFILE (Account: $account_id)"
    else
        log_message "ERROR" "✗ AWS profile '$PROFILE' is not configured"
        prereqs_met=false
    fi
    
    echo ""
    [[ "$prereqs_met" == false ]] && { log_message "ERROR" "Prerequisites not met"; exit 1; }
    log_message "INFO" "✓ All prerequisites verified"
    echo ""
}

# =============================================================================
# S3 BUCKET MANAGEMENT
# =============================================================================

create_s3_bucket() {
    local account_id=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
    S3_BUCKET="serverless-saas-orchestration-${account_id}-${REGION}"
    
    log_message "INFO" "Checking S3 bucket: $S3_BUCKET"
    
    if aws s3api head-bucket --bucket "$S3_BUCKET" --profile "$PROFILE" --region "$REGION" 2>/dev/null; then
        log_message "INFO" "✓ S3 bucket exists"
    else
        log_message "INFO" "Creating S3 bucket..."
        if [[ "$REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "$S3_BUCKET" --profile "$PROFILE" --region "$REGION" >> "$LOG_FILE" 2>&1
        else
            aws s3api create-bucket --bucket "$S3_BUCKET" --profile "$PROFILE" --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION" >> "$LOG_FILE" 2>&1
        fi
        log_message "INFO" "✓ S3 bucket created"
    fi
}

# =============================================================================
# API GATEWAY ACCOUNT CONFIGURATION
# =============================================================================
# NOTE: The APIGatewayCloudWatchRole is created by the main CloudFormation template.
# This function only configures the API Gateway account settings AFTER deployment
# to use the role created by CloudFormation.
# =============================================================================

configure_api_gateway_account() {
    # This function is called AFTER deployment to configure API Gateway account settings
    # The role is created by CloudFormation (APIGatewayCloudWatchRole resource)
    local role_name="apigateway-cloudwatch-publish-role"
    local account_id=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
    local role_arn="arn:aws:iam::${account_id}:role/${role_name}"
    
    log_message "INFO" "Configuring API Gateway account to use CloudWatch role..."
    
    # Configure API Gateway account settings to use the role created by CloudFormation
    if ! aws apigateway update-account \
        --patch-operations op=replace,path=/cloudwatchRoleArn,value="$role_arn" \
        --profile "$PROFILE" \
        --region "$REGION" >> "$LOG_FILE" 2>&1; then
        log_message "WARN" "Could not update API Gateway account settings (may already be configured)"
    else
        log_message "INFO" "✓ API Gateway account configured to use CloudWatch role"
    fi
    
    return 0
}

# =============================================================================
# VALIDATE BASE TEMPLATE STRUCTURE
# =============================================================================

validate_base_template() {
    local template="$ORCHESTRATION_DIR/main-template.yaml"
    
    log_message "INFO" "========================================"
    log_message "INFO" "Validating Base Template Structure"
    log_message "INFO" "========================================"
    echo ""
    
    # Check if template file exists
    if [[ ! -f "$template" ]]; then
        log_message "ERROR" "Base template not found: $template"
        return 1
    fi
    
    # Check required resources exist
    local required_resources=(
        "APIGatewayCloudWatchRole"
        "APIGatewayAccount"
        "Lab1Stack"
        "Lab2Stack"
        "Lab3Stack"
        "Lab3TenantStack"
        "Lab4Stack"
        "Lab4TenantStack"
        "Lab5Stack"
        "Lab6Stack"
        "Lab7Stack"
        "Lab7PooledStack"
    )
    
    local missing_resources=()
    
    for resource in "${required_resources[@]}"; do
        if ! grep -q "^  ${resource}:" "$template"; then
            missing_resources+=("$resource")
        fi
    done
    
    if [[ ${#missing_resources[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required resources in base template:"
        for resource in "${missing_resources[@]}"; do
            log_message "ERROR" "  - $resource"
        done
        return 1
    fi
    
    log_message "INFO" "✓ Base template structure validated"
    log_message "INFO" "  All ${#required_resources[@]} required resources found"
    echo ""
    return 0
}

# =============================================================================
# SAM PACKAGE FUNCTIONS
# =============================================================================

package_lab_template() {
    local lab_num=$1
    local template_path=$2
    local output_template="$LOG_DIR/lab${lab_num}-packaged.yaml"
    local lab_dir=$(dirname "$template_path")
    # Use separate build directories for each lab to avoid race conditions
    # This is critical for Lab 7 and Lab 7p which share the same parent directory
    local build_dir="$lab_dir/.aws-sam/build-${lab_num}"
    local built_template="$build_dir/template.yaml"
    
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Packaging Lab $lab_num..." >> "$LOG_FILE"
    
    # Build the SAM application first - this compiles dependencies and creates the build artifacts
    if ! sam build \
        --template-file "$template_path" \
        --build-dir "$build_dir" \
        --profile "$PROFILE" \
        --region "$REGION" >> "$LOG_FILE" 2>&1; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   SAM build failed for Lab $lab_num" >> "$LOG_FILE"
        return 1
    fi
    
    # Package the BUILT template (not the original) - this uploads artifacts to S3
    # The built template is in .aws-sam/build/template.yaml
    if sam package \
        --template-file "$built_template" \
        --output-template-file "$output_template" \
        --s3-bucket "$S3_BUCKET" \
        --s3-prefix "lab${lab_num}" \
        --profile "$PROFILE" \
        --region "$REGION" >> "$LOG_FILE" 2>&1; then
        
        # Upload packaged template to S3
        local s3_key="templates/lab${lab_num}-template.yaml"
        aws s3 cp "$output_template" "s3://${S3_BUCKET}/${s3_key}" --profile "$PROFILE" --region "$REGION" >> "$LOG_FILE" 2>&1
        
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab $lab_num packaged" >> "$LOG_FILE"
        
        # Output the HTTPS URL to stdout (for CloudFormation nested stacks)
        echo "https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${s3_key}"
        return 0
    else
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   ✗ Lab $lab_num packaging failed" >> "$LOG_FILE"
        return 1
    fi
}

package_all_labs() {
    log_message "INFO" "========================================"
    log_message "INFO" "Packaging Lab Templates (Parallel)"
    log_message "INFO" "========================================"
    echo ""
    
    # Define templates (bash 3 compatible - no associative arrays)
    local LAB1_TEMPLATE="$WORKSHOP_ROOT/Lab1/server/template.yaml"
    local LAB2_TEMPLATE="$WORKSHOP_ROOT/Lab2/server/template.yaml"
    local LAB3_TEMPLATE="$WORKSHOP_ROOT/Lab3/server/shared-template.yaml"
    local LAB3T_TEMPLATE="$WORKSHOP_ROOT/Lab3/server/tenant-template.yaml"
    local LAB4_TEMPLATE="$WORKSHOP_ROOT/Lab4/server/shared-template.yaml"
    local LAB4T_TEMPLATE="$WORKSHOP_ROOT/Lab4/server/tenant-template.yaml"
    local LAB5_TEMPLATE="$WORKSHOP_ROOT/Lab5/server/shared-template.yaml"
    local LAB6_TEMPLATE="$WORKSHOP_ROOT/Lab6/server/shared-template.yaml"
    local LAB7_TEMPLATE="$WORKSHOP_ROOT/Lab7/template.yaml"
    local LAB7P_TEMPLATE="$WORKSHOP_ROOT/Lab7/tenant-template.yaml"
    
    # Pre-clean all .aws-sam build directories to prevent race conditions
    # SAM build tries to clean directories during build, which causes [Errno 66] Directory not empty
    # when multiple parallel builds are running. By cleaning BEFORE parallel builds start, we avoid this.
    log_message "INFO" "  Pre-cleaning build directories..."
    for lab_num in 1 2 3 4 5 6 7; do
        local lab_dir
        case $lab_num in
            1) lab_dir="$WORKSHOP_ROOT/Lab1/server" ;;
            2) lab_dir="$WORKSHOP_ROOT/Lab2/server" ;;
            3) lab_dir="$WORKSHOP_ROOT/Lab3/server" ;;
            4) lab_dir="$WORKSHOP_ROOT/Lab4/server" ;;
            5) lab_dir="$WORKSHOP_ROOT/Lab5/server" ;;
            6) lab_dir="$WORKSHOP_ROOT/Lab6/server" ;;
            7) lab_dir="$WORKSHOP_ROOT/Lab7" ;;
        esac
        # Remove all .aws-sam directories (including build-N subdirectories)
        if [[ -d "$lab_dir/.aws-sam" ]]; then
            rm -rf "$lab_dir/.aws-sam" 2>/dev/null || true
        fi
    done
    log_message "INFO" "  ✓ Build directories cleaned"
    
    local pids=()
    local labs=()
    local failed=false
    
    # Package all labs in parallel
    for lab_info in "1:$LAB1_TEMPLATE" "2:$LAB2_TEMPLATE" "3:$LAB3_TEMPLATE" "3t:$LAB3T_TEMPLATE" "4:$LAB4_TEMPLATE" "4t:$LAB4T_TEMPLATE" "5:$LAB5_TEMPLATE" "6:$LAB6_TEMPLATE" "7:$LAB7_TEMPLATE" "7p:$LAB7P_TEMPLATE"; do
        IFS=':' read -r lab_num template <<< "$lab_info"
        
        if [[ -f "$template" ]]; then
            # Package in background
            (
                package_lab_template "$lab_num" "$template" > "$LOG_DIR/package-lab-${lab_num}.log" 2>&1
            ) &
            pids+=($!)
            labs+=($lab_num)
        else
            log_message "ERROR" "  ✗ Template not found: $template"
            failed=true
        fi
    done
    
    # Wait for all packaging jobs to complete and collect results
    local failed_labs=()
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local lab=${labs[$i]}
        
        if wait $pid; then
            log_message "INFO" "  ✓ Lab $lab packaged"
        else
            log_message "ERROR" "  ✗ Lab $lab packaging failed"
            failed_labs+=($lab)
            failed=true
        fi
    done
    
    echo ""
    
    if [[ "$failed" == true ]]; then
        log_message "ERROR" "Some templates failed to package: ${failed_labs[*]}"
        return 1
    fi
    
    # Now collect the URLs from the log files
    LAB1_URL=$(grep "^https://" "$LOG_DIR/package-lab-1.log" 2>/dev/null | tail -1)
    LAB2_URL=$(grep "^https://" "$LOG_DIR/package-lab-2.log" 2>/dev/null | tail -1)
    LAB3_URL=$(grep "^https://" "$LOG_DIR/package-lab-3.log" 2>/dev/null | tail -1)
    LAB3T_URL=$(grep "^https://" "$LOG_DIR/package-lab-3t.log" 2>/dev/null | tail -1)
    LAB4_URL=$(grep "^https://" "$LOG_DIR/package-lab-4.log" 2>/dev/null | tail -1)
    LAB4T_URL=$(grep "^https://" "$LOG_DIR/package-lab-4t.log" 2>/dev/null | tail -1)
    LAB5_URL=$(grep "^https://" "$LOG_DIR/package-lab-5.log" 2>/dev/null | tail -1)
    LAB6_URL=$(grep "^https://" "$LOG_DIR/package-lab-6.log" 2>/dev/null | tail -1)
    LAB7_URL=$(grep "^https://" "$LOG_DIR/package-lab-7.log" 2>/dev/null | tail -1)
    LAB7P_URL=$(grep "^https://" "$LOG_DIR/package-lab-7p.log" 2>/dev/null | tail -1)
    
    # Export URLs for use in template generation
    export LAB1_URL LAB2_URL LAB3_URL LAB3T_URL LAB4_URL LAB4T_URL LAB5_URL LAB6_URL LAB7_URL LAB7P_URL
    
    log_message "INFO" "✓ All templates packaged successfully"
    return 0
}

# =============================================================================
# FRONTEND BUILD FUNCTIONS
# =============================================================================

build_frontend() {
    local lab_num=$1
    local client_dir=$2
    local api_gateway_url=$3
    
    # Skip if client directory doesn't exist (e.g., Lab7 has no frontend)
    if [[ ! -d "$client_dir" ]]; then
        echo "  ℹ Lab $lab_num has no frontend (client directory not found)" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Lab $lab_num has no frontend" >> "$LOG_FILE"
        return 0
    fi
    
    echo "  Building Lab $lab_num frontend..." >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Building Lab $lab_num frontend..." >> "$LOG_FILE"
    
    # Save current directory
    local original_dir=$(pwd)
    
    # Navigate to client directory
    cd "$client_dir" || {
        echo "  ✗ Could not navigate to client directory: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Could not navigate to $client_dir" >> "$LOG_FILE"
        return 1
    }
    
    # Check if Node.js is installed
    if ! command -v npm &> /dev/null; then
        echo "  ✗ npm is not installed" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   npm not found for Lab $lab_num" >> "$LOG_FILE"
        cd "$original_dir"
        return 1
    fi
    
    # NOTE: Environment files are configured by the specific configure_* functions
    # (configure_lab1_environment, configure_lab2_admin_environment, configure_labs36_admin_environment, etc.)
    # before build_frontend is called. Do NOT overwrite them here.
    
    # Clean previous npm installation to avoid stale dependencies
    echo "  Cleaning previous npm installation..." >&2
    rm -rf node_modules package-lock.json || true
    
    # Install dependencies
    echo "  Installing npm dependencies..." >&2
    if ! npm install >> "$LOG_FILE" 2>&1; then
        echo "  ✗ npm install failed for Lab $lab_num" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   npm install failed for Lab $lab_num" >> "$LOG_FILE"
        cd "$original_dir"
        return 1
    fi
    
    # Build Angular application using direct ng.js path (avoids Node.js compatibility issues)
    echo "  Building Angular application..." >&2
    if ! node node_modules/@angular/cli/bin/ng.js build >> "$LOG_FILE" 2>&1; then
        echo "  ✗ Angular build failed for Lab $lab_num" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Angular build failed for Lab $lab_num" >> "$LOG_FILE"
        cd "$original_dir"
        return 1
    fi
    
    echo "  ✓ Lab $lab_num frontend built" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab $lab_num frontend built" >> "$LOG_FILE"
    
    # Return to original directory
    cd "$original_dir"
    return 0
}

upload_frontend_to_s3() {
    local lab_num=$1
    local client_dir=$2
    local s3_bucket=$3
    
    # Skip if client directory doesn't exist (e.g., Lab7 has no frontend)
    if [[ ! -d "$client_dir" ]]; then
        echo "  ℹ Lab $lab_num has no frontend (client directory not found)" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Lab $lab_num has no frontend" >> "$LOG_FILE"
        return 0
    fi
    
    # Check if dist directory exists
    local dist_dir="$client_dir/dist"
    if [[ ! -d "$dist_dir" ]]; then
        echo "  ✗ dist directory not found for Lab $lab_num: $dist_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   dist directory not found for Lab $lab_num" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Uploading Lab $lab_num frontend to S3..." >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Uploading Lab $lab_num frontend to S3..." >> "$LOG_FILE"
    
    # Upload to S3 with cache control headers
    # --delete removes old assets from S3
    # --cache-control no-store prevents browser caching of old versions
    if ! aws s3 sync --delete --cache-control no-store "$dist_dir" "s3://${s3_bucket}" \
        --profile "$PROFILE" --region "$REGION" >> "$LOG_FILE" 2>&1; then
        echo "  ✗ Failed to upload Lab $lab_num frontend to S3" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Failed to upload Lab $lab_num frontend to S3" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  ✓ Lab $lab_num frontend uploaded to S3" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab $lab_num frontend uploaded to S3" >> "$LOG_FILE"
    return 0
}

# =============================================================================
# Lab 2 Admin Environment Configuration
# Lab 2 Admin uses apiUrl (not apiGatewayUrl) and aws-exports.ts for Cognito
# =============================================================================
configure_lab2_admin_environment() {
    local client_dir=$1
    local api_url=$2
    local user_pool_id=$3
    local client_id=$4
    local region=$5
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab 2 Admin client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab 2 Admin client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab 2 Admin environment..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Create environment.ts with apiUrl (Lab 2 Admin uses apiUrl, not apiGatewayUrl)
    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiUrl: '$api_url'
};
EoF

    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiUrl: '$api_url'
};
EoF

    # Create aws-exports.ts for Cognito configuration (AWS Amplify)
    cat <<EoF >./src/aws-exports.ts
const awsmobile = {
    "aws_project_region": "$region",
    "aws_cognito_region": "$region",
    "aws_user_pools_id": "$user_pool_id",
    "aws_user_pools_web_client_id": "$client_id",
};

export default awsmobile;
EoF

    echo "  ✓ Lab 2 Admin environment configured" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab 2 Admin environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

# =============================================================================
# Lab 2 Landing Environment Configuration
# Lab 2 Landing uses apiGatewayUrl (no Cognito - public signup page)
# =============================================================================
configure_lab2_landing_environment() {
    local client_dir=$1
    local api_url=$2
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab 2 Landing client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab 2 Landing client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab 2 Landing environment..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Create environment.ts with apiGatewayUrl (Lab 2 Landing uses apiGatewayUrl)
    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiGatewayUrl: '$api_url'
};
EoF

    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_url'
};
EoF

    echo "  ✓ Lab 2 Landing environment configured" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab 2 Landing environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

# =============================================================================
# Labs 3-6 Admin Environment Configuration
# Labs 3-6 Admin apps use apiUrl (not apiGatewayUrl) and aws-exports.ts for Cognito
# Same pattern as Lab 2 Admin
# =============================================================================
configure_labs36_admin_environment() {
    local lab_num=$1
    local client_dir=$2
    local api_url=$3
    local user_pool_id=$4
    local client_id=$5
    local region=$6
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab $lab_num Admin client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab $lab_num Admin client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab $lab_num Admin environment..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Create environment.ts with apiUrl (Labs 3-6 Admin use apiUrl, not apiGatewayUrl)
    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiUrl: '$api_url'
};
EoF

    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiUrl: '$api_url'
};
EoF

    # Create aws-exports.ts for Cognito configuration (AWS Amplify)
    cat <<EoF >./src/aws-exports.ts
const awsmobile = {
    "aws_project_region": "$region",
    "aws_cognito_region": "$region",
    "aws_user_pools_id": "$user_pool_id",
    "aws_user_pools_web_client_id": "$client_id",
};

export default awsmobile;
EoF

    echo "  ✓ Lab $lab_num Admin environment configured" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab $lab_num Admin environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

# =============================================================================
# Labs 3-6 Landing Environment Configuration
# Labs 3-6 Landing apps use apiGatewayUrl (no Cognito - public signup page)
# Same pattern as Lab 2 Landing
# =============================================================================
configure_labs36_landing_environment() {
    local lab_num=$1
    local client_dir=$2
    local api_url=$3
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab $lab_num Landing client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab $lab_num Landing client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab $lab_num Landing environment..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Create environment.ts with apiGatewayUrl (Labs 3-6 Landing use apiGatewayUrl)
    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: false,
  apiGatewayUrl: '$api_url'
};
EoF

    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_url'
};
EoF

    echo "  ✓ Lab $lab_num Landing environment configured" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab $lab_num Landing environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

# =============================================================================
# Lab 3 Application Environment Configuration
# Lab 3 Application needs BOTH regApiGatewayUrl (admin API for tenant init)
# AND apiGatewayUrl (tenant API for /products, /orders endpoints)
# =============================================================================
configure_lab3_app_environment() {
    local client_dir=$1
    local reg_api_url=$2
    local tenant_api_url=$3
    local user_pool_id=$4
    local client_id=$5
    local region=$6
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab 3 App client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab 3 App client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab 3 App environment (with tenant API)..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Lab 3 App needs:
    # - regApiGatewayUrl: Admin API (for /tenant/init/{tenantName} to get tenant config)
    # - apiGatewayUrl: Tenant API (for /products, /orders business endpoints)
    # - userPoolId, appClientId: Pre-populated so the app can authenticate immediately
    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$reg_api_url',
  userPoolId: '$user_pool_id',
  appClientId: '$client_id',
  apiGatewayUrl: '$tenant_api_url'
};
EoF

    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$reg_api_url',
  userPoolId: '$user_pool_id',
  appClientId: '$client_id',
  apiGatewayUrl: '$tenant_api_url'
};
EoF

    echo "  ✓ Lab 3 App environment configured (tenant API: $tenant_api_url)" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab 3 App environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

# =============================================================================
# Lab 4 Application needs BOTH regApiGatewayUrl (admin API for tenant init)
# AND apiGatewayUrl (tenant API for /products, /orders endpoints)
# =============================================================================
configure_lab4_app_environment() {
    local client_dir=$1
    local reg_api_url=$2
    local tenant_api_url=$3
    local user_pool_id=$4
    local client_id=$5
    local region=$6
    
    if [[ ! -d "$client_dir" ]]; then
        echo "  ✗ Lab 4 App client directory not found: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Lab 4 App client directory not found" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  Configuring Lab 4 App environment (with tenant API)..." >&2
    
    local original_dir=$(pwd)
    cd "$client_dir" || return 1
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Lab 4 App needs:
    # - regApiGatewayUrl: Admin API (for /tenant/init/{tenantName} to get tenant config)
    # - apiGatewayUrl: Tenant API (for /products, /orders business endpoints)
    # - userPoolId, appClientId: Pre-populated so the app can authenticate immediately
    cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$reg_api_url',
  userPoolId: '$user_pool_id',
  appClientId: '$client_id',
  apiGatewayUrl: '$tenant_api_url'
};
EoF

    cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$reg_api_url',
  userPoolId: '$user_pool_id',
  appClientId: '$client_id',
  apiGatewayUrl: '$tenant_api_url'
};
EoF

    echo "  ✓ Lab 4 App environment configured (tenant API: $tenant_api_url)" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Lab 4 App environment configured" >> "$LOG_FILE"
    
    cd "$original_dir"
    return 0
}

invalidate_cloudfront() {
    local lab_num=$1
    local stack_name=$2
    local output_key=$3
    
    echo "  Invalidating CloudFront cache for Lab $lab_num..." >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Invalidating CloudFront cache for Lab $lab_num..." >> "$LOG_FILE"
    
    # Retrieve CloudFront distribution ID from CloudFormation outputs
    local distribution_id=$(aws cloudformation describe-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    # Skip if distribution ID not found (lab may not have CloudFront)
    if [[ -z "$distribution_id" ]] || [[ "$distribution_id" == "None" ]]; then
        echo "  ℹ Lab $lab_num has no CloudFront distribution (output not found)" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Lab $lab_num has no CloudFront distribution" >> "$LOG_FILE"
        return 0
    fi
    
    # Create CloudFront invalidation for all paths
    if ! aws cloudfront create-invalidation \
        --profile "$PROFILE" \
        --distribution-id "$distribution_id" \
        --paths "/*" >> "$LOG_FILE" 2>&1; then
        echo "  ✗ Failed to create CloudFront invalidation for Lab $lab_num" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Failed to create CloudFront invalidation for Lab $lab_num" >> "$LOG_FILE"
        return 1
    fi
    
    echo "  ✓ CloudFront cache invalidated for Lab $lab_num" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ CloudFront cache invalidated for Lab $lab_num" >> "$LOG_FILE"
    return 0
}

configure_frontend_environment() {
    local lab_num=$1
    local client_dir=$2
    local api_gateway_url=$3
    local cognito_user_pool_id=${4:-}
    local cognito_client_id=${5:-}
    local cognito_region=${6:-}
    
    # Skip if client directory doesn't exist (e.g., Lab7 has no frontend)
    if [[ ! -d "$client_dir" ]]; then
        echo "  ℹ Lab $lab_num has no frontend (client directory not found)" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Lab $lab_num has no frontend" >> "$LOG_FILE"
        return 0
    fi
    
    echo "  Configuring environment for Lab $lab_num..." >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   Configuring environment for Lab $lab_num..." >> "$LOG_FILE"
    
    # Save current directory
    local original_dir=$(pwd)
    
    # Navigate to client directory
    cd "$client_dir" || {
        echo "  ✗ Could not navigate to client directory: $client_dir" >&2
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Could not navigate to $client_dir" >> "$LOG_FILE"
        return 1
    }
    
    # Create environments directory if it doesn't exist
    mkdir -p ./src/environments
    
    # Create environment files based on lab configuration
    # IMPORTANT: Labs 1-2 use 'apiGatewayUrl', Labs 3-6 use 'regApiGatewayUrl'
    # This is because Labs 3-6 have tenant-aware frontends that fetch tenant config
    # from the registration API (regApiGatewayUrl) before authenticating
    
    case $lab_num in
        1)
            # Lab 1: Simple API Gateway URL only (uses apiGatewayUrl)
            echo "  Creating environment files with apiGatewayUrl..." >&2
            
            cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_gateway_url'
};
EoF

            cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_gateway_url'
};
EoF
            ;;
        2)
            # Lab 2: Admin app with Cognito (uses apiGatewayUrl)
            echo "  Creating environment files with apiGatewayUrl and Cognito..." >&2
            
            cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_gateway_url',
  cognito: {
    userPoolId: '$cognito_user_pool_id',
    clientId: '$cognito_client_id',
    region: '$cognito_region'
  }
};
EoF

            cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$api_gateway_url',
  cognito: {
    userPoolId: '$cognito_user_pool_id',
    clientId: '$cognito_client_id',
    region: '$cognito_region'
  }
};
EoF
            ;;
        3|4|5|6)
            # Labs 3-6: Tenant-aware apps (use regApiGatewayUrl)
            # These apps call /tenant/init/{tenantName} to get tenant-specific config
            # Note: userPoolId, appClientId, apiGatewayUrl are optional - they're fetched dynamically
            # but must be declared in the interface for TypeScript compilation
            echo "  Creating environment files with regApiGatewayUrl..." >&2
            
            cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$api_gateway_url',
  // Optional: These are fetched dynamically via /tenant/init/{tenantName}
  // but declared here for TypeScript interface compatibility
  userPoolId: '',
  appClientId: '',
  apiGatewayUrl: ''
};
EoF

            cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  regApiGatewayUrl: '$api_gateway_url',
  // Optional: These are fetched dynamically via /tenant/init/{tenantName}
  // but declared here for TypeScript interface compatibility
  userPoolId: '',
  appClientId: '',
  apiGatewayUrl: ''
};
EoF
            ;;
        *)
            echo "  ✗ Unknown lab number: $lab_num" >&2
            echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR]   Unknown lab number: $lab_num" >> "$LOG_FILE"
            cd "$original_dir"
            return 1
            ;;
    esac
    
    echo "  ✓ Environment files configured for Lab $lab_num" >&2
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]   ✓ Environment files configured for Lab $lab_num" >> "$LOG_FILE"
    
    # Return to original directory
    cd "$original_dir"
    return 0
}

# =============================================================================
# PARALLEL FRONTEND BUILD HELPER
# =============================================================================
# Builds a single frontend in a subshell, capturing output to a log file
# Returns 0 on success, 1 on failure
# =============================================================================
build_single_frontend() {
    local frontend_id=$1      # e.g., "1", "2-Admin", "3-Landing"
    local client_dir=$2
    local s3_bucket=$3
    local api_url=$4
    local config_func=$5      # Configuration function name
    local config_args=$6      # Additional config args (pipe-separated)
    local stack_name=$7
    local cf_output_key=$8    # CloudFront distribution output key
    local log_file="$LOG_DIR/frontend-${frontend_id}.log"
    
    {
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting frontend build: $frontend_id"
        echo "  Client dir: $client_dir"
        echo "  S3 bucket: $s3_bucket"
        echo "  API URL: $api_url"
        
        # Skip if client directory doesn't exist
        if [[ ! -d "$client_dir" ]]; then
            echo "  ℹ Frontend $frontend_id has no client directory (skipping)"
            exit 0
        fi
        
        # Run configuration function if specified
        if [[ -n "$config_func" ]] && [[ "$config_func" != "none" ]]; then
            echo "  Running configuration: $config_func"
            # Parse pipe-separated args
            IFS='|' read -ra ARGS <<< "$config_args"
            case "$config_func" in
                configure_frontend_environment)
                    configure_frontend_environment "${ARGS[@]}" || { echo "  ✗ Configuration failed"; exit 1; }
                    ;;
                configure_lab2_admin_environment)
                    configure_lab2_admin_environment "${ARGS[@]}" || { echo "  ✗ Configuration failed"; exit 1; }
                    ;;
                configure_lab2_landing_environment)
                    configure_lab2_landing_environment "${ARGS[@]}" || { echo "  ✗ Configuration failed"; exit 1; }
                    ;;
                configure_labs36_admin_environment)
                    configure_labs36_admin_environment "${ARGS[@]}" || { echo "  ✗ Configuration failed"; exit 1; }
                    ;;
                configure_labs36_landing_environment)
                    configure_labs36_landing_environment "${ARGS[@]}" || { echo "  ✗ Configuration failed"; exit 1; }
                    ;;
            esac
        fi
        
        # Build frontend
        echo "  Building frontend..."
        build_frontend "$frontend_id" "$client_dir" "$api_url" || { echo "  ✗ Build failed"; exit 1; }
        
        # Upload to S3
        echo "  Uploading to S3..."
        upload_frontend_to_s3 "$frontend_id" "$client_dir" "$s3_bucket" || { echo "  ✗ Upload failed"; exit 1; }
        
        # Invalidate CloudFront (if output key provided)
        if [[ -n "$cf_output_key" ]] && [[ "$cf_output_key" != "none" ]]; then
            echo "  Invalidating CloudFront cache..."
            invalidate_cloudfront "$frontend_id" "$stack_name" "$cf_output_key" || echo "  ⚠ CloudFront invalidation failed (non-fatal)"
        fi
        
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ✓ Frontend $frontend_id completed successfully"
        exit 0
    } > "$log_file" 2>&1
    
    return $?
}

deploy_frontends() {
    log_message "INFO" "========================================"
    log_message "INFO" "Deploying Frontend Applications (Parallel)"
    log_message "INFO" "========================================"
    echo ""
    
    local MAX_PARALLEL=${MAX_PARALLEL:-4}
    log_message "INFO" "Max parallel builds: $MAX_PARALLEL"
    echo ""
    
    local failed_frontends=()
    local deployed_frontends=()
    local skipped_frontends=()
    declare -a pids=()
    declare -a frontend_names=()
    declare -a log_files=()
    
    # =========================================================================
    # PHASE 1: Collect all CloudFormation outputs (PARALLEL - 6 API calls instead of ~60)
    # =========================================================================
    log_message "INFO" "Phase 1: Collecting CloudFormation outputs (parallel)..."
    
    # Helper function to extract output value from JSON using grep/sed (no jq dependency)
    get_output_value() {
        local json_file=$1
        local output_key=$2
        if [[ -f "$json_file" ]]; then
            # Use grep and sed to extract value - works without jq
            grep -A1 "\"OutputKey\": \"$output_key\"" "$json_file" 2>/dev/null | \
                grep "OutputValue" | \
                sed 's/.*"OutputValue": "\([^"]*\)".*/\1/' | \
                head -1
        fi
    }
    
    # Helper function to fetch all outputs for a lab stack in background
    fetch_lab_outputs() {
        local lab_num=$1
        local stack_name=$2
        local output_file="$LOG_DIR/outputs-lab${lab_num}.json"
        
        if [[ -n "$stack_name" ]]; then
            aws cloudformation describe-stacks \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$stack_name" \
                --query "Stacks[0].Outputs" \
                --output json > "$output_file" 2>/dev/null || echo "[]" > "$output_file"
        else
            echo "[]" > "$output_file"
        fi
    }
    
    # Get all lab stack names first (fast - just string operations)
    local lab1_stack=$(get_main_lab_stack "${STACK_NAME}-Lab1Stack")
    local lab2_stack=$(get_main_lab_stack "${STACK_NAME}-Lab2Stack")
    local lab3_stack=$(get_main_lab_stack "${STACK_NAME}-Lab3Stack")
    local lab3t_stack=$(get_main_lab_stack "${STACK_NAME}-Lab3TenantStack")
    local lab4_stack=$(get_main_lab_stack "${STACK_NAME}-Lab4Stack")
    local lab4t_stack=$(get_main_lab_stack "${STACK_NAME}-Lab4TenantStack")
    local lab5_stack=$(get_main_lab_stack "${STACK_NAME}-Lab5Stack")
    local lab6_stack=$(get_main_lab_stack "${STACK_NAME}-Lab6Stack")
    
    # Fetch all outputs in PARALLEL (7 API calls running simultaneously)
    log_message "INFO" "  Fetching outputs for Labs 1-6 in parallel..."
    fetch_lab_outputs 1 "$lab1_stack" &
    fetch_lab_outputs 2 "$lab2_stack" &
    fetch_lab_outputs 3 "$lab3_stack" &
    fetch_lab_outputs "3t" "$lab3t_stack" &
    fetch_lab_outputs 4 "$lab4_stack" &
    fetch_lab_outputs "4t" "$lab4t_stack" &
    fetch_lab_outputs 5 "$lab5_stack" &
    fetch_lab_outputs 6 "$lab6_stack" &
    wait
    log_message "INFO" "  ✓ All outputs fetched"
    
    # Parse Lab 1 outputs (local - instant)
    local lab1_api_url="" lab1_bucket="" lab1_cf_dist=""
    if [[ -n "$lab1_stack" ]]; then
        lab1_api_url=$(get_output_value "$LOG_DIR/outputs-lab1.json" "APIGatewayURL")
        lab1_bucket=$(get_output_value "$LOG_DIR/outputs-lab1.json" "AppBucket")
        lab1_cf_dist=$(get_output_value "$LOG_DIR/outputs-lab1.json" "DistributionId")
    fi
    
    # Parse Lab 2 outputs (local - instant)
    local lab2_api_url="" lab2_admin_bucket="" lab2_landing_bucket="" lab2_user_pool="" lab2_client_id=""
    local lab2_admin_cf="" lab2_landing_cf=""
    if [[ -n "$lab2_stack" ]]; then
        lab2_api_url=$(get_output_value "$LOG_DIR/outputs-lab2.json" "AdminApi")
        lab2_admin_bucket=$(get_output_value "$LOG_DIR/outputs-lab2.json" "AdminSiteBucket")
        lab2_landing_bucket=$(get_output_value "$LOG_DIR/outputs-lab2.json" "LandingApplicationSiteBucket")
        lab2_user_pool=$(get_output_value "$LOG_DIR/outputs-lab2.json" "CognitoOperationUsersUserPoolId")
        lab2_client_id=$(get_output_value "$LOG_DIR/outputs-lab2.json" "CognitoOperationUsersUserPoolClientId")
        lab2_admin_cf=$(get_output_value "$LOG_DIR/outputs-lab2.json" "AdminDistributionId")
        lab2_landing_cf=$(get_output_value "$LOG_DIR/outputs-lab2.json" "LandingDistributionId")
    fi
    
    # Parse Lab 3 outputs (local - instant)
    local lab3_api_url="" lab3_app_bucket="" lab3_admin_bucket="" lab3_landing_bucket=""
    local lab3_ops_user_pool="" lab3_ops_client_id="" lab3_tenant_user_pool="" lab3_tenant_client_id=""
    local lab3_admin_cf="" lab3_app_cf="" lab3_landing_cf=""
    if [[ -n "$lab3_stack" ]]; then
        lab3_api_url=$(get_output_value "$LOG_DIR/outputs-lab3.json" "AdminApi")
        lab3_app_bucket=$(get_output_value "$LOG_DIR/outputs-lab3.json" "ApplicationSiteBucket")
        lab3_admin_bucket=$(get_output_value "$LOG_DIR/outputs-lab3.json" "AdminSiteBucket")
        lab3_landing_bucket=$(get_output_value "$LOG_DIR/outputs-lab3.json" "LandingApplicationSiteBucket")
        lab3_ops_user_pool=$(get_output_value "$LOG_DIR/outputs-lab3.json" "CognitoOperationUsersUserPoolId")
        lab3_ops_client_id=$(get_output_value "$LOG_DIR/outputs-lab3.json" "CognitoOperationUsersUserPoolClientId")
        lab3_tenant_user_pool=$(get_output_value "$LOG_DIR/outputs-lab3.json" "CognitoTenantUserPoolId")
        lab3_tenant_client_id=$(get_output_value "$LOG_DIR/outputs-lab3.json" "CognitoTenantAppClientId")
        lab3_admin_cf=$(get_output_value "$LOG_DIR/outputs-lab3.json" "AdminDistributionId")
        lab3_app_cf=$(get_output_value "$LOG_DIR/outputs-lab3.json" "DistributionId")
        lab3_landing_cf=$(get_output_value "$LOG_DIR/outputs-lab3.json" "LandingDistributionId")
    fi
    
    # Parse Lab 3 Tenant outputs (local - instant)
    local lab3_tenant_api_url=""
    if [[ -n "$lab3t_stack" ]]; then
        lab3_tenant_api_url=$(get_output_value "$LOG_DIR/outputs-lab3t.json" "TenantAPI")
    fi
    
    # Parse Lab 4 outputs (local - instant)
    local lab4_api_url="" lab4_app_bucket="" lab4_admin_bucket="" lab4_landing_bucket=""
    local lab4_ops_user_pool="" lab4_ops_client_id="" lab4_tenant_user_pool="" lab4_tenant_client_id=""
    local lab4_admin_cf="" lab4_app_cf="" lab4_landing_cf=""
    if [[ -n "$lab4_stack" ]]; then
        lab4_api_url=$(get_output_value "$LOG_DIR/outputs-lab4.json" "AdminApi")
        lab4_app_bucket=$(get_output_value "$LOG_DIR/outputs-lab4.json" "ApplicationSiteBucket")
        lab4_admin_bucket=$(get_output_value "$LOG_DIR/outputs-lab4.json" "AdminSiteBucket")
        lab4_landing_bucket=$(get_output_value "$LOG_DIR/outputs-lab4.json" "LandingApplicationSiteBucket")
        lab4_ops_user_pool=$(get_output_value "$LOG_DIR/outputs-lab4.json" "CognitoOperationUsersUserPoolId")
        lab4_ops_client_id=$(get_output_value "$LOG_DIR/outputs-lab4.json" "CognitoOperationUsersUserPoolClientId")
        lab4_tenant_user_pool=$(get_output_value "$LOG_DIR/outputs-lab4.json" "CognitoTenantUserPoolId")
        lab4_tenant_client_id=$(get_output_value "$LOG_DIR/outputs-lab4.json" "CognitoTenantAppClientId")
        lab4_admin_cf=$(get_output_value "$LOG_DIR/outputs-lab4.json" "AdminDistributionId")
        lab4_app_cf=$(get_output_value "$LOG_DIR/outputs-lab4.json" "DistributionId")
        lab4_landing_cf=$(get_output_value "$LOG_DIR/outputs-lab4.json" "LandingDistributionId")
    fi
    
    # Parse Lab 4 Tenant outputs (local - instant)
    local lab4_tenant_api_url=""
    if [[ -n "$lab4t_stack" ]]; then
        lab4_tenant_api_url=$(get_output_value "$LOG_DIR/outputs-lab4t.json" "TenantAPI")
    fi
    
    # Parse Lab 5 outputs (local - instant)
    local lab5_api_url="" lab5_app_bucket="" lab5_admin_bucket="" lab5_landing_bucket=""
    local lab5_ops_user_pool="" lab5_ops_client_id="" lab5_tenant_user_pool="" lab5_tenant_client_id=""
    local lab5_admin_cf="" lab5_app_cf="" lab5_landing_cf=""
    if [[ -n "$lab5_stack" ]]; then
        lab5_api_url=$(get_output_value "$LOG_DIR/outputs-lab5.json" "AdminApi")
        lab5_app_bucket=$(get_output_value "$LOG_DIR/outputs-lab5.json" "AppBucket")
        lab5_admin_bucket=$(get_output_value "$LOG_DIR/outputs-lab5.json" "AdminSiteBucket")
        lab5_landing_bucket=$(get_output_value "$LOG_DIR/outputs-lab5.json" "LandingApplicationSiteBucket")
        lab5_ops_user_pool=$(get_output_value "$LOG_DIR/outputs-lab5.json" "CognitoOperationUsersUserPoolId")
        lab5_ops_client_id=$(get_output_value "$LOG_DIR/outputs-lab5.json" "CognitoOperationUsersUserPoolClientId")
        lab5_tenant_user_pool=$(get_output_value "$LOG_DIR/outputs-lab5.json" "CognitoTenantUserPoolId")
        lab5_tenant_client_id=$(get_output_value "$LOG_DIR/outputs-lab5.json" "CognitoTenantAppClientId")
        lab5_admin_cf=$(get_output_value "$LOG_DIR/outputs-lab5.json" "AdminDistributionId")
        lab5_app_cf=$(get_output_value "$LOG_DIR/outputs-lab5.json" "DistributionId")
        lab5_landing_cf=$(get_output_value "$LOG_DIR/outputs-lab5.json" "LandingDistributionId")
    fi
    
    # Parse Lab 6 outputs (local - instant)
    local lab6_api_url="" lab6_app_bucket="" lab6_admin_bucket="" lab6_landing_bucket=""
    local lab6_ops_user_pool="" lab6_ops_client_id="" lab6_tenant_user_pool="" lab6_tenant_client_id=""
    local lab6_admin_cf="" lab6_app_cf="" lab6_landing_cf=""
    if [[ -n "$lab6_stack" ]]; then
        lab6_api_url=$(get_output_value "$LOG_DIR/outputs-lab6.json" "AdminApi")
        lab6_app_bucket=$(get_output_value "$LOG_DIR/outputs-lab6.json" "ApplicationSiteBucket")
        lab6_admin_bucket=$(get_output_value "$LOG_DIR/outputs-lab6.json" "AdminSiteBucket")
        lab6_landing_bucket=$(get_output_value "$LOG_DIR/outputs-lab6.json" "LandingApplicationSiteBucket")
        lab6_ops_user_pool=$(get_output_value "$LOG_DIR/outputs-lab6.json" "CognitoOperationUsersUserPoolId")
        lab6_ops_client_id=$(get_output_value "$LOG_DIR/outputs-lab6.json" "CognitoOperationUsersUserPoolClientId")
        lab6_tenant_user_pool=$(get_output_value "$LOG_DIR/outputs-lab6.json" "CognitoTenantUserPoolId")
        lab6_tenant_client_id=$(get_output_value "$LOG_DIR/outputs-lab6.json" "CognitoTenantAppClientId")
        lab6_admin_cf=$(get_output_value "$LOG_DIR/outputs-lab6.json" "AdminDistributionId")
        lab6_app_cf=$(get_output_value "$LOG_DIR/outputs-lab6.json" "DistributionId")
        lab6_landing_cf=$(get_output_value "$LOG_DIR/outputs-lab6.json" "LandingDistributionId")
    fi
    
    log_message "INFO" "✓ CloudFormation outputs collected"
    echo ""

    # =========================================================================
    # PHASE 2: Build job queue with all frontend configurations
    # =========================================================================
    log_message "INFO" "Phase 2: Building frontend job queue..."
    
    # Job queue format: "frontend_id|client_dir|s3_bucket|api_url|config_type|config_args|stack_name|cf_dist"
    # config_type: lab1, lab2_admin, lab2_landing, lab36_admin, lab36_app, lab36_landing
    declare -a job_queue=()
    
    # Lab 1 frontend (1 frontend)
    if [[ -n "$lab1_api_url" ]] && [[ "$lab1_api_url" != "None" ]] && [[ -n "$lab1_bucket" ]]; then
        job_queue+=("Lab1|$WORKSHOP_ROOT/Lab1/client/Application|$lab1_bucket|$lab1_api_url|lab1|1|$lab1_stack|$lab1_cf_dist")
        log_message "DEBUG" "Queued: Lab1"
    else
        skipped_frontends+=("Lab1")
    fi
    
    # Lab 2 frontends (2 frontends: Admin, Landing)
    if [[ -n "$lab2_api_url" ]] && [[ "$lab2_api_url" != "None" ]]; then
        if [[ -n "$lab2_admin_bucket" ]]; then
            job_queue+=("Lab2-Admin|$WORKSHOP_ROOT/Lab2/client/Admin|$lab2_admin_bucket|$lab2_api_url|lab2_admin|$lab2_user_pool|$lab2_client_id|$lab2_stack|$lab2_admin_cf")
            log_message "DEBUG" "Queued: Lab2-Admin"
        fi
        if [[ -n "$lab2_landing_bucket" ]]; then
            job_queue+=("Lab2-Landing|$WORKSHOP_ROOT/Lab2/client/Landing|$lab2_landing_bucket|$lab2_api_url|lab2_landing||$lab2_stack|$lab2_landing_cf")
            log_message "DEBUG" "Queued: Lab2-Landing"
        fi
    else
        skipped_frontends+=("Lab2-Admin" "Lab2-Landing")
    fi
    
    # Lab 3 frontends (3 frontends: Admin, App, Landing)
    if [[ -n "$lab3_api_url" ]] && [[ "$lab3_api_url" != "None" ]]; then
        if [[ -n "$lab3_admin_bucket" ]]; then
            job_queue+=("Lab3-Admin|$WORKSHOP_ROOT/Lab3/client/Admin|$lab3_admin_bucket|$lab3_api_url|lab36_admin|3|$lab3_ops_user_pool|$lab3_ops_client_id|$lab3_stack|$lab3_admin_cf")
            log_message "DEBUG" "Queued: Lab3-Admin"
        fi
        if [[ -n "$lab3_app_bucket" ]]; then
            # Lab3-App uses lab3_app config type (NOT lab36_app) because it needs the tenant API URL
            # for apiGatewayUrl in addition to regApiGatewayUrl (admin API)
            job_queue+=("Lab3-App|$WORKSHOP_ROOT/Lab3/client/Application|$lab3_app_bucket|$lab3_api_url|lab3_app|3|$lab3_tenant_user_pool|$lab3_tenant_client_id|$lab3_tenant_api_url|$lab3_stack|$lab3_app_cf")
            log_message "DEBUG" "Queued: Lab3-App (tenant API: $lab3_tenant_api_url)"
        fi
        if [[ -n "$lab3_landing_bucket" ]]; then
            job_queue+=("Lab3-Landing|$WORKSHOP_ROOT/Lab3/client/Landing|$lab3_landing_bucket|$lab3_api_url|lab36_landing|3|$lab3_stack|$lab3_landing_cf")
            log_message "DEBUG" "Queued: Lab3-Landing"
        fi
    else
        skipped_frontends+=("Lab3-Admin" "Lab3-App" "Lab3-Landing")
    fi
    
    # Lab 4 frontends (3 frontends: Admin, App, Landing)
    if [[ -n "$lab4_api_url" ]] && [[ "$lab4_api_url" != "None" ]]; then
        if [[ -n "$lab4_admin_bucket" ]]; then
            job_queue+=("Lab4-Admin|$WORKSHOP_ROOT/Lab4/client/Admin|$lab4_admin_bucket|$lab4_api_url|lab36_admin|4|$lab4_ops_user_pool|$lab4_ops_client_id|$lab4_stack|$lab4_admin_cf")
            log_message "DEBUG" "Queued: Lab4-Admin"
        fi
        if [[ -n "$lab4_app_bucket" ]]; then
            # Lab4-App uses lab4_app config type (NOT lab36_app) because it needs the tenant API URL
            # for apiGatewayUrl in addition to regApiGatewayUrl (admin API)
            job_queue+=("Lab4-App|$WORKSHOP_ROOT/Lab4/client/Application|$lab4_app_bucket|$lab4_api_url|lab4_app|4|$lab4_tenant_user_pool|$lab4_tenant_client_id|$lab4_tenant_api_url|$lab4_stack|$lab4_app_cf")
            log_message "DEBUG" "Queued: Lab4-App (tenant API: $lab4_tenant_api_url)"
        fi
        if [[ -n "$lab4_landing_bucket" ]]; then
            job_queue+=("Lab4-Landing|$WORKSHOP_ROOT/Lab4/client/Landing|$lab4_landing_bucket|$lab4_api_url|lab36_landing|4|$lab4_stack|$lab4_landing_cf")
            log_message "DEBUG" "Queued: Lab4-Landing"
        fi
    else
        skipped_frontends+=("Lab4-Admin" "Lab4-App" "Lab4-Landing")
    fi
    
    # Lab 5 frontends (3 frontends: Admin, App, Landing)
    if [[ -n "$lab5_api_url" ]] && [[ "$lab5_api_url" != "None" ]]; then
        if [[ -n "$lab5_admin_bucket" ]]; then
            job_queue+=("Lab5-Admin|$WORKSHOP_ROOT/Lab5/client/Admin|$lab5_admin_bucket|$lab5_api_url|lab36_admin|5|$lab5_ops_user_pool|$lab5_ops_client_id|$lab5_stack|$lab5_admin_cf")
            log_message "DEBUG" "Queued: Lab5-Admin"
        fi
        if [[ -n "$lab5_app_bucket" ]]; then
            job_queue+=("Lab5-App|$WORKSHOP_ROOT/Lab5/client/Application|$lab5_app_bucket|$lab5_api_url|lab36_app|5|$lab5_tenant_user_pool|$lab5_tenant_client_id|$lab5_stack|$lab5_app_cf")
            log_message "DEBUG" "Queued: Lab5-App"
        fi
        if [[ -n "$lab5_landing_bucket" ]]; then
            job_queue+=("Lab5-Landing|$WORKSHOP_ROOT/Lab5/client/Landing|$lab5_landing_bucket|$lab5_api_url|lab36_landing|5|$lab5_stack|$lab5_landing_cf")
            log_message "DEBUG" "Queued: Lab5-Landing"
        fi
    else
        skipped_frontends+=("Lab5-Admin" "Lab5-App" "Lab5-Landing")
    fi
    
    # Lab 6 frontends (3 frontends: Admin, App, Landing)
    if [[ -n "$lab6_api_url" ]] && [[ "$lab6_api_url" != "None" ]]; then
        if [[ -n "$lab6_admin_bucket" ]]; then
            job_queue+=("Lab6-Admin|$WORKSHOP_ROOT/Lab6/client/Admin|$lab6_admin_bucket|$lab6_api_url|lab36_admin|6|$lab6_ops_user_pool|$lab6_ops_client_id|$lab6_stack|$lab6_admin_cf")
            log_message "DEBUG" "Queued: Lab6-Admin"
        fi
        if [[ -n "$lab6_app_bucket" ]]; then
            job_queue+=("Lab6-App|$WORKSHOP_ROOT/Lab6/client/Application|$lab6_app_bucket|$lab6_api_url|lab36_app|6|$lab6_tenant_user_pool|$lab6_tenant_client_id|$lab6_stack|$lab6_app_cf")
            log_message "DEBUG" "Queued: Lab6-App"
        fi
        if [[ -n "$lab6_landing_bucket" ]]; then
            job_queue+=("Lab6-Landing|$WORKSHOP_ROOT/Lab6/client/Landing|$lab6_landing_bucket|$lab6_api_url|lab36_landing|6|$lab6_stack|$lab6_landing_cf")
            log_message "DEBUG" "Queued: Lab6-Landing"
        fi
    else
        skipped_frontends+=("Lab6-Admin" "Lab6-App" "Lab6-Landing")
    fi
    
    local total_jobs=${#job_queue[@]}
    log_message "INFO" "✓ Job queue built: $total_jobs frontends to deploy"
    if [[ ${#skipped_frontends[@]} -gt 0 ]]; then
        log_message "WARN" "  Skipped (no API URL): ${skipped_frontends[*]}"
    fi
    echo ""

    # =========================================================================
    # PHASE 3: Execute builds in parallel batches of MAX_PARALLEL
    # =========================================================================
    log_message "INFO" "Phase 3: Building and deploying frontends (max $MAX_PARALLEL parallel)..."
    echo ""
    
    # Helper function to process a single frontend job in background
    process_frontend_job() {
        local job=$1
        local job_log=$2
        
        # Parse job string (pipe-separated)
        IFS='|' read -ra parts <<< "$job"
        local frontend_id="${parts[0]}"
        local client_dir="${parts[1]}"
        local s3_bucket="${parts[2]}"
        local api_url="${parts[3]}"
        local config_type="${parts[4]}"
        
        {
            echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting: $frontend_id"
            echo "  Client dir: $client_dir"
            echo "  S3 bucket: $s3_bucket"
            echo "  API URL: $api_url"
            echo "  Config type: $config_type"
            
            # Check if client directory exists
            if [[ ! -d "$client_dir" ]]; then
                echo "  ⚠ Client directory not found, skipping"
                exit 0
            fi
            
            # Configure environment based on config_type
            case "$config_type" in
                lab1)
                    local lab_num="${parts[5]}"
                    configure_frontend_environment "$lab_num" "$client_dir" "$api_url" "" "" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab2_admin)
                    local user_pool="${parts[5]}"
                    local client_id="${parts[6]}"
                    configure_lab2_admin_environment "$client_dir" "$api_url" "$user_pool" "$client_id" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab2_landing)
                    configure_lab2_landing_environment "$client_dir" "$api_url" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab36_admin)
                    local lab_num="${parts[5]}"
                    local user_pool="${parts[6]}"
                    local client_id="${parts[7]}"
                    configure_labs36_admin_environment "$lab_num" "$client_dir" "$api_url" "$user_pool" "$client_id" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab36_app)
                    local lab_num="${parts[5]}"
                    local user_pool="${parts[6]}"
                    local client_id="${parts[7]}"
                    configure_frontend_environment "$lab_num" "$client_dir" "$api_url" "$user_pool" "$client_id" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab3_app)
                    # Lab3-App needs BOTH regApiGatewayUrl (admin API) AND apiGatewayUrl (tenant API)
                    local lab_num="${parts[5]}"
                    local user_pool="${parts[6]}"
                    local client_id="${parts[7]}"
                    local tenant_api_url="${parts[8]}"
                    configure_lab3_app_environment "$client_dir" "$api_url" "$tenant_api_url" "$user_pool" "$client_id" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab4_app)
                    # Lab4-App needs BOTH regApiGatewayUrl (admin API) AND apiGatewayUrl (tenant API)
                    local lab_num="${parts[5]}"
                    local user_pool="${parts[6]}"
                    local client_id="${parts[7]}"
                    local tenant_api_url="${parts[8]}"
                    configure_lab4_app_environment "$client_dir" "$api_url" "$tenant_api_url" "$user_pool" "$client_id" "$REGION" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
                lab36_landing)
                    local lab_num="${parts[5]}"
                    configure_labs36_landing_environment "$lab_num" "$client_dir" "$api_url" || { echo "  ✗ Config failed"; exit 1; }
                    ;;
            esac
            
            echo "  ✓ Environment configured"
            
            # Build frontend
            echo "  Building..."
            build_frontend "$frontend_id" "$client_dir" "$api_url" || { echo "  ✗ Build failed"; exit 1; }
            echo "  ✓ Build complete"
            
            # Upload to S3
            echo "  Uploading to S3..."
            upload_frontend_to_s3 "$frontend_id" "$client_dir" "$s3_bucket" || { echo "  ✗ Upload failed"; exit 1; }
            echo "  ✓ Upload complete"
            
            # Get CloudFront distribution ID and invalidate
            local stack_name cf_dist
            case "$config_type" in
                lab1)
                    stack_name="${parts[6]}"
                    cf_dist="${parts[7]}"
                    ;;
                lab2_admin|lab2_landing)
                    stack_name="${parts[7]}"
                    cf_dist="${parts[8]}"
                    ;;
                lab36_admin|lab36_app)
                    stack_name="${parts[8]}"
                    cf_dist="${parts[9]}"
                    ;;
                lab3_app)
                    stack_name="${parts[9]}"
                    cf_dist="${parts[10]}"
                    ;;
                lab4_app)
                    stack_name="${parts[9]}"
                    cf_dist="${parts[10]}"
                    ;;
                lab36_landing)
                    stack_name="${parts[6]}"
                    cf_dist="${parts[7]}"
                    ;;
            esac
            
            if [[ -n "$cf_dist" ]] && [[ "$cf_dist" != "None" ]]; then
                echo "  Invalidating CloudFront cache..."
                aws cloudfront create-invalidation \
                    --profile "$PROFILE" \
                    --distribution-id "$cf_dist" \
                    --paths "/*" > /dev/null 2>&1 || echo "  ⚠ CloudFront invalidation failed (non-fatal)"
                echo "  ✓ CloudFront invalidated"
            fi
            
            echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ✓ $frontend_id completed successfully"
            exit 0
        } > "$job_log" 2>&1
        
        return $?
    }
    
    # Process jobs in batches
    local job_index=0
    local completed=0
    local batch_num=0
    
    while [[ $job_index -lt $total_jobs ]]; do
        ((batch_num++))
        local batch_size=0
        pids=()
        frontend_names=()
        log_files=()
        
        # Start up to MAX_PARALLEL jobs
        while [[ $batch_size -lt $MAX_PARALLEL ]] && [[ $job_index -lt $total_jobs ]]; do
            local job="${job_queue[$job_index]}"
            local frontend_id=$(echo "$job" | cut -d'|' -f1)
            local job_log="$LOG_DIR/frontend-${frontend_id}.log"
            
            log_message "INFO" "  Starting: $frontend_id"
            
            # Run in background
            process_frontend_job "$job" "$job_log" &
            local pid=$!
            
            pids+=($pid)
            frontend_names+=("$frontend_id")
            log_files+=("$job_log")
            
            ((job_index++))
            ((batch_size++))
        done
        
        log_message "INFO" "  Batch $batch_num: Waiting for ${#pids[@]} builds to complete..."
        
        # Wait for all jobs in this batch and collect results
        for i in "${!pids[@]}"; do
            local pid=${pids[$i]}
            local frontend_id=${frontend_names[$i]}
            local job_log=${log_files[$i]}
            
            wait $pid
            local exit_code=$?
            ((completed++))
            
            if [[ $exit_code -eq 0 ]]; then
                # Check if it was actually skipped
                if grep -q "skipping" "$job_log" 2>/dev/null; then
                    skipped_frontends+=("$frontend_id")
                    log_message "INFO" "    ⊘ $frontend_id (skipped - no client dir)"
                else
                    deployed_frontends+=("$frontend_id")
                    log_message "INFO" "    ✓ $frontend_id"
                fi
            else
                failed_frontends+=("$frontend_id")
                log_message "ERROR" "    ✗ $frontend_id (see $job_log)"
            fi
        done
        
        log_message "INFO" "  Batch $batch_num complete. Progress: $completed/$total_jobs"
        echo ""
    done

    # =========================================================================
    # PHASE 4: Summary
    # =========================================================================
    echo ""
    log_message "INFO" "========================================"
    log_message "INFO" "Frontend Deployment Summary"
    log_message "INFO" "========================================"
    log_message "INFO" "  Deployed: ${#deployed_frontends[@]}"
    for fe in "${deployed_frontends[@]}"; do
        log_message "INFO" "    ✓ $fe"
    done
    
    if [[ ${#skipped_frontends[@]} -gt 0 ]]; then
        log_message "INFO" "  Skipped: ${#skipped_frontends[@]}"
        for fe in "${skipped_frontends[@]}"; do
            log_message "INFO" "    ⊘ $fe"
        done
    fi
    
    if [[ ${#failed_frontends[@]} -gt 0 ]]; then
        log_message "ERROR" "  Failed: ${#failed_frontends[@]}"
        for fe in "${failed_frontends[@]}"; do
            log_message "ERROR" "    ✗ $fe"
            log_message "ERROR" "      Log: $LOG_DIR/frontend-${fe}.log"
        done
        return 1
    fi
    
    log_message "INFO" "✓ All frontends deployed successfully"
    return 0
}

# =============================================================================
# GENERATE ORCHESTRATION TEMPLATE
# =============================================================================

generate_orchestration_template() {
    log_message "INFO" "========================================"
    log_message "INFO" "Generating Orchestration Template"
    log_message "INFO" "========================================"
    echo ""
    
    local base_template="$ORCHESTRATION_DIR/main-template.yaml"
    local output_template="$LOG_DIR/orchestration-template.yaml"
    
    # Verify base template exists
    if [[ ! -f "$base_template" ]]; then
        log_message "ERROR" "Base template not found: $base_template"
        return 1
    fi
    
    log_message "INFO" "Using base template: $base_template"
    
    # Copy base template
    cp "$base_template" "$output_template"
    
    # Replace TemplateURL values with S3 URLs
    # Using | as delimiter since URLs contain /
    sed -i.bak \
        -e "s|TemplateURL: ../Lab1/server/template.yaml|TemplateURL: ${LAB1_URL}|g" \
        -e "s|TemplateURL: ../Lab2/server/template.yaml|TemplateURL: ${LAB2_URL}|g" \
        -e "s|TemplateURL: ../Lab3/server/shared-template.yaml|TemplateURL: ${LAB3_URL}|g" \
        -e "s|TemplateURL: ../Lab3/server/tenant-template.yaml|TemplateURL: ${LAB3T_URL}|g" \
        -e "s|TemplateURL: ../Lab4/server/shared-template.yaml|TemplateURL: ${LAB4_URL}|g" \
        -e "s|TemplateURL: ../Lab4/server/tenant-template.yaml|TemplateURL: ${LAB4T_URL}|g" \
        -e "s|TemplateURL: ../Lab5/server/shared-template.yaml|TemplateURL: ${LAB5_URL}|g" \
        -e "s|TemplateURL: ../Lab6/server/shared-template.yaml|TemplateURL: ${LAB6_URL}|g" \
        -e "s|TemplateURL: ../Lab7/template.yaml|TemplateURL: ${LAB7_URL}|g" \
        -e "s|TemplateURL: ../Lab7/tenant-template.yaml|TemplateURL: ${LAB7P_URL}|g" \
        "$output_template"
    
    # Remove backup file created by sed -i
    rm -f "${output_template}.bak"
    
    log_message "INFO" "✓ Orchestration template generated: $output_template"
    
    # Store the path in a global variable
    ORCHESTRATION_TEMPLATE_PATH="$output_template"
}

# =============================================================================
# GET FAILED NESTED STACKS
# =============================================================================
# Identifies which nested stacks failed during deployment.
# Returns a list of failed nested stack logical IDs and their status reasons.
# =============================================================================

get_failed_nested_stacks() {
    local parent_stack=$1
    
    log_message "INFO" "Analyzing failed resources..."
    
    # Get all resources in the stack
    local resources=$(aws cloudformation describe-stack-resources \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$parent_stack" \
        --query "StackResources[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED'].[LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]" \
        --output json 2>/dev/null)
    
    if [[ -z "$resources" ]] || [[ "$resources" == "[]" ]]; then
        log_message "INFO" "No failed resources found in parent stack"
        return 0
    fi
    
    log_message "INFO" ""
    log_message "INFO" "=== FAILED RESOURCES ==="
    
    # Parse and display failed resources
    echo "$resources" | jq -r '.[] | "  \(.[0]) (\(.[1])): \(.[2]) - \(.[3] // "No reason provided")"' 2>/dev/null | while read -r line; do
        log_message "ERROR" "$line"
    done
    
    # Check for nested stack failures specifically
    local nested_failures=$(echo "$resources" | jq -r '.[] | select(.[1]=="AWS::CloudFormation::Stack") | .[0]' 2>/dev/null)
    
    if [[ -n "$nested_failures" ]]; then
        log_message "INFO" ""
        log_message "INFO" "=== FAILED NESTED STACKS ==="
        for nested_id in $nested_failures; do
            log_message "ERROR" "  - $nested_id"
            
            # Get the physical resource ID (actual nested stack name)
            local nested_stack_name=$(aws cloudformation describe-stack-resource \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$parent_stack" \
                --logical-resource-id "$nested_id" \
                --query "StackResourceDetail.PhysicalResourceId" \
                --output text 2>/dev/null)
            
            if [[ -n "$nested_stack_name" ]] && [[ "$nested_stack_name" != "None" ]]; then
                # Get events from the nested stack to find root cause
                log_message "INFO" "    Nested stack: $nested_stack_name"
                local nested_events=$(aws cloudformation describe-stack-events \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --stack-name "$nested_stack_name" \
                    --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" \
                    --output json 2>/dev/null | jq -r '.[:3][] | "      → \(.[0]): \(.[1] // "No reason")"' 2>/dev/null)
                
                if [[ -n "$nested_events" ]]; then
                    echo "$nested_events" | while read -r event_line; do
                        log_message "ERROR" "$event_line"
                    done
                fi
            fi
        done
    fi
    
    log_message "INFO" ""
    
    return 0
}

# =============================================================================
# DEPLOY STACK WITH RETRY
# =============================================================================
# Deploys the CloudFormation stack with automatic retry on failure.
# This handles transient failures like CloudWatch Log Group race conditions.
#
# IMPROVED BEHAVIOR (February 2026):
# - Does NOT delete the entire stack on failure
# - Uses update-stack to retry failed resources (preserves successful ones)
# - Only deletes stack if in ROLLBACK_COMPLETE state (no other option)
# - Shows detailed information about which nested stacks failed
# =============================================================================

deploy_stack_with_retry() {
    local template_file=$1
    local max_retries=2
    local retry_count=0
    local retry_delay=30  # seconds between retries
    
    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))
        
        if [[ $retry_count -gt 1 ]]; then
            log_message "INFO" "========================================"
            log_message "INFO" "Retry Attempt $retry_count of $max_retries"
            log_message "INFO" "========================================"
            log_message "INFO" "Waiting ${retry_delay} seconds before retry..."
            sleep $retry_delay
            
            # Check current stack status to determine retry strategy
            local stack_status=$(aws cloudformation describe-stacks \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$STACK_NAME" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "DOES_NOT_EXIST")
            
            case "$stack_status" in
                ROLLBACK_COMPLETE)
                    # Stack rolled back completely - MUST delete and recreate
                    # This is the only state where we delete the stack
                    log_message "WARN" "Stack is in ROLLBACK_COMPLETE state (fully rolled back)"
                    log_message "INFO" "This state requires cleanup before re-deployment..."
                    log_message "INFO" "Deleting rolled-back stack..."
                    
                    aws cloudformation delete-stack \
                        --profile "$PROFILE" \
                        --region "$REGION" \
                        --stack-name "$STACK_NAME" >> "$LOG_FILE" 2>&1
                    
                    log_message "INFO" "Waiting for stack deletion..."
                    aws cloudformation wait stack-delete-complete \
                        --profile "$PROFILE" \
                        --region "$REGION" \
                        --stack-name "$STACK_NAME" 2>/dev/null || true
                    
                    log_message "INFO" "✓ Rolled-back stack cleaned up"
                    ;;
                    
                CREATE_FAILED|UPDATE_FAILED)
                    # Stack is in failed state with --disable-rollback
                    # We can retry by running update-stack - this preserves successful resources!
                    log_message "INFO" "Stack is in $stack_status state (resources preserved)"
                    log_message "INFO" "Will retry failed resources using update-stack..."
                    log_message "INFO" "✓ Successfully deployed nested stacks will be preserved"
                    
                    # Show which nested stacks failed
                    get_failed_nested_stacks "$STACK_NAME"
                    ;;
                    
                UPDATE_ROLLBACK_COMPLETE)
                    # Stack update failed and rolled back - can retry with update-stack
                    log_message "INFO" "Stack update rolled back. Retrying..."
                    ;;
                    
                CREATE_COMPLETE|UPDATE_COMPLETE)
                    # Stack is healthy - nothing to retry
                    log_message "INFO" "Stack is already in $stack_status state"
                    return 0
                    ;;
                    
                DOES_NOT_EXIST)
                    # Stack doesn't exist - will be created fresh
                    log_message "INFO" "Stack does not exist. Creating fresh..."
                    ;;
                    
                *)
                    log_message "WARN" "Stack is in $stack_status state"
                    ;;
            esac
        fi
        
        # First attempt: 10 minutes wait, Retry: 5 minutes wait
        local wait_seconds=600
        if [[ $retry_count -gt 1 ]]; then
            wait_seconds=300
        fi
        
        if deploy_stack "$template_file" "$wait_seconds"; then
            return 0
        else
            if [[ $retry_count -lt $max_retries ]]; then
                log_message "WARN" "Deployment failed. Will retry ($retry_count/$max_retries)..."
                log_message "INFO" "Note: Successfully deployed resources will be preserved on retry."
            else
                log_message "ERROR" "Deployment failed after $max_retries attempts"
                
                # Show final failure analysis
                local final_status=$(aws cloudformation describe-stacks \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --stack-name "$STACK_NAME" \
                    --query "Stacks[0].StackStatus" \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                if [[ "$final_status" == "CREATE_FAILED" ]] || [[ "$final_status" == "UPDATE_FAILED" ]]; then
                    log_message "INFO" ""
                    log_message "INFO" "=== RECOVERY OPTIONS ==="
                    log_message "INFO" "The stack is preserved in $final_status state."
                    log_message "INFO" ""
                    log_message "INFO" "Option 1: Fix the issue and retry (preserves successful resources)"
                    log_message "INFO" "  ./deploy-all.sh --profile $PROFILE --disable-rollback"
                    log_message "INFO" ""
                    log_message "INFO" "Option 2: Use MCP tools to investigate failures"
                    log_message "INFO" "  mcp_aws_iac_troubleshoot_cloudformation_deployment("
                    log_message "INFO" "    stack_name='$STACK_NAME',"
                    log_message "INFO" "    region='$REGION'"
                    log_message "INFO" "  )"
                    log_message "INFO" ""
                    log_message "INFO" "Option 3: Clean up and start fresh"
                    log_message "INFO" "  echo 'yes' | ./cleanup-all.sh --profile $PROFILE"
                fi
                
                return 1
            fi
        fi
    done
    
    return 1
}

# =============================================================================
# DEPLOY STACK
# =============================================================================

deploy_stack() {
    local template_file=$1
    local initial_wait_seconds=${2:-600}  # Default 10 minutes for first attempt
    
    log_message "INFO" "========================================"
    log_message "INFO" "Deploying Orchestration Stack"
    log_message "INFO" "========================================"
    echo ""
    
    log_message "INFO" "Stack Name: $STACK_NAME"
    log_message "INFO" "Template: $template_file"
    log_message "INFO" "Estimated time: 15-20 minutes (all labs deploy in parallel)"
    if [[ "$DISABLE_ROLLBACK" == true ]]; then
        log_message "WARN" "⚠ Rollback disabled - stack will NOT rollback on failure"
        log_message "WARN" "  Use this for debugging only. Manual cleanup required after analysis."
    fi
    echo ""
    
    # If tenant email is not provided, use admin email as fallback
    local EFFECTIVE_TENANT_EMAIL="$TENANT_EMAIL"
    if [[ -z "$EFFECTIVE_TENANT_EMAIL" ]]; then
        EFFECTIVE_TENANT_EMAIL="$EMAIL"
        log_message "INFO" "Tenant email not provided, using admin email as reference: $EFFECTIVE_TENANT_EMAIL"
    fi
    
    # Check if stack already exists
    local existing_status=$(aws cloudformation describe-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    # Use create-stack with --disable-rollback for debugging, otherwise use deploy
    if [[ "$DISABLE_ROLLBACK" == true ]]; then
        log_message "INFO" "Using --disable-rollback mode for debugging..."
        
        # Handle different stack states
        case "$existing_status" in
            DOES_NOT_EXIST)
                # Stack doesn't exist - create it
                log_message "INFO" "Creating new stack with --disable-rollback..."
                
                if aws cloudformation create-stack \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --template-body "file://$template_file" \
                    --stack-name "$STACK_NAME" \
                    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
                    --parameters \
                        ParameterKey=AdminEmail,ParameterValue="$EMAIL" \
                        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
                        ParameterKey=TenantEmail,ParameterValue="$EFFECTIVE_TENANT_EMAIL" \
                    --disable-rollback 2>&1 | tee -a "$LOG_FILE"; then
                    
                    log_message "INFO" "Stack creation initiated. Waiting for completion..."
                    log_message "INFO" "(This may take 25-30 minutes)"
                else
                    log_message "ERROR" "✗ Stack creation command failed"
                    return 1
                fi
                ;;
            
            CREATE_FAILED|UPDATE_FAILED)
                # Stack exists in failed state - update it to retry
                # This is the KEY behavior: update-stack on a failed stack retries ONLY the failed resources
                # Successfully provisioned resources are PRESERVED
                log_message "INFO" "Stack exists in $existing_status state."
                log_message "INFO" "Using update-stack to retry failed resources..."
                log_message "INFO" "✓ Successfully deployed nested stacks will be preserved"
                
                if aws cloudformation update-stack \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --template-body "file://$template_file" \
                    --stack-name "$STACK_NAME" \
                    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
                    --parameters \
                        ParameterKey=AdminEmail,ParameterValue="$EMAIL" \
                        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
                        ParameterKey=TenantEmail,ParameterValue="$EFFECTIVE_TENANT_EMAIL" \
                    --disable-rollback 2>&1 | tee -a "$LOG_FILE"; then
                    
                    log_message "INFO" "Stack update initiated. Waiting for completion..."
                    log_message "INFO" "(This may take 15-25 minutes)"
                else
                    log_message "ERROR" "✗ Stack update command failed"
                    log_message "INFO" "If the error is 'No updates are to be performed', the template hasn't changed."
                    log_message "INFO" "You may need to run cleanup first: echo 'yes' | ./cleanup-all.sh --profile $PROFILE"
                    return 1
                fi
                ;;
            
            CREATE_COMPLETE|UPDATE_COMPLETE)
                # Stack exists and is healthy - update it
                log_message "INFO" "Stack exists in $existing_status state. Updating..."
                
                if aws cloudformation update-stack \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --template-body "file://$template_file" \
                    --stack-name "$STACK_NAME" \
                    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
                    --parameters \
                        ParameterKey=AdminEmail,ParameterValue="$EMAIL" \
                        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
                        ParameterKey=TenantEmail,ParameterValue="$EFFECTIVE_TENANT_EMAIL" \
                    --disable-rollback 2>&1 | tee -a "$LOG_FILE"; then
                    
                    log_message "INFO" "Stack update initiated. Waiting for completion..."
                else
                    local update_error=$?
                    # Check if it's "No updates to perform" which is not really an error
                    if grep -q "No updates are to be performed" "$LOG_FILE" 2>/dev/null; then
                        log_message "INFO" "✓ No updates needed - stack is already up to date"
                        return 0
                    fi
                    log_message "ERROR" "✗ Stack update command failed"
                    return 1
                fi
                ;;
            
            ROLLBACK_COMPLETE)
                # Stack rolled back completely - must delete and recreate
                log_message "WARN" "Stack is in ROLLBACK_COMPLETE state."
                log_message "WARN" "This state requires cleanup before re-deployment."
                log_message "INFO" "Run: echo 'yes' | ./cleanup-all.sh --profile $PROFILE"
                return 1
                ;;
            
            *_IN_PROGRESS)
                # Stack operation in progress - wait or abort
                log_message "WARN" "Stack operation already in progress: $existing_status"
                log_message "WARN" "Please wait for the current operation to complete."
                return 1
                ;;
            
            *)
                log_message "WARN" "Stack exists with status: $existing_status"
                log_message "WARN" "Attempting update..."
                
                if aws cloudformation update-stack \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --template-body "file://$template_file" \
                    --stack-name "$STACK_NAME" \
                    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
                    --parameters \
                        ParameterKey=AdminEmail,ParameterValue="$EMAIL" \
                        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
                        ParameterKey=TenantEmail,ParameterValue="$EFFECTIVE_TENANT_EMAIL" \
                    --disable-rollback 2>&1 | tee -a "$LOG_FILE"; then
                    
                    log_message "INFO" "Stack update initiated. Waiting for completion..."
                else
                    log_message "ERROR" "✗ Stack update command failed"
                    return 1
                fi
                ;;
        esac
        
        # Wait for stack operation to complete with proper failure detection
        # Wait before starting to poll, then check every 1 minute
        local wait_minutes=$((initial_wait_seconds / 60))
        log_message "INFO" "Waiting for stack operation to complete..."
        log_message "INFO" "Initial wait: ${wait_minutes} minutes before polling starts..."
        sleep $initial_wait_seconds
        
        local wait_status=""
        local wait_count=0
        local max_wait=50  # 50 iterations * 60 seconds = 50 minutes max (after initial 10 min = 60 min total)
        
        while [[ $wait_count -lt $max_wait ]]; do
            wait_status=$(aws cloudformation describe-stacks \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$STACK_NAME" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            case "$wait_status" in
                CREATE_COMPLETE|UPDATE_COMPLETE)
                    log_message "INFO" "✓ Stack operation completed successfully"
                    break
                    ;;
                CREATE_FAILED|UPDATE_FAILED|ROLLBACK_COMPLETE|ROLLBACK_FAILED|UPDATE_ROLLBACK_COMPLETE|UPDATE_ROLLBACK_FAILED)
                    log_message "ERROR" "✗ Stack operation failed: $wait_status"
                    break
                    ;;
                CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS|UPDATE_ROLLBACK_IN_PROGRESS|UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS|ROLLBACK_IN_PROGRESS)
                    # Still in progress, continue waiting
                    ((wait_count++))
                    local elapsed_min=$((10 + wait_count))
                    log_message "INFO" "  Status: $wait_status (${elapsed_min} min elapsed)"
                    sleep 60  # Check every 1 minute
                    ;;
                *)
                    log_message "WARN" "Unknown status: $wait_status, continuing to wait..."
                    ((wait_count++))
                    sleep 60
                    ;;
            esac
        done
        
        if [[ $wait_count -ge $max_wait ]]; then
            log_message "ERROR" "✗ Timeout waiting for stack operation (60 minutes)"
            wait_status="TIMEOUT"
        fi
        
        # Check final status
        local stack_status="$wait_status"
        
        log_message "INFO" "Stack Status: $stack_status"
        
        case "$stack_status" in
            CREATE_COMPLETE|UPDATE_COMPLETE)
                log_message "INFO" "✓ Deployment completed successfully"
                return 0
                ;;
            CREATE_FAILED|UPDATE_FAILED)
                log_message "ERROR" "✗ Stack operation failed (rollback disabled)"
                log_message "ERROR" "Stack Status: $stack_status"
                log_message "INFO" ""
                log_message "INFO" "=== DEBUGGING MODE ==="
                log_message "INFO" "Stack is preserved for analysis. Use MCP tools to investigate:"
                log_message "INFO" "  mcp_aws_iac_troubleshoot_cloudformation_deployment("
                log_message "INFO" "    stack_name='$STACK_NAME',"
                log_message "INFO" "    region='$REGION'"
                log_message "INFO" "  )"
                log_message "INFO" ""
                log_message "INFO" "After fixing the issue, re-run this command to update the stack:"
                log_message "INFO" "  ./deploy-all.sh --profile $PROFILE --disable-rollback"
                log_message "INFO" ""
                log_message "INFO" "Or run cleanup to start fresh:"
                log_message "INFO" "  echo 'yes' | ./cleanup-all.sh --profile $PROFILE"
                return 1
                ;;
            *)
                log_message "WARN" "⚠ Unexpected stack status: $stack_status"
                return 1
                ;;
        esac
    else
        # Standard deployment with rollback enabled
        local param_overrides="AdminEmail=$EMAIL Environment=$ENVIRONMENT TenantEmail=$EFFECTIVE_TENANT_EMAIL"
        
        if aws cloudformation deploy \
            --profile "$PROFILE" \
            --region "$REGION" \
            --template-file "$template_file" \
            --stack-name "$STACK_NAME" \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --parameter-overrides $param_overrides \
            --no-fail-on-empty-changeset 2>&1 | tee -a "$LOG_FILE"; then
            
            # CRITICAL: Check final stack status - deploy command returns 0 even on rollback
            log_message "INFO" "Verifying stack status..."
            local stack_status=$(aws cloudformation describe-stacks \
                --profile "$PROFILE" \
                --region "$REGION" \
                --stack-name "$STACK_NAME" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            log_message "INFO" "Stack Status: $stack_status"
            
            # Check for failure states
            case "$stack_status" in
                CREATE_COMPLETE|UPDATE_COMPLETE)
                    log_message "INFO" "✓ Deployment completed successfully"
                    return 0
                    ;;
                ROLLBACK_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
                    log_message "ERROR" "✗ Stack creation failed and rolled back"
                    log_message "ERROR" "Stack Status: $stack_status"
                    log_message "ERROR" "Check CloudFormation events for details:"
                    log_message "ERROR" "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --profile $PROFILE"
                    log_message "INFO" ""
                    log_message "INFO" "TIP: Re-run with --disable-rollback to preserve failed state for debugging"
                    return 1
                    ;;
                CREATE_FAILED|UPDATE_FAILED|DELETE_FAILED)
                    log_message "ERROR" "✗ Stack is in failed state: $stack_status"
                    return 1
                    ;;
                *)
                    log_message "WARN" "⚠ Unexpected stack status: $stack_status"
                    return 1
                    ;;
            esac
        else
            log_message "ERROR" "✗ Deployment failed"
            return 1
        fi
    fi
}

# =============================================================================
# DEPLOY CDK PIPELINE STACKS (Labs 5 and 6)
# =============================================================================
# Labs 5 and 6 have CDK-based CI/CD pipeline stacks that cannot be deployed
# as CloudFormation nested stacks. They require:
#   1. CDK bootstrap (CDKToolkit stack + staging bucket)
#   2. CodeCommit repository creation + code push
#   3. CDK deploy for each pipeline
#   4. (Lab6 only) Wait for pipeline to create stack-lab6-pooled
#
# These must run AFTER the CloudFormation orchestration stack deploys
# (Lab5Stack and Lab6Stack must exist first).
# =============================================================================

deploy_pipelines() {
    log_message "INFO" "========================================"
    log_message "INFO" "Deploying CDK Pipeline Stacks (Labs 5 & 6)"
    log_message "INFO" "========================================"
    echo ""

    # Check if CDK CLI is available
    if ! command -v cdk &> /dev/null; then
        log_message "WARN" "⚠ CDK CLI not found - skipping pipeline deployment"
        log_message "INFO" "  Install CDK: npm install -g aws-cdk"
        log_message "INFO" "  Then deploy pipelines manually using individual lab scripts"
        return 0
    fi

    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        log_message "WARN" "⚠ npm not found - skipping pipeline deployment"
        return 0
    fi

    local ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)

    # =========================================================================
    # Step 1: CDK Bootstrap (shared by both pipelines)
    # =========================================================================
    log_message "INFO" "Step 1: Checking CDK bootstrap..."

    local CDK_NEEDS_BOOTSTRAP=false
    local CDK_BUCKET="cdk-hnb659fds-assets-${ACCOUNT_ID}-${REGION}"

    if ! aws cloudformation describe-stacks --stack-name "CDKToolkit" --profile "$PROFILE" --region "$REGION" &> /dev/null; then
        log_message "INFO" "  CDKToolkit stack not found"
        CDK_NEEDS_BOOTSTRAP=true
    else
        if ! aws s3 ls "s3://${CDK_BUCKET}" --profile "$PROFILE" --region "$REGION" &> /dev/null; then
            log_message "INFO" "  CDKToolkit stack exists but staging bucket missing: $CDK_BUCKET"
            CDK_NEEDS_BOOTSTRAP=true
        else
            log_message "INFO" "  ✓ CDKToolkit stack and staging bucket verified"
        fi
    fi

    if [[ "$CDK_NEEDS_BOOTSTRAP" == "true" ]]; then
        log_message "INFO" "  Bootstrapping CDK..."
        if ! cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}" --profile "$PROFILE" >> "$LOG_FILE" 2>&1; then
            log_message "ERROR" "✗ CDK bootstrap failed"
            return 1
        fi
        log_message "INFO" "  ✓ CDKToolkit bootstrapped successfully"
    fi

    # =========================================================================
    # Step 2: CodeCommit repository + code push
    # =========================================================================
    log_message "INFO" "Step 2: Setting up CodeCommit repository..."

    local REPO_URL="codecommit::${REGION}://${PROFILE}@aws-serverless-saas-workshop"

    set +e
    local REPO_CHECK=$(aws codecommit get-repository --repository-name aws-serverless-saas-workshop --profile "$PROFILE" --region "$REGION" 2>&1)
    local REPO_CHECK_EXIT=$?
    set -e

    if [[ $REPO_CHECK_EXIT -ne 0 ]]; then
        log_message "INFO" "  Creating CodeCommit repository: aws-serverless-saas-workshop"
        if ! aws codecommit create-repository \
            --repository-name aws-serverless-saas-workshop \
            --repository-description "Serverless SaaS workshop repository" \
            --profile "$PROFILE" --region "$REGION" >> "$LOG_FILE" 2>&1; then
            log_message "ERROR" "✗ Failed to create CodeCommit repository"
            return 1
        fi
        log_message "INFO" "  ✓ Repository created"
        sleep 10
    else
        log_message "INFO" "  ✓ Repository exists"
    fi

    # Set up git remote
    local GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$GIT_ROOT" ]]; then
        log_message "ERROR" "✗ Not in a git repository"
        return 1
    fi

    git -C "$GIT_ROOT" remote set-url cc "$REPO_URL" 2>/dev/null || git -C "$GIT_ROOT" remote add cc "$REPO_URL" 2>/dev/null

    local CURRENT_BRANCH=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD)
    log_message "INFO" "  Current branch: $CURRENT_BRANCH"

    # Check for uncommitted changes
    if [[ -n $(git -C "$GIT_ROOT" status -s) ]]; then
        log_message "WARN" "  ⚠ Uncommitted changes detected, committing now..."
        git -C "$GIT_ROOT" add -A
        git -C "$GIT_ROOT" commit -m "chore: Auto-commit before pipeline deployment"
    fi

    # Push to CodeCommit (export AWS_PROFILE for git-remote-codecommit)
    log_message "INFO" "  Pushing code to CodeCommit..."
    export AWS_PROFILE="$PROFILE"
    local push_attempts=0
    local push_max=5
    local push_success=false
    while [[ $push_attempts -lt $push_max ]]; do
        push_attempts=$((push_attempts + 1))
        if git -C "$GIT_ROOT" push cc "$CURRENT_BRANCH:main" --force >> "$LOG_FILE" 2>&1; then
            push_success=true
            break
        fi
        if [[ $push_attempts -lt $push_max ]]; then
            log_message "WARN" "  Push attempt $push_attempts/$push_max failed, retrying in 10s..."
            sleep 10
        fi
    done
    if [[ "$push_success" != "true" ]]; then
        log_message "ERROR" "✗ Failed to push code to CodeCommit after $push_max attempts"
        return 1
    fi
    log_message "INFO" "  ✓ Code pushed to CodeCommit main branch"

    # =========================================================================
    # Step 3: Deploy Lab5 & Lab6 pipelines IN PARALLEL
    # =========================================================================
    log_message "INFO" "Step 3: Deploying Lab5 & Lab6 pipelines in parallel..."

    local LAB5_PIPELINE_DIR="$WORKSHOP_ROOT/Lab5/server/TenantPipeline"
    local LAB6_PIPELINE_DIR="$WORKSHOP_ROOT/Lab6/server/TenantPipeline"
    local original_dir=$(pwd)
    local LAB5_LOG="${LOG_DIR}/pipeline-lab5.log"
    local LAB6_LOG="${LOG_DIR}/pipeline-lab6.log"
    local lab5_pid="" lab6_pid=""
    local lab5_exit=0 lab6_exit=0

    # --- Lab5 pipeline deploy (background) ---
    if [[ -d "$LAB5_PIPELINE_DIR" ]]; then
        (
            cd "$LAB5_PIPELINE_DIR" || exit 1
            echo "[$(date '+%H:%M:%S')] Cleaning previous npm installation..." >> "$LAB5_LOG"
            rm -rf node_modules package-lock.json 2>/dev/null || true

            echo "[$(date '+%H:%M:%S')] Installing dependencies..." >> "$LAB5_LOG"
            npm install >> "$LAB5_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] Building..." >> "$LAB5_LOG"
            npm run build >> "$LAB5_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] Deploying CDK stack..." >> "$LAB5_LOG"
            cdk deploy --require-approval never --profile "$PROFILE" --region "$REGION" >> "$LAB5_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] ✓ Lab5 pipeline deployed successfully" >> "$LAB5_LOG"
        ) &
        lab5_pid=$!
        log_message "INFO" "  Lab5 pipeline started (PID: $lab5_pid, log: $LAB5_LOG)"
    else
        log_message "WARN" "  ⚠ Lab5 TenantPipeline directory not found, skipping"
    fi

    # --- Lab6 pipeline deploy (background) ---
    if [[ -d "$LAB6_PIPELINE_DIR" ]]; then
        (
            cd "$LAB6_PIPELINE_DIR" || exit 1
            echo "[$(date '+%H:%M:%S')] Cleaning previous npm installation..." >> "$LAB6_LOG"
            rm -rf node_modules package-lock.json 2>/dev/null || true

            echo "[$(date '+%H:%M:%S')] Installing dependencies..." >> "$LAB6_LOG"
            npm install >> "$LAB6_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] Building..." >> "$LAB6_LOG"
            npm run build >> "$LAB6_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] Deploying CDK stack..." >> "$LAB6_LOG"
            cdk deploy --require-approval never --profile "$PROFILE" --region "$REGION" >> "$LAB6_LOG" 2>&1 || exit 1

            echo "[$(date '+%H:%M:%S')] ✓ Lab6 pipeline deployed successfully" >> "$LAB6_LOG"
        ) &
        lab6_pid=$!
        log_message "INFO" "  Lab6 pipeline started (PID: $lab6_pid, log: $LAB6_LOG)"
    else
        log_message "WARN" "  ⚠ Lab6 TenantPipeline directory not found, skipping"
    fi

    # --- Wait for both to finish ---
    if [[ -n "$lab5_pid" ]]; then
        log_message "INFO" "  Waiting for Lab5 pipeline (PID: $lab5_pid)..."
        set +e
        wait "$lab5_pid"
        lab5_exit=$?
        set -e
        if [[ $lab5_exit -eq 0 ]]; then
            log_message "INFO" "  ✓ Lab5 pipeline deployed successfully"
        else
            log_message "ERROR" "  ✗ Lab5 pipeline failed (exit code: $lab5_exit)"
            log_message "INFO" "    Check log: $LAB5_LOG"
        fi
    fi

    if [[ -n "$lab6_pid" ]]; then
        log_message "INFO" "  Waiting for Lab6 pipeline (PID: $lab6_pid)..."
        set +e
        wait "$lab6_pid"
        lab6_exit=$?
        set -e
        if [[ $lab6_exit -eq 0 ]]; then
            log_message "INFO" "  ✓ Lab6 pipeline deployed successfully"
        else
            log_message "ERROR" "  ✗ Lab6 pipeline failed (exit code: $lab6_exit)"
            log_message "INFO" "    Check log: $LAB6_LOG"
        fi
    fi

    if [[ $lab5_exit -ne 0 || $lab6_exit -ne 0 ]]; then
        log_message "WARN" "⚠ One or both pipeline deployments failed"
        [[ $lab5_exit -ne 0 ]] && log_message "INFO" "  Lab5 log: $LAB5_LOG"
        [[ $lab6_exit -ne 0 ]] && log_message "INFO" "  Lab6 log: $LAB6_LOG"
        return 1
    fi

    # =========================================================================
    # Step 4: Wait for Lab6 pipeline to create pooled stack
    # =========================================================================
    log_message "INFO" "Step 4: Waiting for Lab6 pipeline to create stack-lab6-pooled..."
    log_message "INFO" "  The pipeline auto-triggers and creates the pooled tenant stack"
    log_message "INFO" "  This typically takes 5-10 minutes..."
    echo ""

    sleep 30  # Wait for pipeline execution to start

    local MAX_WAIT=900  # 15 minutes
    local ELAPSED=0
    local INTERVAL=30

    while [[ $ELAPSED -lt $MAX_WAIT ]]; do
        set +e
        local PIPELINE_STATUS=$(aws codepipeline get-pipeline-state \
            --name serverless-saas-pipeline-lab6 \
            --profile "$PROFILE" --region "$REGION" \
            --query 'stageStates[?stageName==`Deploy`].latestExecution.status' \
            --output text 2>/dev/null)
        set -e

        if [[ "$PIPELINE_STATUS" == "Succeeded" ]]; then
            log_message "INFO" "  ✓ Lab6 pipeline Deploy stage completed successfully"
            break
        elif [[ "$PIPELINE_STATUS" == "Failed" ]]; then
            log_message "WARN" "  ⚠ Lab6 pipeline Deploy stage failed"
            log_message "INFO" "    Check: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view"
            break
        elif [[ -n "$PIPELINE_STATUS" ]]; then
            log_message "INFO" "  Pipeline Deploy stage status: $PIPELINE_STATUS (waiting...)"
        fi

        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done

    if [[ $ELAPSED -ge $MAX_WAIT ]]; then
        log_message "WARN" "  ⚠ Timeout waiting for Lab6 pipeline (15 minutes)"
        log_message "INFO" "    The pipeline may still be running. Check the console:"
        log_message "INFO" "    https://console.aws.amazon.com/codesuite/codepipeline/pipelines/serverless-saas-pipeline-lab6/view"
    fi

    # Wait for pooled stack to be fully created
    log_message "INFO" "  Waiting for stack-lab6-pooled to be ready..."
    set +e
    aws cloudformation wait stack-create-complete \
        --stack-name stack-lab6-pooled \
        --profile "$PROFILE" --region "$REGION" 2>/dev/null
    local pooled_wait_result=$?
    set -e

    if [[ $pooled_wait_result -eq 0 ]]; then
        log_message "INFO" "  ✓ stack-lab6-pooled created successfully"
    else
        log_message "WARN" "  ⚠ stack-lab6-pooled may not be ready yet (non-fatal)"
    fi

    echo ""
    log_message "INFO" "✓ Pipeline deployment completed"
    return 0
}

# =============================================================================
# DISPLAY OUTPUTS
# =============================================================================

display_outputs() {
    log_message "INFO" "========================================"
    log_message "INFO" "Deployment Outputs"
    log_message "INFO" "========================================"
    echo ""
    
    aws cloudformation describe-stacks \
        --profile "$PROFILE" \
        --region "$REGION" \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
        --output table 2>/dev/null || log_message "WARN" "Could not retrieve outputs"
    
    echo ""
    
    # If email was not provided, remind user to create users
    if [[ -z "$EMAIL" ]]; then
        log_message "INFO" "========================================"
        log_message "INFO" "NEXT STEP: Create Workshop Users"
        log_message "INFO" "========================================"
        echo ""
        log_message "WARN" "⚠ No admin email was provided during deployment."
        log_message "INFO" "Admin users were NOT created in Cognito."
        log_message "INFO" ""
        log_message "INFO" "To create admin users, run:"
        log_message "INFO" "  ./orchestration/create-workshop-users.sh --email <your-email> --profile $PROFILE --stack-name $STACK_NAME"
        echo ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_arguments "$@"
    
    # Don't redirect all output - it causes issues with variable capture
    # Just log to file explicitly where needed
    
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "AWS Serverless SaaS Workshop"
    print_message "$BLUE" "Orchestration Deployment"
    print_message "$BLUE" "========================================"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    local start_time=$(date +%s)
    
    verify_prerequisites
    create_s3_bucket
    
    # Validate base template structure before packaging
    if ! validate_base_template; then
        log_message "ERROR" "Base template validation failed"
        exit 1
    fi
    
    if ! package_all_labs; then
        log_message "ERROR" "Failed to package templates"
        exit 1
    fi
    
    generate_orchestration_template
    
    if deploy_stack_with_retry "$ORCHESTRATION_TEMPLATE_PATH"; then
        # Configure API Gateway account AFTER deployment
        # The role is created by CloudFormation, we just need to configure the account to use it
        configure_api_gateway_account
        
        # Set log retention on all Lambda log groups
        # This runs AFTER deployment to avoid CloudFormation race condition with RetentionInDays
        log_message "INFO" "========================================"
        log_message "INFO" "Setting Log Group Retention"
        log_message "INFO" "========================================"
        echo ""
        
        local retention_script="$ORCHESTRATION_DIR/set-log-retention.sh"
        if [[ -x "$retention_script" ]]; then
            if "$retention_script" --profile "$PROFILE" --region "$REGION" --retention 60; then
                log_message "INFO" "✓ Log retention configured"
            else
                log_message "WARN" "⚠ Log retention configuration had issues (non-critical)"
            fi
        else
            log_message "WARN" "⚠ Log retention script not found: $retention_script"
        fi
        echo ""
        
        # Deploy CDK pipeline stacks for Labs 5 and 6
        if deploy_pipelines; then
            log_message "INFO" "✓ Pipeline deployment completed"
        else
            log_message "WARN" "⚠ Pipeline deployment had issues (see details above)"
        fi
        echo ""
        
        # Deploy frontends after CloudFormation deployment
        if deploy_frontends; then
            log_message "INFO" "✓ Frontend deployment completed"
        else
            log_message "WARN" "⚠ Some frontends failed to deploy (see details above)"
        fi
        
        display_outputs
        
        # Automatically create workshop users if email was provided
        if [[ -n "$EMAIL" ]]; then
            log_message "INFO" "========================================"
            log_message "INFO" "Creating Workshop Users"
            log_message "INFO" "========================================"
            echo ""
            log_message "INFO" "Email provided - automatically creating Cognito admin users..."
            
            local user_script="$ORCHESTRATION_DIR/create-workshop-users.sh"
            if [[ -x "$user_script" ]]; then
                local -a user_cmd=("$user_script" --email "$EMAIL" --profile "$PROFILE" --region "$REGION" --stack-name "$STACK_NAME")
                if [[ -n "$TENANT_EMAIL" ]]; then
                    user_cmd+=(--tenant-email "$TENANT_EMAIL")
                fi
                
                # Capture output to a temp file so we can log it
                local user_output_file="${LOG_DIR}/user-creation-output.log"
                
                if "${user_cmd[@]}" > "$user_output_file" 2>&1; then
                    log_message "INFO" "✓ Workshop users created successfully"
                    # Log the output for reference
                    if [[ -f "$user_output_file" ]]; then
                        log_message "INFO" "User creation output:"
                        cat "$user_output_file" >> "$LOG_FILE"
                        cat "$user_output_file"
                    fi
                else
                    local exit_code=$?
                    log_message "WARN" "⚠ User creation failed with exit code: $exit_code"
                    # Log the error output for debugging
                    if [[ -f "$user_output_file" && -s "$user_output_file" ]]; then
                        log_message "ERROR" "User creation script output:"
                        echo "--- User Creation Error Output Start ---" >> "$LOG_FILE"
                        cat "$user_output_file" >> "$LOG_FILE"
                        echo "--- User Creation Error Output End ---" >> "$LOG_FILE"
                        # Also display to console
                        echo "--- User Creation Error Output ---"
                        cat "$user_output_file"
                        echo "--- End Error Output ---"
                    else
                        log_message "ERROR" "No output captured from user creation script"
                    fi
                    log_message "INFO" "You can retry manually:"
                    log_message "INFO" "  ./orchestration/create-workshop-users.sh --email $EMAIL --profile $PROFILE --stack-name $STACK_NAME"
                fi
            else
                log_message "WARN" "⚠ User creation script not found or not executable: $user_script"
                log_message "INFO" "Create users manually:"
                log_message "INFO" "  ./orchestration/create-workshop-users.sh --email $EMAIL --profile $PROFILE --stack-name $STACK_NAME"
            fi
            echo ""
        fi
        
        local duration=$(($(date +%s) - start_time))
        log_message "INFO" "✓ Deployment completed in ${duration} seconds"
        log_message "INFO" "To cleanup: ./cleanup-all.sh --profile $PROFILE --stack-name $STACK_NAME"
    else
        local duration=$(($(date +%s) - start_time))
        log_message "ERROR" "✗ Deployment failed after ${duration} seconds"
        exit 1
    fi
}

main "$@"
