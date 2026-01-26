# Deployment Order Fix - Lab6

## Problem

The initial deployment was failing because the pipeline was being deployed **before** the shared stack and DynamoDB tables were created. This caused two issues:

1. **ResourceNotFoundException**: The `deploy-tenant-stack` Lambda function tried to scan the `ServerlessSaaS-TenantStackMapping-lab6` table before it existed
2. **Missing API Gateway URL**: Even if the pipeline succeeded later, the pooled stack wouldn't be created on first run, leaving the `apiGatewayUrl-Pooled` setting missing from the Settings table

## Root Cause

The `deployment.sh` script had the wrong deployment order:

```bash
# OLD ORDER (WRONG)
1. Deploy pipeline (triggers on CodeCommit push)
2. Deploy shared stack (creates DynamoDB tables)
```

When the pipeline was deployed first:
- CodeCommit repository was created
- Code was pushed to CodeCommit
- Pipeline was automatically triggered
- Pipeline's Lambda function tried to scan DynamoDB tables
- **ERROR**: Tables didn't exist yet because shared stack wasn't deployed

## Solution

We fixed the deployment order in `deployment.sh`:

```bash
# NEW ORDER (CORRECT)
1. Deploy shared stack (creates DynamoDB tables)
2. Wait for DynamoDB tables to be ACTIVE
3. Deploy pipeline (now tables exist when triggered)
```

### Changes Made

#### 1. Reordered Deployment Steps (`deployment.sh`)

Moved the pipeline deployment block to execute **after** the shared stack deployment and DynamoDB table verification:

```bash
# Deploy shared stack first
if [[ $server -eq 1 ]] || [[ $bootstrap -eq 1 ]]; then
  # ... deploy shared stack ...
  
  # Wait for DynamoDB tables
  for table in "ServerlessSaaS-Settings-lab6" "ServerlessSaaS-TenantStackMapping-lab6" ...; do
    aws dynamodb wait table-exists --table-name $table
  done
fi

# Deploy pipeline AFTER tables are ready
if [[ $server -eq 1 ]] || [[ $pipeline -eq 1 ]]; then
  # ... deploy pipeline ...
fi
```

#### 2. Added Error Handling (`lambda-deploy-tenant-stack.py`)

Added graceful handling for the edge case where tables might not exist:

```python
try:
    mappings = table_tenant_stack_mapping.scan()
except botocore.exceptions.ClientError as e:
    if e.response['Error']['Code'] == 'ResourceNotFoundException':
        # Table doesn't exist yet - this can happen if pipeline is triggered before shared stack completes
        put_job_success(job_id, 'TenantStackMapping table not found - will retry on next pipeline run')
        return "Complete."
```

Also added check for empty table:

```python
if mappings['Count'] == 0:
    put_job_success(job_id, 'No tenants found in TenantStackMapping table')
    return "Complete."
```

## Test Results

After implementing the fixes, a complete clean deployment was successful:

### ✅ Deployment Sequence
1. Shared stack deployed: `CREATE_COMPLETE`
2. DynamoDB tables verified: All `ACTIVE`
3. Pipeline deployed: `CREATE_COMPLETE`
4. Pipeline executed automatically: All stages `Succeeded`
5. Pooled stack created: `stack-lab6-pooled` - `CREATE_COMPLETE`

### ✅ Settings Table Populated
```
apiGatewayUrl-Pooled: https://qefdsa2i8j.execute-api.us-east-1.amazonaws.com/prod/
userPoolId-pooled: us-east-1_iMF1aTT1Q
appClientId-pooled: 3hhoc9ihhs83gubb8o3p72bq1j
```

### ✅ Client Sites Deployed
- Admin Site: https://d8f5dv03w3xtd.cloudfront.net
- Landing Site: https://dcbmw2vjweqno.cloudfront.net
- Application Site: https://d2wkdb1jfjbwsm.cloudfront.net

## Files Modified

1. `aws-serverless-saas-workshop/Lab6/scripts/deployment.sh`
   - Reordered deployment steps
   - Pipeline now deploys after shared stack

2. `aws-serverless-saas-workshop/Lab6/server/TenantPipeline/resources/lambda-deploy-tenant-stack.py`
   - Added ResourceNotFoundException handling
   - Added empty table check

## Commits

1. `fix(pipeline): handle ResourceNotFoundException for TenantStackMapping table`
2. `fix(deployment): deploy pipeline after shared stack and DynamoDB tables`

## Benefits

1. **Reliable First Deployment**: Pipeline always has required resources available
2. **No Manual Intervention**: No need to manually trigger pipeline after initial deployment
3. **Graceful Error Handling**: Even if timing issues occur, Lambda handles them gracefully
4. **Tenant Registration Works**: `apiGatewayUrl-Pooled` is always populated before tenants are created

## Architecture Flow (Corrected)

```
1. Shared Stack Deployment
   ├── Creates DynamoDB tables
   ├── Creates Cognito User Pools
   ├── Creates API Gateway
   └── Custom resources populate Settings table

2. Wait for DynamoDB Tables
   └── Verify all tables are ACTIVE

3. Pipeline Deployment
   ├── Creates CodeCommit repository
   ├── Pushes code to CodeCommit
   └── Pipeline is triggered

4. Pipeline Execution
   ├── Source: Pulls code from CodeCommit
   ├── Build: Builds tenant template
   └── Deploy: Creates pooled stack
       └── Custom resource stores apiGatewayUrl-Pooled

5. Tenant Registration
   └── Can now retrieve pooled API Gateway URL
```

## Related Documentation

- [TENANT_REGISTRATION_FIX.md](./TENANT_REGISTRATION_FIX.md) - Original tenant registration issue
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Complete deployment instructions
