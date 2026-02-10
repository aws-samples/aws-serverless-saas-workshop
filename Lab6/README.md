# Lab 6: Tenant Throttling and API Quotas

Implement tier-based API rate limiting using API Gateway Usage Plans and API Keys in a multi-tenant SaaS application.

## Architecture Overview

Lab 6 builds on Lab 5's pooled/siloed deployment model and adds **API Gateway usage plans** to enforce per-tenant throttling:

```
CloudFront (Admin, Landing, App UIs)
        │
        ▼
  Admin API Gateway ──── Usage Plans + API Keys (throttling)
        │                  • Basic:    50 req/s,  50 burst,   500/day
        │                  • Standard: 75 req/s, 100 burst, 3,000/day
        │                  • Premium: 100 req/s, 200 burst, 5,000/day
        │                  • Platinum: 300 req/s, 300 burst, 10,000/day
        ▼
  Lambda Authorizer (JWT validation + tenant context)
        │
   ┌────┴────┐
   ▼         ▼
 Pooled    Siloed (Platinum)
 Model     Model
 (Basic/   ├─ Dedicated Cognito
  Std/     ├─ Dedicated DynamoDB
  Premium) ├─ Dedicated Lambda
           └─ Dedicated API Gateway
```

**AWS Services:** API Gateway (usage plans, API keys), Lambda (Python 3.14), DynamoDB, Cognito, CloudFront, S3, CodePipeline, CodeBuild, CodeCommit, CloudWatch.

**Stacks deployed:**
- `serverless-saas-shared-lab6` — Shared services, Cognito, API Gateway with usage plans, UIs
- `serverless-saas-pipeline-lab6` — CDK CI/CD pipeline (CodePipeline + CodeBuild)
- `stack-lab6-pooled` — Pooled tenant resources (auto-created by pipeline)
- `stack-<tenantId>-lab6` — Per-Platinum-tenant dedicated resources

## Directory Structure

```
Lab6/
├── client/              # Angular UIs (Admin, Landing, Application)
├── server/
│   ├── shared-template.yaml       # Main SAM template (orchestrates nested stacks)
│   ├── tenant-template.yaml       # Per-tenant resources (Product/Order CRUD, API GW)
│   ├── tenant-buildspec.yml       # CodeBuild spec for tenant stack deployments
│   ├── nested_templates/          # Nested CFN: apigateway, cognito, tables, lambdas, UI
│   ├── TenantManagementService/   # Tenant registration, provisioning, user mgmt
│   ├── ProductService/            # Product CRUD Lambda handlers
│   ├── OrderService/              # Order CRUD Lambda handlers
│   ├── Resources/                 # Lambda authorizers (shared + tenant)
│   ├── layers/                    # Shared Lambda layer (auth, logging, metrics, utils)
│   ├── custom_resources/          # CFN custom resources (settings, usage plans)
│   └── TenantPipeline/            # CDK app for CI/CD pipeline
├── scripts/             # deployment.sh, cleanup.sh, geturl.sh
├── tests/               # test-basic-tier-throttling.sh
└── extra-info/          # LAB_REFERENCE.md (operational details)
```

## Prerequisites

- Labs 1-5 concepts understood (multi-tenant SaaS, pooled/siloed models)
- AWS CLI, SAM CLI, Python 3.14, Node.js, Git, jq installed
- AWS profile configured (default region: `us-east-1`)

## Key Concepts

### API Gateway Usage Plans
Usage plans define **rate limit** (sustained req/s), **burst limit** (max concurrent), and **daily quota** per tier. Each tenant gets an API key mapped to their tier's usage plan during registration.

### Throttling Flow
1. Client sends request with API key (injected by authorizer from JWT)
2. API Gateway matches API key → usage plan → applies throttling limits
3. Within limits → request proceeds to Lambda
4. Exceeds limits → API Gateway returns **429 Too Many Requests**

### Tenant Registration with API Keys
During registration (`tenant-registration.py`), each tenant is assigned the API key for their tier (Basic/Standard/Premium/Platinum). This key is stored in the `TenantDetails` DynamoDB table and used by the authorizer to enforce throttling.

### Pooled vs Siloed Throttling
- **Pooled** (Basic/Standard/Premium): Share API Gateway; throttled independently via per-tier API keys
- **Siloed** (Platinum): Dedicated API Gateway with Platinum usage plan; complete isolation

## Deployment

```bash
cd workshop/Lab6/scripts
./deployment.sh -s -c --profile <your-profile>
```

**Flags:** `-s` deploys server (shared stack + pipeline), `-c` deploys client UIs.
**Duration:** ~20-25 minutes (includes waiting for pipeline to create pooled stack).

The deployment script:
1. Builds and deploys the shared stack (SAM)
2. Creates CodeCommit repo and pushes code
3. Deploys CI/CD pipeline (CDK)
4. Waits for pipeline to auto-create `stack-lab6-pooled`
5. Builds and deploys three Angular UIs to S3/CloudFront

**Get URLs after deployment:**
```bash
./geturl.sh --profile <your-profile>
```

## Testing Throttling

The throttling test sends 1000 concurrent requests to verify rate limiting:

```bash
cd workshop/Lab6/tests

# Get a JWT token: login to the App UI → browser dev tools → Local Storage → copy idToken
./test-basic-tier-throttling.sh "<jwt-token>" --profile <your-profile>
```

**Expected output:** Mix of `200` (success) and `429` (throttled) status codes. Higher tiers will see fewer 429s.

## Cleanup

```bash
cd workshop/Lab6/scripts
echo "yes" | ./cleanup.sh --profile <your-profile>
```

**Duration:** ~15-20 minutes. Deletes all `lab6` stacks, S3 buckets, Cognito users, CloudWatch logs, and pipeline resources.

## Troubleshooting

| Issue | Solution |
|-------|---------|
| `stack-lab6-pooled` doesn't exist | Wait for pipeline; check CodeBuild logs; re-trigger pipeline |
| `KeyError('Item')` on tenant registration | Pooled stack not ready — wait for pipeline to complete |
| All 401s in throttle test | JWT expired — re-login and get fresh token |
| All 403s in throttle test | API key missing — verify tenant record in DynamoDB |
| Pipeline Python version error | `tenant-buildspec.yml` uses `--use-container` for sam build |

## Operational Reference

See [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) for detailed stack names, resource naming conventions, throttling limits, deployment order, and applied fixes.
