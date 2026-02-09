#!/bin/bash
# =============================================================================
# create-workshop-users.sh
# Creates all necessary Cognito users for the workshop after deployment
# 
# This script is designed to be run AFTER the orchestration deployment
# completes, allowing email-free deployment of infrastructure first.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="serverless-saas-lab"
AWS_REGION="us-east-1"
AWS_PROFILE=""
ADMIN_EMAIL=""
TENANT_EMAIL=""
ADMIN_PASSWORD=""
VERBOSE=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage function
usage() {
    cat << EOF
Usage: $0 --email <admin-email> --profile <aws-profile> [OPTIONS]

Creates Cognito admin users for all deployed labs in the workshop.

REQUIRED:
  --email <email>           Admin email address for all users
  --profile <profile>       AWS CLI profile name

OPTIONAL:
  --tenant-email <email>    Tenant admin email (defaults to admin email)
  --password <password>     Admin password (auto-generated if not provided)
  --stack-name <name>       CloudFormation stack name (default: serverless-saas-workshop)
  --region <region>         AWS region (default: us-east-1)
  --verbose                 Enable verbose output
  --help                    Show this help message

EXAMPLES:
  # Create users with auto-generated password
  $0 --email admin@example.com --profile my-profile

  # Create users with custom password
  $0 --email admin@example.com --profile my-profile --password "MyPass123!"

  # Create users for custom stack name
  $0 --email admin@example.com --profile my-profile --stack-name my-workshop

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --tenant-email)
            TENANT_EMAIL="$2"
            shift 2
            ;;
        --password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ADMIN_EMAIL" ]]; then
    echo -e "${RED}Error: --email is required${NC}"
    echo ""
    usage
fi

if [[ -z "$AWS_PROFILE" ]]; then
    echo -e "${RED}Error: --profile is required${NC}"
    echo ""
    usage
fi

