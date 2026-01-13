# Lab6 Dependency Verification

## ✅ Verified Components

### 1. Pipeline Configuration (TenantPipeline)

**Files Checked:**
- `Lab6/server/TenantPipeline/package.json`
- `Lab6/server/TenantPipeline/cdk.json`
- `Lab6/server/TenantPipeline/bin/pipeline.ts`
- `Lab6/server/TenantPipeline/lib/serverless-saas-stack.ts`

**Status:** ✅ **FIXED**

**Changes Made:**
1. **Pipeline Stack Name**: Updated from `serverless-saas-pipeline` to `serverless-saas-pipeline-lab6`
   - File: `bin/pipeline.ts`
   - Line: `new ServerlessSaaSStack(app, 'serverless-saas-pipeline-lab6')`

2. **Pipeline Resource Name**: Updated from `serverless-saas-pipeline` to `serverless-saas-pipeline-lab6`
   - File: `lib/serverless-saas-stack.ts`
   - Line: `pipelineName: 'serverless-saas-pipeline-lab6'`

3. **Build Spec Path**: Correctly references `Lab6/server/tenant-buildspec.yml`

**Dependencies:**
- ✅ `aws-cdk-lib: ^2.0.0`
- ✅ `constructs: ^10.0.0`
- ✅ `typescript: 4.9.5`
- ✅ All dev dependencies match Lab5

**CodeCommit Repository:**
- ✅ Name: `aws-serverless-saas-workshop` (shared across all labs - correct)

---

### 2. DynamoDB Tables

**Files Checked:**
- `Lab6/server/nested_templates/tables.yaml`
- `Lab6/server/tenant-template.yaml`

**Status:** ✅ **VERIFIED**

**All Tables Have Lab6 Suffix:**
1. ✅ `ServerlessSaaS-Settings-lab6`
2. ✅ `ServerlessSaaS-TenantStackMapping-lab6`
3. ✅ `ServerlessSaaS-TenantDetails-lab6`
4. ✅ `ServerlessSaaS-TenantUserMapping-lab6`

**Global Secondary Index:**
- ✅ `ServerlessSaas-TenantConfig-lab6` (on TenantDetails table)

**IAM Policy References:**
- ✅ All ARNs correctly reference lab6 table names
- ✅ Custom resource properties use lab6 table names

---

### 3. Lambda Functions

**Naming Convention:** `serverless-saas-lab6-{function-name}`

**Status:** ✅ **VERIFIED**

**Key Functions:**
- ✅ `serverless-saas-lab6-update-settings-table`
- ✅ `serverless-saas-lab6-update-tenant-stack-map`
- ✅ All Lambda functions follow naming convention

---

### 4. Custom Resources

**File:** `Lab6/server/nested_templates/custom_resources.yaml`

**Status:** ✅ **VERIFIED**

**Configuration:**
1. ✅ `ServiceTimeout: 300` - Present on both custom resources
   - `UpdateSettingsTable`
   - `UpdateTenantStackMap`

2. ✅ Correct table name references:
   - `ServerlessSaaS-Settings-lab6`
   - `ServerlessSaaS-TenantStackMapping-lab6`

---

### 5. S3 Buckets

**Naming Convention:** `serverless-saas-lab6-{type}-${ShortId}`

**Status:** ✅ **VERIFIED**

**Bucket Types:**
- ✅ `serverless-saas-lab6-admin-${ShortId}`
- ✅ `serverless-saas-lab6-landing-${ShortId}`
- ✅ `serverless-saas-lab6-app-${ShortId}`

**ShortId Technique:**
```yaml
ShortId: !Select [0, !Split ['-', !Select [2, !Split ['/', !Ref 'AWS::StackId']]]]
```

---

### 6. CloudFormation Stacks

**Status:** ✅ **VERIFIED**

**Stack Names:**
1. ✅ `serverless-saas-workshop-shared-lab6` (shared infrastructure)
2. ✅ `serverless-saas-workshop-tenant-lab6` (tenant template)
3. ✅ `serverless-saas-pipeline-lab6` (CI/CD pipeline) - **FIXED**

---

### 7. CloudFormation Exports

**Naming Convention:** `Serverless-SaaS-{ExportName}-lab6`

