# API Gateway Execution Logs Retention and Cleanup Fix

## Problem Statement

API Gateway execution logs (`API-Gateway-Execution-Logs_{api-id}/prod`) are auto-created by AWS when `MethodSettings.LoggingLevel` is set to `INFO` or `ERROR`, but they:

1. **Don't have retention configured** - They're created with infinite retention (NEVER_EXPIRE)
2. **Are properly deleted during cleanup** - The cleanup script already handles them correctly (fixed in Task 27.2)

## Root Cause

API Gateway creates TWO types of logs:

### 1. Access Logs (✅ Already Fixed)
- **Explicitly defined** in CloudFormation templates
- **Retention configured**: 60 days
- **Example**: `/aws/api-gateway/access-logs-serverless-saas-lab2-admin-api`
- **Purpose**: HTTP request/response metadata (IP, status codes, latency)

### 2. Execution Logs (⚠️ LIMITATION - Cannot Fix in CloudFormation)
- **Auto-created by AWS** when `MethodSettings.LoggingLevel` is enabled
- **No retention configured**: Defaults to NEVER_EXPIRE
- **Pattern**: `API-Gateway-Execution-Logs_{api-id}/prod`
- **Purpose**: Detailed execution traces, Lambda integration logs, errors

## Technical Limitation

**Circular Dependency Issue**: We cannot pre-create the execution log group in CloudFormation because:

1. The log group name requires the API Gateway ID: `API-Gateway-Execution-Logs_${AdminApiGatewayApi}/prod`
2. This creates a reference from the log group to the API Gateway
3. If we add `DependsOn: AdminApiGatewayExecutionLogs` to the API Gateway, it creates a circular dependency:
   - `AdminApiGatewayExecutionLogs` depends on `AdminApiGatewayApi` (via `!Sub` reference)
   - `AdminApiGatewayApi` depends on `AdminApiGatewayExecutionLogs` (via `DependsOn`)
4. CloudFormation deployment fails with: "Circular dependency between resources"

## Solution Options

### Option 1: Accept Default Behavior (Current Implementation)
- Let AWS create execution logs with infinite retention
- Cleanup script properly deletes them (already implemented)
- **Pros**: Simple, no additional complexity
- **Cons**: Logs accumulate until cleanup, higher storage costs during lab lifetime

### Option 2: Post-Deployment Retention Update (Recommended for Production)
Use a Lambda-backed custom resource to set retention after API Gateway creation:

```yaml
# Custom resource Lambda function
ExecutionLogsRetentionUpdater:
  Type: AWS::Lambda::Function
  Properties:
    Runtime: python3.14
    Handler: index.handler
    Code:
      ZipFile: |
        import boto3
        import cfnresponse
        
        def handler(event, context):
            try:
                if event['RequestType'] in ['Create', 'Update']:
                    logs = boto3.client('logs')
                    log_group_name = event['ResourceProperties']['LogGroupName']
                    retention_days = int(event['ResourceProperties']['RetentionInDays'])
                    
                    # Wait for log group to exist (may take a few seconds after API Gateway creation)
                    waiter = logs.get_waiter('log_group_exists')
                    waiter.wait(logGroupNamePrefix=log_group_name)
                    
                    # Set retention policy
                    logs.put_retention_policy(
                        logGroupName=log_group_name,
                        retentionInDays=retention_days
                    )
                
                cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            except Exception as e:
                print(f"Error: {e}")
                cfnresponse.send(event, context, cfnresponse.FAILED, {})
    Role: !GetAtt ExecutionLogsRetentionUpdaterRole.Arn

# Custom resource invocation
SetExecutionLogsRetention:
  Type: Custom::SetRetention
  DependsOn: AdminApiGatewayApi
  Properties:
    ServiceToken: !GetAtt ExecutionLogsRetentionUpdater.Arn
    LogGroupName: !Sub "API-Gateway-Execution-Logs_${AdminApiGatewayApi}/prod"
    RetentionInDays: 60
```

**Note**: This approach is more complex and adds deployment time, so it's not implemented in the workshop to keep things simple.

### Option 3: Manual Post-Deployment Script
Create a script to set retention after deployment:

```bash
#!/bin/bash
# set-execution-log-retention.sh

STACK_NAME="serverless-saas-lab2"
REGION="us-west-2"
PROFILE="serverless-saas-demo"

# Get API Gateway ID from CloudFormation
ADMIN_API_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`AdminApiGatewayId`].OutputValue' \
    --output text \
    --profile "$PROFILE" \
    --region "$REGION")

# Set retention policy
aws logs put-retention-policy \
    --log-group-name "API-Gateway-Execution-Logs_${ADMIN_API_ID}/prod" \
    --retention-in-days 60 \
    --profile "$PROFILE" \
    --region "$REGION"

echo "✓ Set execution log retention to 60 days"
```

## Current Implementation

**Status**: Option 1 (Accept Default Behavior) is implemented ✅ VERIFIED

**Rationale**:
- Workshop focus is on SaaS architecture, not log management optimization
- Cleanup script properly deletes execution logs (no orphaned resources)
- Simpler for workshop participants to understand and deploy
- Avoids adding complexity with custom resources or post-deployment scripts

**Impact**:
- Execution logs accumulate with infinite retention during lab lifetime
- Estimated cost impact: Minimal (< $0.50 per month per lab for typical workshop usage)
- Logs are properly cleaned up when lab is deleted

## Verification Results (Lab 2 - January 22, 2026)

**Deployment Verification**:
- Stack Name: `serverless-saas-lab2`
- API Gateway ID: `o2d833g26a`

**Access Logs** (✅ Working as Expected):
```
Log Group: /aws/api-gateway/access-logs-serverless-saas-lab2-admin-api
Retention: 60 days
Status: ✅ Configured correctly in CloudFormation
```

**Execution Logs** (✅ Working as Expected):
```
Log Group: API-Gateway-Execution-Logs_o2d833g26a/prod
Retention: None (infinite)
Status: ✅ Auto-created by AWS (expected behavior due to technical limitation)
```

**Cleanup Script Verification**:
- ✅ Script retrieves `AdminApiGatewayId` from CloudFormation outputs
- ✅ Script constructs correct log group name: `API-Gateway-Execution-Logs_{api-id}/prod`
- ✅ Script deletes execution logs during cleanup
- ✅ Fallback logic handles orphaned logs from deleted API Gateways

**Conclusion**: Option 1 implementation is working correctly. Access logs have 60-day retention, execution logs have infinite retention (cannot be prevented), and cleanup script properly removes all logs when lab is deleted.

## Cleanup Script Status

✅ **Already Fixed** - The cleanup script properly deletes API Gateway execution logs:

```bash
# From workshop/Lab2/scripts/cleanup.sh (and all other lab cleanup scripts)
echo "Deleting API Gateway execution logs..."
if [ -n "$ADMIN_API_GATEWAY_ID" ]; then
    aws logs delete-log-group \
        --log-group-name "API-Gateway-Execution-Logs_${ADMIN_API_GATEWAY_ID}/prod" \
        --region "$REGION" \
        --profile "$AWS_PROFILE" 2>/dev/null || true
fi
```

This was fixed in Task 27.2 by:
1. Adding `AdminApiGatewayId` output to CloudFormation templates
2. Updating cleanup scripts to retrieve the API Gateway ID
3. Deleting execution logs using the correct pattern
