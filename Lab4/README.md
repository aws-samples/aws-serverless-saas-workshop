# Lab 4: Isolating Tenant Data in a Pooled Model

Implement IAM policy-based tenant data isolation in shared DynamoDB tables using STS temporary credentials.

## Quick Start

```bash
# Deploy (~18-20 min)
cd workshop/Lab4/scripts
./deployment.sh -s -c --email <admin-email> --tenant-email <tenant-email> --profile <profile>

# Get URLs
./geturl.sh --profile <profile>

# Cleanup (~15-20 min)
echo "yes" | ./cleanup.sh --profile <profile>
```

## Architecture Overview

Lab 4 deploys **two CloudFormation stacks**:

**Shared Stack** (`serverless-saas-shared-lab4`) — Tenant lifecycle & admin:
- 16 Lambda functions (Python 3.14) — tenant/user management
- 2 DynamoDB tables — TenantDetails, TenantUserMapping
- 2 Cognito User Pools — PooledTenant, OperationUsers
- Admin API Gateway, 3 CloudFront distributions, 3 S3 buckets

**Tenant Stack** (`serverless-saas-tenant-lab4`) — Business services with isolation:
- 11 Lambda functions — Product/Order CRUD + Business Services Authorizer
- 2 DynamoDB tables — Product-pooled-lab4, Order-pooled-lab4 (shared across tenants)
- Tenant API Gateway with custom Lambda authorizer
- IAM roles with tenant-scoped DynamoDB access policies

### Tenant Isolation Flow

```
User authenticates → Cognito JWT (contains tenantId)
  → API Gateway invokes Business Services Authorizer
    → Authorizer validates JWT, extracts tenantId
    → STS AssumeRole with inline policy scoped to tenant's DynamoDB rows
    → Scoped credentials passed to Lambda via authorizer context
      → Lambda creates DynamoDB client with scoped credentials
        → IAM enforces row-level access via dynamodb:LeadingKeys condition
```

The `dynamodb:LeadingKeys` condition restricts access to rows where the partition key (`shardId`) matches `{tenantId}-*`, preventing cross-tenant data access.

## Directory Structure

```
Lab4/
├── client/                  # Angular UIs (Admin, Landing, Application)
├── scripts/                 # deployment.sh, cleanup.sh, geturl.sh
├── server/
│   ├── shared-template.yaml # Shared stack (nested: cognito, tables, lambdas, API, UI)
│   ├── tenant-template.yaml # Tenant stack (products, orders, authorizer, API)
│   ├── Resources/           # tenant_authorizer.py, shared_service_authorizer.py
│   ├── ProductService/      # Product CRUD Lambda handlers + DAL
│   ├── OrderService/        # Order CRUD Lambda handlers + DAL
│   ├── TenantManagementService/  # Tenant registration, management, user mgmt
│   ├── layers/              # Shared layer: auth_manager, logger, metrics, utils
│   └── nested_templates/    # CloudFormation nested stacks
└── extra-info/              # LAB_REFERENCE.md — operational reference
```

## Prerequisites

- **AWS CLI v2** and **SAM CLI** installed
- **Python 3.14** (Lambda runtime)
- **Node.js/npm** (for client UI builds, only needed with `-c` flag)
- AWS profile with admin permissions configured

## Key Concepts

### IAM Policy-Based Isolation
Each tenant's DynamoDB access is restricted by IAM policies generated at request time. The `auth_manager.py` layer builds policies with `dynamodb:LeadingKeys` conditions scoped to the tenant ID, ensuring row-level security in shared tables.

### STS Credential Scoping
The Business Services Authorizer (`tenant_authorizer.py`) calls `sts:AssumeRole` with an inline policy that limits DynamoDB operations to the authenticated tenant's rows. These temporary credentials are passed through the API Gateway authorizer context to downstream Lambda functions.

### Shard-Based Partition Keys
DynamoDB tables use a composite key: `shardId` (partition) = `{tenantId}-{suffix}`, where suffix is 1-9 for write distribution. The DAL queries all partitions in parallel threads when listing items.

### Key Implementation Files

| File | What It Does |
|------|-------------|
| `server/Resources/tenant_authorizer.py` | Validates JWT, generates tenant-scoped STS credentials |
| `server/layers/auth_manager.py` | Builds IAM policies with `LeadingKeys` conditions per user role |
| `server/ProductService/product_service_dal.py` | Creates DynamoDB client using scoped STS credentials |

## Deployment Details

### Flags

| Flag | Description |
|------|-------------|
| `-s` / `--server` | Deploy both shared and tenant stacks |
| `-b` / `--bootstrap` | Deploy only shared stack |
| `-t` / `--tenant` | Deploy only tenant stack |
| `-c` / `--client` | Build and deploy Angular client UIs |
| `-e` / `--email` | Admin user email |
| `-te` / `--tenant-email` | Tenant email (auto-creates two sample tenants) |
| `--profile` | AWS CLI profile (required) |

### Verification

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name serverless-saas-shared-lab4 \
  --profile <profile> --query 'Stacks[0].StackStatus'
aws cloudformation describe-stacks --stack-name serverless-saas-tenant-lab4 \
  --profile <profile> --query 'Stacks[0].StackStatus'

# Check DynamoDB tables
aws dynamodb list-tables --profile <profile> | grep lab4

# Check Lambda function count (expect ~27)
aws lambda list-functions --profile <profile> --query 'Functions[?contains(FunctionName,`lab4`)].FunctionName' --output text | wc -w
```

## Testing Tenant Isolation

1. **Create two tenants** via the Landing Site (or use auto-created tenants from `--tenant-email`)
2. **Log in as Tenant A** → create products/orders
3. **Log in as Tenant B** (incognito) → create different products/orders
4. **Verify isolation**: each tenant sees only their own data
5. **DynamoDB scan** confirms all data exists but with tenant-prefixed partition keys:
   ```bash
   aws dynamodb scan --table-name Product-pooled-lab4 --profile <profile> \
     --query 'Items[*].[shardId.S, productId.S, name.S]' --output table
   ```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| SAM build fails (Python) | Verify `python3.14` is installed; do NOT change runtime version |
| Stack creation fails | Check `describe-stack-events` for the failed resource; ensure no name conflicts |
| Can see other tenant's data | Check authorizer logs; verify `dynamodb:LeadingKeys` in generated policy |
| 403 on all API calls | JWT may be expired (1hr default); re-login. Check authorizer Lambda logs |
| CloudFront 403/404 | Wait 15-20 min after deploy for distribution propagation |
| Cleanup hangs | CloudFront deletion takes 15-30 min; do not interrupt |

## Cleanup

```bash
cd workshop/Lab4/scripts
echo "yes" | ./cleanup.sh --profile <profile>
```

Deletes: CloudFormation stacks, S3 buckets, DynamoDB tables, Cognito pools/users, IAM roles, CloudWatch logs, SAM bootstrap buckets. Follows secure deletion order (stacks before S3) to prevent CloudFront Origin Hijacking.

## Additional Resources

- [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) — Operational reference with detailed troubleshooting
- [Solution/Lab4/](../Solution/Lab4/) — Reference implementation (do not modify)
- [AWS IAM Policy Conditions](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition.html)
- [DynamoDB Fine-Grained Access Control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html)
- [AWS STS AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [API Gateway Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