**Status:** ✅ **VERIFIED**

**Key Exports:**
- ✅ All exports have `-lab6` suffix
- ✅ No cross-lab dependencies

---

### 8. API Gateway

**Status:** ✅ **VERIFIED**

**Resources:**
- ✅ API Gateway REST APIs have lab6 naming
- ✅ Usage Plans: `serverless-saas-lab6-{tier}-plan`
- ✅ API Keys: `serverless-saas-lab6-{tier}-apikey`

**CloudWatch Role:**
- ✅ `apigateway-cloudwatch-publish-role` (NO lab suffix - shared resource, correct)

---

### 9. Cognito User Pools

**Status:** ✅ **VERIFIED**

**User Pools:**
- ✅ `PooledTenant-ServerlessSaaS-lab6-UserPool`
- ✅ `OperationUsers-ServerlessSaas-lab6-UserPool`

**Domains:**
- ✅ `serverless-saas-lab6-pool-${ShortId}`
- ✅ `serverless-saas-lab6-ops-${ShortId}`

---

### 10. IAM Roles and Policies

**Status:** ✅ **VERIFIED**

**Naming Convention:** `{role-name}-lab6`

**All IAM resources follow the convention:**
- ✅ Execution roles have `-lab6` suffix
- ✅ Policies have `-lab6` suffix
- ✅ No region suffix (IAM is global)

---

### 11. Deployment Scripts

**File:** `Lab6/scripts/deployment.sh`

**Status:** ✅ **UPDATED**

**Features Added:**
1. ✅ Command-line argument parsing (-s, -b, -p, -c)
2. ✅ Pipeline deployment (CodeCommit + CDK)
3. ✅ DynamoDB table wait logic
4. ✅ CloudFront cache invalidation
5. ✅ Better error handling
6. ✅ Final deployment summary

**DynamoDB Wait Tables:**
```bash
ServerlessSaaS-Settings-lab6
ServerlessSaaS-TenantStackMapping-lab6
ServerlessSaaS-TenantDetails-lab6
ServerlessSaaS-TenantUserMapping-lab6
```

---

### 12. Cleanup Scripts

**File:** `Lab6/scripts/cleanup.sh`

**Status:** ✅ **VERIFIED**

**Cleanup Order:**
1. ✅ Tenant stacks (stack-*)
2. ✅ Tenant template stack
3. ✅ S3 buckets (emptied first)
4. ✅ Shared infrastructure stack
5. ✅ Pipeline artifacts bucket
6. ✅ Pipeline stack (`serverless-saas-pipeline-lab6`)
7. ✅ SAM artifacts
8. ✅ Cognito User Pools
9. ✅ Verification

---

## 🔍 No Lab5 References Found

**Verification:** Searched all Lab6 YAML and TypeScript files
- ✅ No hardcoded `lab5` references
- ✅ All resources properly namespaced with `lab6`

---

## 📋 Deployment Checklist

Before deploying Lab6, ensure:

- [x] Pipeline stack name updated to `serverless-saas-pipeline-lab6`
- [x] Pipeline resource name updated to `serverless-saas-pipeline-lab6`
- [x] All DynamoDB tables have `-lab6` suffix
- [x] All Lambda functions have `serverless-saas-lab6-` prefix
- [x] All S3 buckets use ShortId technique with `lab6` prefix
- [x] All CloudFormation exports have `-lab6` suffix
- [x] Custom resources have `ServiceTimeout: 300`
- [x] Deployment script has all features from Lab5
- [x] Cleanup script handles all Lab6 resources

---

## 🚀 Ready to Deploy

Lab6 is now fully configured with:
- ✅ Proper naming conventions
- ✅ No cross-lab dependencies
- ✅ Complete pipeline infrastructure
- ✅ All necessary dependencies
- ✅ Comprehensive deployment and cleanup scripts

**Deploy Command:**
```bash
cd Lab6/scripts
./deployment.sh -s -c
```

This will deploy:
1. CI/CD Pipeline (CodeCommit + CDK)
2. Shared Infrastructure (DynamoDB, Lambda, API Gateway, Cognito)
3. Tenant Template
4. Client Applications (Admin, Landing, Application)