# Validate email format
if ! [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Error: Invalid email format: $ADMIN_EMAIL${NC}"
    exit 1
fi

# Set defaults
TENANT_EMAIL="${TENANT_EMAIL:-$ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SaaS#Workshop$(date +%s)!}"

# Build AWS CLI base command
aws_cmd() {
    aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        print_message "$CYAN" "  [DEBUG] $1"
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# Function to get CloudFormation output from main stack
get_stack_output() {
    local output_key=$1
    aws_cmd cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Function to get nested stack physical resource ID
get_nested_stack_id() {
    local logical_id=$1
    aws_cmd cloudformation describe-stack-resource \
        --stack-name "$STACK_NAME" \
        --logical-resource-id "$logical_id" \
        --query "StackResourceDetail.PhysicalResourceId" \
        --output text 2>/dev/null || echo ""
}

# Function to get output from nested stack
get_nested_stack_output() {
    local nested_stack_id=$1
    local output_key=$2
    
    if [[ -z "$nested_stack_id" ]]; then
        echo ""
        return
    fi
    
    aws_cmd cloudformation describe-stacks \
        --stack-name "$nested_stack_id" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Function to check if user exists
user_exists() {
    local user_pool_id=$1
    local username=$2
    
    aws_cmd cognito-idp admin-get-user \
        --user-pool-id "$user_pool_id" \
        --username "$username" > /dev/null 2>&1
}

# Function to create admin user
create_admin_user() {
    local user_pool_id=$1
    local username=$2
    local email=$3
    local password=$4
    local tenant_id=$5
    local user_role=$6
    local group_name=$7
    local lab_name=$8
    
    print_message "$BLUE" "  Creating user '$username' for $lab_name..."
    print_verbose "User Pool ID: $user_pool_id"
    
    # Check if user already exists
    if user_exists "$user_pool_id" "$username"; then
        print_message "$YELLOW" "    ⚠ User '$username' already exists, skipping creation"
        
        # Still try to add to group in case it wasn't added before
        if [[ -n "$group_name" ]]; then
            aws_cmd cognito-idp admin-add-user-to-group \
                --user-pool-id "$user_pool_id" \
                --username "$username" \
                --group-name "$group_name" > /dev/null 2>&1 || true
        fi
        return 0
    fi
    
    # Create user
    if aws_cmd cognito-idp admin-create-user \
        --user-pool-id "$user_pool_id" \
        --username "$username" \
        --user-attributes \
            Name=email,Value="$email" \
            Name=email_verified,Value=true \
            Name=custom:tenantId,Value="$tenant_id" \
            Name=custom:userRole,Value="$user_role" \
        --temporary-password "$password" \
        --message-action SUPPRESS > /dev/null 2>&1; then
        print_message "$GREEN" "    ✓ User '$username' created successfully"
    else
        print_message "$RED" "    ✗ Failed to create user '$username'"
        return 1
    fi
    
    # Add to group if specified
    if [[ -n "$group_name" ]]; then
        if aws_cmd cognito-idp admin-add-user-to-group \
            --user-pool-id "$user_pool_id" \
            --username "$username" \
            --group-name "$group_name" > /dev/null 2>&1; then
            print_message "$GREEN" "    ✓ Added to group '$group_name'"
        else
            print_message "$YELLOW" "    ⚠ Could not add to group '$group_name' (may not exist)"
        fi
    fi
    
    return 0
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

print_header "Workshop User Creation Script"
echo ""
print_message "$CYAN" "Configuration:"
print_message "$BLUE" "  Stack Name:    $STACK_NAME"
print_message "$BLUE" "  Region:        $AWS_REGION"
print_message "$BLUE" "  Profile:       $AWS_PROFILE"
print_message "$BLUE" "  Admin Email:   $ADMIN_EMAIL"
print_message "$BLUE" "  Tenant Email:  $TENANT_EMAIL"

# Verify stack exists
print_header "Verifying CloudFormation Stack"
if ! aws_cmd cloudformation describe-stacks --stack-name "$STACK_NAME" > /dev/null 2>&1; then
    print_message "$RED" "Error: Stack '$STACK_NAME' not found in region '$AWS_REGION'"
    print_message "$YELLOW" "Make sure the orchestration deployment has completed successfully."
    exit 1
fi
print_message "$GREEN" "✓ Stack '$STACK_NAME' found"

# Track success/failure
USERS_CREATED=0
USERS_SKIPPED=0
USERS_FAILED=0

# =============================================================================
# LAB 2 - Admin User (Operations User Pool)
# =============================================================================
print_header "Lab 2: Admin User"

LAB2_STACK_ID=$(get_nested_stack_id "Lab2Stack")
if [[ -n "$LAB2_STACK_ID" ]]; then
    print_verbose "Lab2 Stack ID: $LAB2_STACK_ID"
    LAB2_ADMIN_POOL_ID=$(get_nested_stack_output "$LAB2_STACK_ID" "CognitoOperationUsersUserPoolId")
    
    if [[ -n "$LAB2_ADMIN_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB2_ADMIN_POOL_ID" \
            "admin" \
            "$ADMIN_EMAIL" \
            "$ADMIN_PASSWORD" \
            "system_admins" \
            "SystemAdmin" \
            "SystemAdmins" \
            "Lab2"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab2 User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab2 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 3 - Admin User (Operations User Pool)
# =============================================================================
print_header "Lab 3: Admin User"

LAB3_STACK_ID=$(get_nested_stack_id "Lab3Stack")
if [[ -n "$LAB3_STACK_ID" ]]; then
    print_verbose "Lab3 Stack ID: $LAB3_STACK_ID"
    LAB3_ADMIN_POOL_ID=$(get_nested_stack_output "$LAB3_STACK_ID" "CognitoOperationUsersUserPoolId")
    
    if [[ -n "$LAB3_ADMIN_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB3_ADMIN_POOL_ID" \
            "admin" \
            "$ADMIN_EMAIL" \
            "$ADMIN_PASSWORD" \
            "system_admins" \
            "SystemAdmin" \
            "SystemAdmins" \
            "Lab3"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab3 User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab3 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 3 - Tenant Admin User (Tenant User Pool)
# =============================================================================
print_header "Lab 3: Tenant Admin User"

if [[ -n "$LAB3_STACK_ID" ]]; then
    LAB3_TENANT_POOL_ID=$(get_nested_stack_output "$LAB3_STACK_ID" "CognitoTenantUserPoolId")
    
    if [[ -n "$LAB3_TENANT_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB3_TENANT_POOL_ID" \
            "tenant1-admin" \
            "$TENANT_EMAIL" \
            "$ADMIN_PASSWORD" \
            "tenant1" \
            "TenantAdmin" \
            "" \
            "Lab3 Tenant"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab3 Tenant User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab3 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 4 - Admin User (Operations User Pool)
# =============================================================================
print_header "Lab 4: Admin User"

LAB4_STACK_ID=$(get_nested_stack_id "Lab4Stack")
if [[ -n "$LAB4_STACK_ID" ]]; then
    print_verbose "Lab4 Stack ID: $LAB4_STACK_ID"
    LAB4_ADMIN_POOL_ID=$(get_nested_stack_output "$LAB4_STACK_ID" "CognitoOperationUsersUserPoolId")
    
    if [[ -n "$LAB4_ADMIN_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB4_ADMIN_POOL_ID" \
            "admin" \
            "$ADMIN_EMAIL" \
            "$ADMIN_PASSWORD" \
            "system_admins" \
            "SystemAdmin" \
            "SystemAdmins" \
            "Lab4"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab4 User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab4 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 4 - Tenant Admin User (Tenant User Pool)
# =============================================================================
print_header "Lab 4: Tenant Admin User"

if [[ -n "$LAB4_STACK_ID" ]]; then
    LAB4_TENANT_POOL_ID=$(get_nested_stack_output "$LAB4_STACK_ID" "CognitoTenantUserPoolId")
    
    if [[ -n "$LAB4_TENANT_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB4_TENANT_POOL_ID" \
            "tenant1-admin" \
            "$TENANT_EMAIL" \
            "$ADMIN_PASSWORD" \
            "tenant1" \
            "TenantAdmin" \
            "" \
            "Lab4 Tenant"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
        
        if create_admin_user \
            "$LAB4_TENANT_POOL_ID" \
            "tenant2-admin" \
            "$TENANT_EMAIL" \
            "$ADMIN_PASSWORD" \
            "tenant2" \
            "TenantAdmin" \
            "" \
            "Lab4 Tenant"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab4 Tenant User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab4 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 5 - Admin User (Operations User Pool)
# =============================================================================
print_header "Lab 5: Admin User"

LAB5_STACK_ID=$(get_nested_stack_id "Lab5Stack")
if [[ -n "$LAB5_STACK_ID" ]]; then
    print_verbose "Lab5 Stack ID: $LAB5_STACK_ID"
    LAB5_ADMIN_POOL_ID=$(get_nested_stack_output "$LAB5_STACK_ID" "CognitoOperationUsersUserPoolId")
    
    if [[ -n "$LAB5_ADMIN_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB5_ADMIN_POOL_ID" \
            "admin" \
            "$ADMIN_EMAIL" \
            "$ADMIN_PASSWORD" \
            "system_admins" \
            "SystemAdmin" \
            "SystemAdmins" \
            "Lab5"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab5 User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab5 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# LAB 6 - Admin User (Operations User Pool)
# =============================================================================
print_header "Lab 6: Admin User"

LAB6_STACK_ID=$(get_nested_stack_id "Lab6Stack")
if [[ -n "$LAB6_STACK_ID" ]]; then
    print_verbose "Lab6 Stack ID: $LAB6_STACK_ID"
    LAB6_ADMIN_POOL_ID=$(get_nested_stack_output "$LAB6_STACK_ID" "CognitoOperationUsersUserPoolId")
    
    if [[ -n "$LAB6_ADMIN_POOL_ID" ]]; then
        if create_admin_user \
            "$LAB6_ADMIN_POOL_ID" \
            "admin" \
            "$ADMIN_EMAIL" \
            "$ADMIN_PASSWORD" \
            "system_admins" \
            "SystemAdmin" \
            "SystemAdmins" \
            "Lab6"; then
            ((USERS_CREATED++)) || true
        else
            ((USERS_FAILED++)) || true
        fi
    else
        print_message "$YELLOW" "  Lab6 User Pool ID not found in outputs"
        ((USERS_SKIPPED++)) || true
    fi
else
    print_message "$YELLOW" "  Lab6 not deployed"
    ((USERS_SKIPPED++)) || true
fi

# =============================================================================
# SUMMARY
# =============================================================================
print_header "Summary"
echo ""
print_message "$GREEN" "Users Created/Updated: $USERS_CREATED"
print_message "$YELLOW" "Users Skipped:         $USERS_SKIPPED"
print_message "$RED" "Users Failed:          $USERS_FAILED"
echo ""

if [[ $USERS_CREATED -gt 0 ]] || [[ $USERS_SKIPPED -gt 0 && $USERS_FAILED -eq 0 ]]; then
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    print_message "$GREEN" "  Admin Credentials (Operations)"
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    echo ""
    print_message "$CYAN" "  Username:           admin"
    print_message "$CYAN" "  Email:              $ADMIN_EMAIL"
    print_message "$CYAN" "  Temporary Password: $ADMIN_PASSWORD"
    echo ""
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    print_message "$GREEN" "  Tenant Credentials (Lab3 Application)"
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    echo ""
    print_message "$CYAN" "  Username:           tenant1-admin"
    print_message "$CYAN" "  Email:              $TENANT_EMAIL"
    print_message "$CYAN" "  Temporary Password: $ADMIN_PASSWORD"
    echo ""
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    print_message "$GREEN" "  Tenant Credentials (Lab4 Application)"
    print_message "$GREEN" "═══════════════════════════════════════════════════"
    echo ""
    print_message "$CYAN" "  Username:           tenant1-admin"
    print_message "$CYAN" "  Email:              $TENANT_EMAIL"
    print_message "$CYAN" "  Temporary Password: $ADMIN_PASSWORD"
    echo ""
    print_message "$CYAN" "  Username:           tenant2-admin"
    print_message "$CYAN" "  Email:              $TENANT_EMAIL"
    print_message "$CYAN" "  Temporary Password: $ADMIN_PASSWORD"
    echo ""
    print_message "$YELLOW" "  Note: Users must change password on first login."
    echo ""
    
    # Write credentials to file
    CREDENTIALS_FILE="$SCRIPT_DIR/workshop-credentials.txt"
    {
        echo "═══════════════════════════════════════════════════"
        echo "  AWS Serverless SaaS Workshop - Credentials"
        echo "═══════════════════════════════════════════════════"
        echo ""
        echo "  Generated: $(date)"
        echo "  Stack:     $STACK_NAME"
        echo "  Region:    $AWS_REGION"
        echo ""
        echo "  --- Admin Credentials (Operations) ---"
        echo "  Username:           admin"
        echo "  Email:              $ADMIN_EMAIL"
        echo "  Temporary Password: $ADMIN_PASSWORD"
        echo ""
        echo "  --- Tenant Credentials (Lab3 Application) ---"
        echo "  Username:           tenant1-admin"
        echo "  Email:              $TENANT_EMAIL"
        echo "  Temporary Password: $ADMIN_PASSWORD"
        echo ""
        echo "  --- Tenant Credentials (Lab4 Application) ---"
        echo "  Username:           tenant1-admin"
        echo "  Email:              $TENANT_EMAIL"
        echo "  Temporary Password: $ADMIN_PASSWORD"
        echo ""
        echo "  Username:           tenant2-admin"
        echo "  Email:              $TENANT_EMAIL"
        echo "  Temporary Password: $ADMIN_PASSWORD"
        echo ""
        echo "  Note: Users must change password on first login."
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo "  SECURITY WARNING: Delete this file after use!"
        echo "═══════════════════════════════════════════════════"
    } > "$CREDENTIALS_FILE"
    
    print_message "$GREEN" "  Credentials saved to: $CREDENTIALS_FILE"
    print_message "$YELLOW" "  ⚠ Remember to delete this file after use!"
    echo ""
fi

if [[ $USERS_FAILED -gt 0 ]]; then
    print_message "$RED" "Some users failed to create. Check the output above for details."
    exit 1
fi

print_message "$GREEN" "✓ User creation complete!"
echo ""
print_message "$BLUE" "Next Steps:"
print_message "$BLUE" "  1. Log in to each lab's admin application with the credentials above"
print_message "$BLUE" "  2. Change the temporary password when prompted"
print_message "$BLUE" "  3. For Labs 3-4, use the admin app to onboard tenants"
print_message "$BLUE" "  4. Delete workshop-credentials.txt after noting the password"
echo ""
