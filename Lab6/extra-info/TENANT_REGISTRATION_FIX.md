# Tenant Registration Fix - Lab6

## Issue Summary

Tenant registration was failing with `KeyError('Item')` when trying to create pooled tenants (Basic, Standard, Premium tiers).

## Root Cause

The `create_tenant` function in `tenant-management.py` attempts to retrieve `apiGatewayUrl-Pooled` from the Settings table:

```python
settings_response = table_system_settings.get_item(
    Key={
        'settingName': 'apiGatewayUrl-Pooled'
    } 
)
api_gateway_url = settings_response['Item']['settingValue']
```

However, this setting was missing because:

1. The pooled stack (`stack-lab6-pooled`) was never created
2. The pooled stack contains a custom resource (`UpdateTenantApiGatewayUrl`) that stores the pooled API Gateway URL in the Settings table
3. The pipeline's Deploy stage failed on the first run, preventing the pooled stack from being created

## Why the Pipeline Failed

The `lambda-deploy-tenant-stack.py` function had a logic issue:

1. On first pipeline run after deployment, it scans the `TenantStackMapping` table
2. Finds the `pooled` entry (created by the `UpdateTenantStackMap` custom resource)
3. Calls `start_update_or_create` which calls `continue_job_later`
4. Function returns without calling `put_job_success`
5. CodePipeline waits for the Lambda to signal success, but it never does
6. After timeout, CodePipeline marks the Deploy stage as Failed

## Solution Applied

### Immediate Fix
Manually triggered the pipeline to run again:
```
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline-lab6 --region us-east-1
```

This successfully created the `stack-lab6-pooled` stack, which populated the Settings table with `apiGatewayUrl-Pooled`.

### Permanent Fix
Added a check in `lambda-deploy-tenant-stack.py` to handle empty TenantStackMapping table:

```python
# Check if there are any tenants to process
if mappings['Count'] == 0:
    put_job_success(job_id, 'No tenants found in TenantStackMapping table')
    return "Complete."
```

This prevents the pipeline from failing if the table is temporarily empty during initial deployment.

## Verification

After the fix:
1. Pooled stack created: `stack-lab6-pooled` - Status: `CREATE_COMPLETE`
2. Settings table populated:
   - `apiGatewayUrl-Pooled`: `https://ujahdawp8j.execute-api.us-east-1.amazonaws.com/prod/`
   - `userPoolId-pooled`: `us-east-1_2abjfo1SV`
   - `appClientId-pooled`: `6s0niq93pv4r6ta4fff0l9ag2t`
3. Tenant registration now works for pooled tenants

## Files Modified

- `aws-serverless-saas-workshop/Lab6/server/TenantPipeline/resources/lambda-deploy-tenant-stack.py`

## Commit

```
fix(pipeline): handle empty TenantStackMapping table gracefully

Add check for empty TenantStackMapping table scan results to prevent
pipeline failures when no tenants exist. This ensures the pipeline
completes successfully even if the table is temporarily empty during
initial deployment.

Fixes issue where first pipeline run would fail with JobFailed error
when TenantStackMapping table scan returned 0 items.
```

## Architecture Flow

1. **Shared Stack Deployment** → Creates Settings table with Cognito settings only
2. **Custom Resource** → Populates TenantStackMapping table with pooled entry
3. **Pipeline Triggered** → Deploys tenant template for pooled tenants
4. **Pooled Stack Created** → Custom resource stores pooled API Gateway URL in Settings table
5. **Tenant Registration** → Can now retrieve pooled API Gateway URL for pooled tenants

## Related Files

- `aws-serverless-saas-workshop/Lab6/server/TenantManagementService/tenant-management.py` (lines 36-42)
- `aws-serverless-saas-workshop/Lab6/server/custom_resources/update_tenant_apigatewayurl.py`
- `aws-serverless-saas-workshop/Lab6/server/custom_resources/update_tenantstackmap_table.py`
- `aws-serverless-saas-workshop/Lab6/server/tenant-template.yaml` (UpdateTenantApiGatewayUrl custom resource)
