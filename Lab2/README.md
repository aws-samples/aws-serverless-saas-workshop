# Lab 2: Introducing SaaS Shared Services

Build multi-tenant shared services with tenant registration, user management, and admin capabilities using Cognito, Lambda, API Gateway, and DynamoDB.

## Architecture

```
┌──────────────┐     ┌──────────────┐
│  Admin UI    │     │  Landing UI  │
│ (CloudFront) │     │ (CloudFront) │
└──────┬───────┘     └──────┬───────┘
       └───────┬────────────┘
               ▼
       ┌───────────────┐
       │  API Gateway   │  (Admin API + Authorizer)
       └───────┬───────┘
               ▼
  ┌────────────────────────────┐
  │     Lambda Functions (16)  │
  │  Tenant Mgmt │ User Mgmt  │
  └───────┬────────────┬───────┘
          ▼            ▼
   ┌───────────┐ ┌───────────┐
   │ DynamoDB  │ │  Cognito  │
   │ (2 tables)│ │ (2 pools) │
   └───────────┘ └───────────┘
```

**AWS Services:** API Gateway, Lambda (Python 3.14), DynamoDB, Cognito, CloudFront, S3, CloudWatch, IAM, X-Ray

**Stack name:** `serverless-saas-lab2`

## Directory Structure

```
Lab2/
├── client/          # Angular apps (Admin + Landing)
├── server/          # SAM template + Lambda functions
│   ├── template.yaml
│   ├── nested_templates/   # Cognito, API GW, DynamoDB, Lambda, UI
│   ├── TenantManagementService/  # Tenant + user + registration handlers
│   ├── OrderService/       # Order CRUD (placeholder for later labs)
│   ├── ProductService/     # Product CRUD (placeholder for later labs)
│   ├── Resources/          # Shared authorizer
│   └── layers/             # Common utilities (logger, utils)
├── scripts/         # Deploy, cleanup, geturl, deploy-updates
├── tests/           # Registration endpoint test
└── extra-info/      # Operational reference
```

## Prerequisites

- AWS CLI v2, SAM CLI v1+, Python 3.14, Node.js 18+, Docker
- AWS profile configured with sufficient permissions
- Lab 1 concepts understood (not a deployment dependency)

## Key Concepts

- **Tenant Registration Flow:** Landing page → `RegisterTenantFunction` → invokes `CreateTenantFunction` + `CreateTenantAdminUserFunction` via internal API calls
- **Dual Cognito Pools:** `OperationUsers` pool for system admins, `PooledTenant` pool for tenant users
- **JWT Authorizer:** `SharedServicesAuthorizerFunction` validates tokens against the OperationUsers pool, builds IAM policy
- **DynamoDB Tables:** `TenantDetails` (tenant metadata), `TenantUserMapping` (user-tenant relationships)
- **Resource Isolation:** All resources include `lab2` in names; cleanup script filters by lab ID

## Quick Start

```bash
# Deploy (server + client, ~10-15 min)
cd workshop/Lab2/scripts
./deployment.sh -s -c --email your@email.com --profile <profile>

# Get URLs
./geturl.sh --profile <profile>

# Cleanup (~15-20 min)
echo "yes" | ./cleanup.sh --profile <profile>
```

> **Note:** Admin credentials (username + temp password) are printed at the end of deployment. You must change the password on first login.

## Deployment Options

| Flag | Description |
|------|-------------|
| `-s, --server` | Deploy backend (SAM build + deploy) |
| `-c, --client` | Deploy frontend (Angular build + S3 sync) |
| `--email <email>` | Admin email (required with `-c`) |
| `--profile <name>` | AWS CLI profile |
| `--region <region>` | AWS region (default: `us-east-1`) |
| `--stack-name <name>` | Stack name (default: `serverless-saas-lab2`) |

## Verification

```bash
# Stack status
aws cloudformation describe-stacks --stack-name serverless-saas-lab2 \
  --profile <profile> --query 'Stacks[0].StackStatus'
# Expected: "CREATE_COMPLETE"

# Lambda functions (expect 16)
aws lambda list-functions --profile <profile> \
  --query 'Functions[?contains(FunctionName, `lab2`)].FunctionName'

# DynamoDB tables
aws dynamodb list-tables --profile <profile> \
  --query 'TableNames[?contains(@, `lab2`)]'
# Expected: ["ServerlessSaaS-TenantDetails-lab2", "ServerlessSaaS-TenantUserMapping-lab2"]
```

## Testing

**Via Landing Page:** Open Landing Site URL → Sign Up → fill tenant details (name, email, tier) → submit

**Via API:**
```bash
API_URL=$(aws cloudformation describe-stacks --stack-name serverless-saas-lab2 \
  --profile <profile> --query 'Stacks[0].Outputs[?OutputKey==`AdminApi`].OutputValue' --output text)

curl -X POST ${API_URL}/registration \
  -H "Content-Type: application/json" \
  -d '{"tenantName":"Test Co","tenantEmail":"test@example.com","tenantTier":"basic"}'
```

**Test script:**
```bash
./tests/test-registration.sh $API_URL
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Email parameter required | `--email` is required when deploying client (`-c`) |
| CloudFront 403 | Wait 15-20 min for distribution propagation |
| Cognito domain conflict | Use a different `--stack-name` (domains are globally unique) |
| API returns Unauthorized | JWT expired (1hr TTL); re-authenticate via Admin UI |
| Cleanup takes too long | CloudFront deletion takes 15-30 min — do not interrupt |

See [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) for detailed operational reference including cleanup security notes and stack outputs.

## Resources

- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/latest/developerguide/)
- [SaaS Architecture Lens](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)
- [Deployment & Cleanup Manual](../extra-info/DEPLOYMENT_CLEANUP_MANUAL.md)

## Next Step

**→ Lab 3:** Adding Multi-Tenancy to Microservices — tenant isolation and partitioned data access
