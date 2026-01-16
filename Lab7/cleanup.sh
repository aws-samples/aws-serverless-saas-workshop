#!/bin/bash -e

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging setup
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="cleanup-${TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Lab7 Cleanup Script"
echo "========================================"
echo "Log file: $LOG_FILE"
echo ""

START_TIME=$(date +%s)

# Stack names
MAIN_STACK="serverless-saas-workshop-lab7"

echo -e "${YELLOW}Starting cleanup of Lab7 resources...${NC}"
echo ""

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" --region us-east-1 >/dev/null 2>&1
}

# Function to wait for stack deletion
wait_for_stack_deletion() {
    local stack_name=$1
    echo "Waiting for stack $stack_name to be deleted..."
    
    while stack_exists "$stack_name"; do
        local status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region us-east-1 --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [ "$status" == "DELETE_FAILED" ]; then
            echo -e "${RED}Stack deletion failed. Please check AWS Console for details.${NC}"
            return 1
        fi
        
        echo "  Status: $status"
        sleep 10
    done
    
    echo -e "${GREEN}Stack $stack_name deleted successfully${NC}"
}

# Empty and delete S3 buckets with lab7 prefix
echo -e "${YELLOW}Step 1: Cleaning up S3 buckets...${NC}"
BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'serverless-saas-lab7')].Name" --output text)

if [ -n "$BUCKETS" ]; then
    for bucket in $BUCKETS; do
        echo "  Emptying bucket: $bucket"
        aws s3 rm s3://$bucket --recursive --quiet 2>/dev/null || true
        echo "  Deleting bucket: $bucket"
        aws s3api delete-bucket --bucket $bucket --region us-east-1 2>/dev/null || true
    done
    echo -e "${GREEN}S3 buckets cleaned up${NC}"
else
    echo "  No Lab7 S3 buckets found"
fi
echo ""

# Delete tenant stack first (if exists)
echo -e "${YELLOW}Step 2: Deleting tenant stack...${NC}"
TENANT_STACK="stack-pooled-lab7"
if stack_exists "$TENANT_STACK"; then
    echo "  Deleting stack: $TENANT_STACK"
    aws cloudformation delete-stack --stack-name "$TENANT_STACK" --region us-east-1
    wait_for_stack_deletion "$TENANT_STACK"
else
    echo "  Stack $TENANT_STACK not found"
fi
echo ""

# Delete main CloudFormation stack
echo -e "${YELLOW}Step 3: Deleting main CloudFormation stack...${NC}"
if stack_exists "$MAIN_STACK"; then
    echo "  Deleting stack: $MAIN_STACK"
    aws cloudformation delete-stack --stack-name "$MAIN_STACK" --region us-east-1
    wait_for_stack_deletion "$MAIN_STACK"
else
    echo "  Stack $MAIN_STACK not found"
fi
echo ""

# Delete DynamoDB table
echo -e "${YELLOW}Step 4: Deleting DynamoDB table...${NC}"
TABLE_NAME="TenantCostAndUsageAttribution-lab7"
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region us-east-1 >/dev/null 2>&1; then
    echo "  Deleting table: $TABLE_NAME"
    aws dynamodb delete-table --table-name "$TABLE_NAME" --region us-east-1 >/dev/null 2>&1 || true
    echo -e "${GREEN}DynamoDB table deleted${NC}"
else
    echo "  Table $TABLE_NAME not found"
fi
echo ""

# Delete Lambda functions with lab7 prefix
echo -e "${YELLOW}Step 5: Deleting Lambda functions...${NC}"
FUNCTIONS=$(aws lambda list-functions --region us-east-1 --query "Functions[?contains(FunctionName, 'lab7')].FunctionName" --output text)

if [ -n "$FUNCTIONS" ]; then
    for func in $FUNCTIONS; do
        echo "  Deleting function: $func"
        aws lambda delete-function --function-name "$func" --region us-east-1 2>/dev/null || true
    done
    echo -e "${GREEN}Lambda functions deleted${NC}"
else
    echo "  No Lab7 Lambda functions found"
fi
echo ""

# Delete CloudWatch Log Groups
echo -e "${YELLOW}Step 6: Deleting CloudWatch Log Groups...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --region us-east-1 --query "logGroups[?contains(logGroupName, 'lab7')].logGroupName" --output text)

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        echo "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" --region us-east-1 2>/dev/null || true
    done
    echo -e "${GREEN}CloudWatch Log Groups deleted${NC}"
else
    echo "  No Lab7 Log Groups found"
fi
echo ""

# Delete EventBridge Rules
echo -e "${YELLOW}Step 7: Deleting EventBridge Rules...${NC}"
RULES=$(aws events list-rules --region us-east-1 --query "Rules[?contains(Name, 'lab7')].Name" --output text)

if [ -n "$RULES" ]; then
    for rule in $RULES; do
        echo "  Removing targets from rule: $rule"
        TARGETS=$(aws events list-targets-by-rule --rule "$rule" --region us-east-1 --query "Targets[].Id" --output text)
        if [ -n "$TARGETS" ]; then
            aws events remove-targets --rule "$rule" --ids $TARGETS --region us-east-1 2>/dev/null || true
        fi
        echo "  Deleting rule: $rule"
        aws events delete-rule --name "$rule" --region us-east-1 2>/dev/null || true
    done
    echo -e "${GREEN}EventBridge Rules deleted${NC}"
else
    echo "  No Lab7 EventBridge Rules found"
fi
echo ""

# Delete IAM Roles
echo -e "${YELLOW}Step 8: Deleting IAM Roles...${NC}"
ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'lab7')].RoleName" --output text)

if [ -n "$ROLES" ]; then
    for role in $ROLES; do
        echo "  Detaching policies from role: $role"
        
        # Detach managed policies
        MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || true)
        for policy in $MANAGED_POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames[]" --output text 2>/dev/null || true)
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        
        echo "  Deleting role: $role"
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done
    echo -e "${GREEN}IAM Roles deleted${NC}"
else
    echo "  No Lab7 IAM Roles found"
fi
echo ""

# Verify cleanup
echo -e "${YELLOW}Step 9: Verifying cleanup...${NC}"
REMAINING_STACKS=$(aws cloudformation list-stacks --region us-east-1 --query "StackSummaries[?contains(StackName, 'lab7') && StackStatus!='DELETE_COMPLETE'].StackName" --output text)
REMAINING_FUNCTIONS=$(aws lambda list-functions --region us-east-1 --query "Functions[?contains(FunctionName, 'lab7')].FunctionName" --output text)
REMAINING_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'serverless-saas-lab7')].Name" --output text)

if [ -z "$REMAINING_STACKS" ] && [ -z "$REMAINING_FUNCTIONS" ] && [ -z "$REMAINING_BUCKETS" ]; then
    echo -e "${GREEN}All Lab7 resources have been cleaned up successfully!${NC}"
else
    echo -e "${YELLOW}Some resources may still exist:${NC}"
    [ -n "$REMAINING_STACKS" ] && echo "  Stacks: $REMAINING_STACKS"
    [ -n "$REMAINING_FUNCTIONS" ] && echo "  Functions: $REMAINING_FUNCTIONS"
    [ -n "$REMAINING_BUCKETS" ] && echo "  Buckets: $REMAINING_BUCKETS"
fi
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "========================================"
echo -e "${GREEN}Lab7 Cleanup Complete!${NC}"
echo "Duration: ${DURATION} seconds"
echo "Log file: $LOG_FILE"
echo "========================================"
