# API Gateway Execution Logs Cleanup Fix

## Issue Discovered

During Lab 2 testing, we discovered that API Gateway execution logs were not being deleted during cleanup:
- `API-Gateway-Execution-Logs_4rmlb3pw2a/prod` (Lab 2 Admin API - current)
- `API-Gateway-Execution-Logs_pgyjq3j0jl/prod` (Lab 1 API - previous deployment)

Both log groups had NO retention policy (infinite retention).

## Root Cause

The cleanup script (`workshop/Lab2/scripts/cleanup.sh`) has code to delete API Gateway execution logs (lines 165-200), but it cannot retrieve the API Gateway IDs because:

1. **Missing CloudFormation Output**: The nested API Gateway template (`workshop/Lab2/server/nested_templates/apigateway.yaml`) only exports `AdminApiGatewayApi` (full resource reference), NOT `AdminApiGatewayId` (just the ID)

2. **Cleanup Script Expectation**: The cleanup script queries for `AdminApiGatewayId` and `TenantApiGatewayId` outputs:
   ```
   ADMIN_API_ID=$(aws cloudformation describe-stacks \
       --stack-name "$STACK_NAME" \
       --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
       --output text)
   ```

3. **Result**: Script cannot find the API Gateway IDs, so it cannot delete the execution logs

## Solution Implemented

### 1. Updated API Gateway Nested Template

**File**: `workshop/Lab2/server/nested_templates/apigateway.yaml`

Added `AdminApiGatewayId` output:
```yaml
Outputs:  
  AdminApiGatewayApi:
    Value: !Ref AdminApiGatewayApi
  AdminApiGatewayId:
    Description: Admin API Gateway ID for log group cleanup
    Value: !Ref AdminApiGatewayApi
```

### 2. Updated Main Template

**File**: `workshop/Lab2/server/template.yaml`

Exposed the `AdminApiGatewayId` output from the nested stack:
```yaml
Outputs:
  AdminApi:
    Description: "API Gateway endpoint URL for Admin API"
    Value: !Join ["", ["https://", !GetAtt APIs.Outputs.AdminApiGatewayApi, ".execute-api.", !Ref "AWS::Region", ".amazonaws.com/", !Ref StageName]]
  AdminApiGatewayId:
    Description: "Admin API Gateway ID for log group cleanup"
    Value: !GetAtt APIs.Outputs.AdminApiGatewayId
```

## Verification Steps

After deploying the updated templates:

1. **Verify Output Exists**:
   ```
   aws cloudformation describe-stacks \
       --stack-name serverless-saas-lab2 \
       --region us-west-2 \
       --profile <your-profile-name> \
       --query "Stacks[0].Outputs[?OutputKey=='AdminApiGatewayId'].OutputValue" \
       --output text
   ```
   Should return the API Gateway ID (e.g., `4rmlb3pw2a`)

2. **Test Cleanup Script**:
   ```
   cd workshop/Lab2/scripts
   echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab2 --profile <your-profile-name>
   ```
   Should successfully delete API Gateway execution logs

3. **Verify Logs Deleted**:
   ```
   aws logs describe-log-groups \
       --region us-west-2 \
       --profile <your-profile-name> \
       --query "logGroups[?contains(logGroupName, 'API-Gateway-Execution-Logs_')].logGroupName" \
       --output text
   ```
   Should return empty (no orphaned API Gateway logs)

## Impact on Other Labs

This same issue likely affects other labs that have API Gateways:
- Lab 3: Has both Admin and Tenant APIs
- Lab 4: Has both Admin and Tenant APIs
- Lab 5: Has both Admin and Tenant APIs
- Lab 6: Has both Admin and Tenant APIs

**Action Required**: Apply the same fix to Labs 3-6 by adding `AdminApiGatewayId` and `TenantApiGatewayId` outputs to their API Gateway templates and main templates.

## Security Note

API Gateway execution logs can contain sensitive information and should be properly cleaned up. Leaving orphaned logs with infinite retention:
- Increases storage costs
- May violate data retention policies
- Could expose sensitive request/response data

## Related Files

- `workshop/Lab2/server/nested_templates/apigateway.yaml` (updated)
- `workshop/Lab2/server/template.yaml` (updated)
- `workshop/Lab2/scripts/cleanup.sh` (reference - shows cleanup logic)
- `workshop/CLOUDWATCH_LOGS_CLEANUP_ORDER_FIX.md` (related - CloudWatch logs cleanup order)
- `workshop/CLOUDFRONT_SECURITY_FIX.md` (related - secure deletion order)

## Testing Status

- [x] Issue identified
- [x] Root cause analyzed
- [x] Fix implemented for Lab 2
- [ ] Fix deployed and tested
- [ ] Fix applied to Labs 3-6
- [ ] All labs verified

## Next Steps

1. Deploy updated Lab 2 templates
2. Test cleanup script to verify API Gateway logs are deleted
3. Apply same fix to Labs 3-6
4. Update deployment guide with verification steps
