#!/bin/bash

# Fix Pipeline Stacks - Manual Cleanup Script
# This script fixes the Lab5 and Lab6 pipeline stacks that failed to delete due to missing CDK execution roles

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Get AWS profile
AWS_PROFILE="${1:-serverless-saas-demo}"
AWS_REGION="us-east-1"

print_message "$BLUE" "========================================"
print_message "$BLUE" "Fix Pipeline Stacks - Manual Cleanup"
print_message "$BLUE" "========================================"
print_message "$YELLOW" "AWS Profile: $AWS_PROFILE"
print_message "$YELLOW" "AWS Region: $AWS_REGION"
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")
print_message "$YELLOW" "Account ID: $ACCOUNT_ID"
echo ""

# CDK execution role name
CDK_ROLE_NAME="cdk-hnb659fds-cfn-exec-role-${ACCOUNT_ID}-${AWS_REGION}"

print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 1: Create Temporary CDK Execution Role"
print_message "$BLUE" "========================================"

# Check if role already exists
ROLE_EXISTS=$(aws iam get-role --role-name "$CDK_ROLE_NAME" --profile "$AWS_PROFILE" 2>/dev/null || echo "")

if [ -n "$ROLE_EXISTS" ]; then
    print_message "$YELLOW" "  ✓ CDK execution role already exists: $CDK_ROLE_NAME"
else
    print_message "$YELLOW" "  Creating CDK execution role: $CDK_ROLE_NAME"
    
    # Create the role
    aws iam create-role \
        --role-name "$CDK_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "cloudformation.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "  ✓ Role created successfully"
    else
        print_message "$RED" "  ✗ Failed to create role"
        exit 1
    fi
    
    # Attach AdministratorAccess policy
    print_message "$YELLOW" "  Attaching AdministratorAccess policy..."
    aws iam attach-role-policy \
        --role-name "$CDK_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "  ✓ Policy attached successfully"
    else
        print_message "$RED" "  ✗ Failed to attach policy"
        exit 1
    fi
    
    # Wait for role to propagate
    print_message "$YELLOW" "  Waiting 5 seconds for role to propagate..."
    sleep 5
fi

echo ""

print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 2: Fix Lab5 Pipeline Stack (DELETE_FAILED)"
print_message "$BLUE" "========================================"

# Check Lab5 stack status
LAB5_STATUS=$(aws cloudformation describe-stacks \
    --stack-name serverless-saas-pipeline-lab5 \
    --query 'Stacks[0].StackStatus' \
    --output text \
    --profile "$AWS_PROFILE" 2>/dev/null || echo "NOT_FOUND")

print_message "$YELLOW" "  Current status: $LAB5_STATUS"

if [ "$LAB5_STATUS" == "DELETE_FAILED" ]; then
    print_message "$YELLOW" "  Retrying deletion with CDK role..."
    
    aws cloudformation delete-stack \
        --stack-name serverless-saas-pipeline-lab5 \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "  ✓ Delete initiated"
        print_message "$YELLOW" "  Waiting for stack deletion to complete..."
        
        aws cloudformation wait stack-delete-complete \
            --stack-name serverless-saas-pipeline-lab5 \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "  ✓ Lab5 pipeline stack deleted successfully"
        else
            print_message "$RED" "  ✗ Stack deletion failed or timed out"
            print_message "$YELLOW" "  Check CloudFormation console for details"
        fi
    else
        print_message "$RED" "  ✗ Failed to initiate deletion"
    fi
elif [ "$LAB5_STATUS" == "NOT_FOUND" ]; then
    print_message "$GREEN" "  ✓ Lab5 pipeline stack already deleted"
else
    print_message "$YELLOW" "  ⚠ Stack status is $LAB5_STATUS (not DELETE_FAILED)"
    print_message "$YELLOW" "  Skipping Lab5 stack deletion"
fi

echo ""

print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 3: Delete Lab6 Pipeline Stack"
print_message "$BLUE" "========================================"

# Check Lab6 stack status
LAB6_STATUS=$(aws cloudformation describe-stacks \
    --stack-name serverless-saas-pipeline-lab6 \
    --query 'Stacks[0].StackStatus' \
    --output text \
    --profile "$AWS_PROFILE" 2>/dev/null || echo "NOT_FOUND")

print_message "$YELLOW" "  Current status: $LAB6_STATUS"

if [ "$LAB6_STATUS" == "CREATE_COMPLETE" ] || [ "$LAB6_STATUS" == "UPDATE_COMPLETE" ]; then
    print_message "$YELLOW" "  Deleting Lab6 pipeline stack..."
    
    aws cloudformation delete-stack \
        --stack-name serverless-saas-pipeline-lab6 \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "  ✓ Delete initiated"
        print_message "$YELLOW" "  Waiting for stack deletion to complete..."
        
        aws cloudformation wait stack-delete-complete \
            --stack-name serverless-saas-pipeline-lab6 \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "  ✓ Lab6 pipeline stack deleted successfully"
        else
            print_message "$RED" "  ✗ Stack deletion failed or timed out"
            print_message "$YELLOW" "  Check CloudFormation console for details"
        fi
    else
        print_message "$RED" "  ✗ Failed to initiate deletion"
    fi
elif [ "$LAB6_STATUS" == "NOT_FOUND" ]; then
    print_message "$GREEN" "  ✓ Lab6 pipeline stack already deleted"
else
    print_message "$YELLOW" "  ⚠ Stack status is $LAB6_STATUS"
    print_message "$YELLOW" "  You may need to manually delete this stack"
fi

echo ""

print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 4: Clean Up Temporary CDK Role"
print_message "$BLUE" "========================================"

print_message "$YELLOW" "  Detaching AdministratorAccess policy..."
aws iam detach-role-policy \
    --role-name "$CDK_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null

print_message "$YELLOW" "  Deleting CDK execution role..."
aws iam delete-role \
    --role-name "$CDK_ROLE_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null

if [ $? -eq 0 ]; then
    print_message "$GREEN" "  ✓ CDK execution role deleted"
else
    print_message "$YELLOW" "  ⚠ Could not delete role (may not exist or have dependencies)"
fi

echo ""

print_message "$BLUE" "========================================"
print_message "$BLUE" "Step 5: Verification"
print_message "$BLUE" "========================================"

# Check for remaining pipeline stacks
print_message "$YELLOW" "Checking for remaining pipeline stacks..."
REMAINING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED \
    --query 'StackSummaries[?contains(StackName, `pipeline-lab`)].StackName' \
    --output text \
    --profile "$AWS_PROFILE" 2>/dev/null)

if [ -n "$REMAINING_STACKS" ]; then
    print_message "$YELLOW" "  ⚠ Found remaining pipeline stacks:"
    for stack in $REMAINING_STACKS; do
        print_message "$YELLOW" "    - $stack"
    done
else
    print_message "$GREEN" "  ✓ No remaining pipeline stacks"
fi

echo ""
print_message "$GREEN" "========================================"
print_message "$GREEN" "Pipeline Stack Fix Complete!"
print_message "$GREEN" "========================================"
