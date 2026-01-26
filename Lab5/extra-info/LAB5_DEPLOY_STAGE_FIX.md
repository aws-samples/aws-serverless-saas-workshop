# Lab 5 Deploy Stage Fix

## Issue Summary

Lab 5's CodePipeline Deploy stage Lambda function was missing required CloudFormation parameters, causing deployment failures when the pipeline attempted to create or update tenant stacks.

## Root Cause

The `lambda-deploy-tenant-stack.py` function's `get_tenant_params()` method only passed the `TenantIdParameter` to CloudFormation, but the `tenant-template.yaml` requires three additional parameters:
- `Environment`
- `Owner`
- `CostCenter`

This caused CloudFormation stack operations to fail with parameter validation errors.

## Changes Made

### 1. Lambda Function Parameter Fix

**File**: `workshop/Lab5/server/TenantPipeline/resources/lambda-deploy-tenant-stack.py`

Updated the `get_tenant_params()` function to include all required CloudFormation parameters:

```python
def get_tenant_params(tenantId):
    """Get tenant details to be supplied to Cloud formation

    Args:
        tenantId (str): tenantId for which details are needed

    Returns:
        params from tenant management table
    """
    params = []
    param_tenantid = {}
    param_tenantid['ParameterKey'] = 'TenantIdParameter'
    param_tenantid['ParameterValue'] = tenantId
    params.append(param_tenantid)

    # Add required CloudFormation parameters
    add_parameter(params, 'Environment', 'prod')
    add_parameter(params, 'Owner', 'serverless-saas-lab5')
    add_parameter(params, 'CostCenter', 'serverless-saas-lab5')

    return params
```

### 2. Empty Tenant Handling Enhancement

Added a check to handle the case when no tenants exist in the TenantStackMapping table:

```python
# Get all the stacks for each tenant to be updated/created from tenant stack mapping table
mappings = table_tenant_stack_mapping.scan()
print (mappings)

# Check if there are any tenants to process
if mappings['Count'] == 0:
    put_job_success(job_id, 'No tenants found in TenantStackMapping table')
    return "Complete."

#Update/Create stacks for all tenants
```

This prevents the Lambda function from failing when the pipeline runs before any tenants are onboarded.

### 3. CDK Stack CloudWatch Logs Configuration

**File**: `workshop/Lab5/server/TenantPipeline/lib/serverless-saas-stack.ts`

Added explicit CloudWatch Logs configuration to prevent log group creation issues:

```typescript
// Create CloudWatch Log Group for Lambda function
const lambdaLogGroup = new logs.LogGroup(this, 'DeployTenantStackLogGroup', {
  logGroupName: '/aws/lambda/serverless-saas-pipeline-lab5-deploytenantstackD22DC62',
  retention: logs.RetentionDays.TWO_MONTHS,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
});

const lambdaFunction = new Function(this, "deploy-tenant-stack", {
    handler: "lambda-deploy-tenant-stack.lambda_handler",
    runtime: Runtime.PYTHON_3_14,
    code: new AssetCode(`./resources`),
    memorySize: 512,
    timeout: Duration.seconds(10),
    environment: {
        BUCKET: artifactsBucket.bucketName,
    },
    initialPolicy: [lambdaPolicy],
    logGroup: lambdaLogGroup,  // Explicit log group reference
})
```

## Testing

After applying the fixes:

1. Rebuilt and redeployed the CDK stack:
   ```bash
   cd workshop/Lab5/server/TenantPipeline
   cdk deploy --require-approval never --profile serverless-saas-demo
   ```

2. Triggered a pipeline execution:
   ```bash
   aws codepipeline start-pipeline-execution \
     --name serverless-saas-pipeline-lab5 \
     --profile serverless-saas-demo
   ```

3. Verified all stages succeeded:
   - Source: ✅ Succeeded
   - Build: ✅ Succeeded
   - Deploy: ✅ Succeeded

## Related Issues

This fix addresses the same issue that was found and fixed in Lab 6. Both labs had the identical parameter mismatch problem.

## Impact

- **Before**: Pipeline Deploy stage failed with CloudFormation parameter validation errors
- **After**: Pipeline executes successfully through all stages
- **Benefit**: Tenant stacks can now be deployed automatically via the pipeline

## Date

January 24, 2026
