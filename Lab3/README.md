# Lab 3: Adding Multi-Tenancy to Microservices

Introduces pooled multi-tenant architecture with authentication, tenant-aware data partitioning, and per-tenant observability.

## Quick Start

```bash
# Deploy (server + client, ~15 min)
cd workshop/Lab3/scripts
./deployment.sh -s -c --email <email> --tenant-email <tenant-email> --profile <profile>

# Get URLs
./geturl.sh --profile <profile>

# Cleanup (~15-20 min)
echo "yes" | ./cleanup.sh --profile <profile>
```

## Architecture Overview

Lab 3 deploys **two CloudFormation stacks** implementing a pooled SaaS model:

```
 Admin Console / Landing Page / SaaS Application  (Angular, S3 + CloudFront)
                        │
          ┌─────────────┴──────────────┐
          ▼                            ▼
   Admin API Gateway            Tenant API Gateway
   (shared stack)               (tenant stack)
          │                            │
   Shared Service               Tenant
   Authorizer                   Authorizer
          │                            │
          ▼                            ▼
   Tenant/User Mgmt            Product & Order
   Lambda Functions             Lambda Functions
          │                       │    │
          ▼                       ▼    ▼
   Cognito User Pools      Pooled DynamoDB Tables
   TenantDetails Table     (Product, Order)
```

**Shared stack** (`serverless-saas-shared-lab3`): Cognito (2 user pools), Admin API Gateway, 16 tenant/user management Lambdas, 3 CloudFront distributions, 3 S3 buckets, 2 DynamoDB tables.

**Tenant stack** (`serverless-saas-tenant-lab3`): Tenant API Gateway, 10 product/order Lambdas + authorizer, 2 pooled DynamoDB tables, Lambda Layer with shared utilities.

## Directory Structure

```
Lab3/
├── client/              # Angular apps (Admin, Landing, Application)
├── server/
│   ├── shared-template.yaml    # Shared stack (Cognito, Admin API, UI hosting)
│   ├── tenant-template.yaml    # Tenant stack (business logic, pooled tables)
│   ├── ProductService/         # Product CRUD (Python)
│   ├── OrderService/           # Order CRUD (Python)
│   ├── TenantManagementService/# Tenant registration, management, users
│   ├── Resources/              # Lambda authorizers
│   └── layers/                 # Shared layer: logger, metrics_manager, auth_manager
├── scripts/
│   ├── deployment.sh           # Full deployment (-s server, -c client, -b bootstrap, -t tenant)
│   ├── cleanup.sh              # Tear down all resources
│   ├── deploy-updates.sh       # Quick code sync via sam sync
│   └── geturl.sh               # Retrieve CloudFront URLs
└── extra-info/
    └── LAB_REFERENCE.md        # Operational reference (commands, troubleshooting)
```

## Prerequisites

- AWS CLI, SAM CLI, Python 3.14, Node.js/npm, Docker
- AWS profile with permissions for Lambda, DynamoDB, API Gateway, Cognito, CloudFront, S3
- **No dependency on other labs** — Lab 3 is fully self-contained

## Key Concepts

### Dual API Gateway Pattern

- **Admin API Gateway** (shared stack): Tenant registration, tenant/user CRUD. Protected by Shared Service Authorizer with role-based access (SystemAdmin gets full access; TenantAdmin is scoped to their tenant).
- **Tenant API Gateway** (tenant stack): Product/order CRUD. Protected by Tenant Authorizer that extracts `tenantId` from JWT and passes it as Lambda context.

The Application UI requires **both** API URLs — `regApiGatewayUrl` for admin operations and `apiGatewayUrl` for business operations.

### Data Partitioning (Pooled DynamoDB)

All tenants share the same DynamoDB tables. Isolation is achieved via composite keys:

- **Partition key**: `shardId` = `{tenantId}-{randomSuffix}` (suffix 1–9)
- **Sort key**: `productId` or `orderId`

Queries fan out across all 9 shard partitions in parallel threads, preventing hot partitions while maintaining tenant isolation.

### Lambda Layers

Shared code deployed as a Lambda Layer (`layers/`):

| Module | Purpose |
|--------|---------|
| `auth_manager.py` | Role-checking helpers (SystemAdmin, TenantAdmin, TenantUser) |
| `logger.py` | Structured logging with `tenant_id` context via Powertools |
| `metrics_manager.py` | CloudWatch EMF metrics with `tenant_id` dimension |

### Multi-Tenant Observability

- **Logs**: Structured JSON with `tenant_id` field — filter with `{ $.tenant_id = "tenant1" }`
- **Metrics**: CloudWatch EMF under `ServerlessSaaS` namespace, dimensioned by `tenant_id` and `service`
- **Traces**: X-Ray with `TenantId` annotation for per-tenant trace filtering

## Deployment Details

### Flags

| Flag | Description |
|------|-------------|
| `-s` / `--server` | Deploy both shared + tenant stacks |
| `-b` / `--bootstrap` | Deploy shared stack only |
| `-t` / `--tenant` | Deploy tenant stack only |
| `-c` / `--client` | Build and deploy Angular UIs |
| `-e` / `--email` | Admin user email |
| `-te` / `--tenant-email` | Tenant admin email (enables auto-tenant creation) |
| `--profile` | AWS CLI profile (**required**) |
| `--region` | AWS region (default: `us-east-1`) |

### Quick Code Updates

For iterating on Lambda code without full redeployment:

```bash
cd workshop/Lab3/scripts
./deploy-updates.sh --profile <profile>
```

Uses `sam sync --code` to push code changes to both stacks.

## Verification

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name serverless-saas-shared-lab3 \
  --profile <profile> --query 'Stacks[0].StackStatus'
aws cloudformation describe-stacks --stack-name serverless-saas-tenant-lab3 \
  --profile <profile> --query 'Stacks[0].StackStatus'

# List Lab3 Lambda functions
aws lambda list-functions --profile <profile> \
  --query 'Functions[?contains(FunctionName, `lab3`)].FunctionName'

# List DynamoDB tables
aws dynamodb list-tables --profile <profile> \
  --query 'TableNames[?contains(@, `lab3`)]'
```

### Testing Multi-Tenancy

1. Open the App Site URL and log in as tenant1 admin
2. Create products/orders
3. Log out, log in as tenant2 admin
4. Verify tenant2 cannot see tenant1's data
5. Check DynamoDB — `shardId` should contain the respective `tenantId`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Stack already exists | Run cleanup, wait for completion, then redeploy |
| Unauthorized error | Re-login via Cognito; check JWT expiry |
| Missing products/orders | Verify both stacks deployed; Application needs both API URLs |
| Metrics not appearing | Wait 5–10 min; check `ServerlessSaaS` namespace in CloudWatch |
| SAM build cache issues | Delete `server/.aws-sam/` and rebuild |

See [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) for detailed troubleshooting and operational notes.

## Next Steps

**Lab 4**: Isolating Tenant Data — adds IAM-based tenant isolation with STS to prevent cross-tenant data access in the pooled model.

## Resources

- [Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Lambda Powertools Python](https://docs.powertools.aws.dev/lambda/python/latest/)
- [CloudWatch EMF](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [SaaS Tenant Isolation](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-isolation.html)
