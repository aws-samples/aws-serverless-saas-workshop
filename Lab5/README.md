# Lab 5: Tier-Based Deployment Strategies

Implement pooled vs. siloed multi-tenant architectures with automated CodePipeline provisioning for premium tenants.

## Architecture Overview

Lab 5 deploys a hybrid multi-tenant SaaS application with two deployment models:

- **Pooled (Basic/Standard/Premium)** — Tenants share Lambda functions, DynamoDB tables, Cognito user pool, and API Gateway
- **Siloed (Platinum)** — Each tenant gets dedicated infrastructure provisioned automatically via CodePipeline

```
                         CloudFront CDN
              ┌──────────┬──────────┬──────────┐
              │ Admin UI │ Landing  │  App UI  │
              └──────────┴──────────┴──────────┘
                              │
                     Admin API Gateway
                              │
                ┌─────────────┴─────────────┐
                │     Shared Services       │
                │  Tenant Mgmt · User Mgmt  │
                │  Registration · Auth      │
                │  DynamoDB · Cognito       │
                └─────────────┬─────────────┘
                    ┌─────────┴─────────┐
          Pooled Model            Siloed Model
    (Basic/Standard/Premium)       (Platinum)
     Shared resources          CodePipeline → CodeBuild
     Tenant-ID partitioning    → Per-tenant CFN stack
                               (Cognito + DynamoDB +
                                Lambda + API Gateway)
```

**AWS Services**: Lambda (Python 3.14), DynamoDB, Cognito, API Gateway, CloudFront, S3, CodePipeline, CodeBuild, CodeCommit, CloudFormation, CDK

### CloudFormation Stacks

| Stack | Description |
|-------|-------------|
| `serverless-saas-shared-lab5` | Shared services: 16 Lambdas, 4 DynamoDB tables, 2 Cognito pools, Admin API GW, 3 CloudFront distributions + S3 |
| `serverless-saas-pipeline-lab5` | CDK-deployed CI/CD: CodePipeline, CodeBuild, CodeCommit repo, deploy Lambda |
| `stack-<tenantId>-lab5` | Per-Platinum-tenant: dedicated Cognito, DynamoDB, Lambda, API Gateway |

## Directory Structure

```
Lab5/
├── client/                  # Angular UIs (Admin, Landing, Application)
├── server/
│   ├── shared-template.yaml # SAM template — shared services stack
│   ├── tenant-template.yaml # SAM template — per-tenant stack (pooled + silo)
│   ├── tenant-buildspec.yml # CodeBuild spec for tenant stack deployment
│   ├── TenantPipeline/      # CDK app defining the CI/CD pipeline
│   ├── TenantManagementService/  # Tenant registration, provisioning, management
│   ├── ProductService/      # Product CRUD (per-tenant)
│   ├── OrderService/        # Order CRUD (per-tenant)
│   ├── Resources/           # Lambda authorizers
│   ├── layers/              # Shared Lambda layer (auth, logging, metrics)
│   ├── nested_templates/    # CloudFormation nested stacks
│   └── custom_resources/    # CFN custom resources for settings/config
├── scripts/
│   ├── deployment.sh        # Deploy server (-s), pipeline (-p), bootstrap (-b), client (-c)
│   ├── cleanup.sh           # Full cleanup with lab-isolation filtering
│   ├── deploy-updates.sh    # Sync Lambda code changes (sam sync)
│   └── geturl.sh            # Retrieve application URLs from stack outputs
└── extra-info/
    └── LAB_REFERENCE.md     # Operational reference (troubleshooting, commands)
```

## Prerequisites

- AWS CLI, SAM CLI, CDK CLI (`npm install -g aws-cdk`), Python 3, Node.js, Git
- AWS profile configured (e.g., `serverless-saas-demo`)
- Familiarity with Labs 1–4 concepts (recommended)

## Deployment

> **⏱ ~20-25 minutes** — Run in your terminal, not from an agent (long-running).

```bash
cd workshop/Lab5/scripts
./deployment.sh -s -c --profile <profile>
```

This deploys:
1. **Bootstrap** (`-s`): Shared SAM stack (Lambda, DynamoDB, Cognito, API GW, CloudFront/S3)
2. **Pipeline** (`-s`): CDK bootstrap → CodeCommit repo + push → CDK deploy (CodePipeline stack)
3. **Client** (`-c`): Build & upload 3 Angular apps to S3, invalidate CloudFront

Retrieve URLs after deployment:
```bash
./geturl.sh --profile <profile>
```

### Partial Deployments

```bash
./deployment.sh -b --profile <profile>   # Bootstrap only
./deployment.sh -p --profile <profile>   # Pipeline only
./deployment.sh -c --profile <profile>   # Client only
```

## Key Concepts

### Tenant Provisioning Flow

**Pooled tenants** (Basic/Standard/Premium):
1. Tenant registers via Landing UI → shared Cognito pool → shared DynamoDB tables → shared API

**Siloed tenants** (Platinum):
1. Tenant created via Admin UI or Landing registration
2. `tenant-provisioning.py` writes to `TenantStackMapping` table and triggers `serverless-saas-pipeline-lab5`
3. CodePipeline: Source (CodeCommit) → Build (SAM build `tenant-template.yaml`) → Deploy (Lambda creates/updates CFN stack)
4. Dedicated stack created: `stack-<tenantId>-lab5` with isolated Cognito, DynamoDB, Lambda, API GW

### Pipeline Architecture (CDK)

Defined in `server/TenantPipeline/lib/serverless-saas-stack.ts`:
- **Source stage**: CodeCommit (`aws-serverless-saas-workshop`, `main` branch)
- **Build stage**: CodeBuild (STANDARD_7_0 image, runs `tenant-buildspec.yml` → `sam build --use-container` + `sam package`)
- **Deploy stage**: Lambda (`lambda-deploy-tenant-stack.py`) iterates `TenantStackMapping` table, creates/updates CFN stacks per tenant

### Tenant Template (`tenant-template.yaml`)

Uses `TenantIdParameter` with conditions:
- `IsPooledDeploy` (tenantId = "pooled"): Shared resources, no dedicated IAM policies
- `IsSiloDeploy` (tenantId ≠ "pooled"): Dedicated IAM policies scoped to tenant-specific DynamoDB tables

Resources per tenant stack: Product/Order DynamoDB tables, 10 Lambda functions (CRUD), authorizer, API Gateway with OpenAPI spec.

## Testing

1. **Pooled tenant**: Register via Landing UI with Basic/Standard/Premium tier → verify no dedicated CFN stack created
2. **Platinum tenant**: Create via Admin UI → monitor pipeline in CodePipeline console → verify `stack-<tenantId>-lab5` reaches `CREATE_COMPLETE`
3. **Data isolation**: Pooled tenants share `Product-pooled-lab5` table (partitioned by tenantId); Platinum tenants get `Product-<tenantId>-lab5`

## Cleanup

> **⏱ ~15-20 minutes** — Run in your terminal.

```bash
cd workshop/Lab5/scripts
echo "yes" | ./cleanup.sh --profile <profile>
```

Deletion order (security-critical): tenant stacks → shared stack (CloudFront must fully delete) → S3 buckets → pipeline stack → CDK assets. This prevents [CloudFront Origin Hijacking](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html).

## Troubleshooting

See [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) for detailed troubleshooting commands covering:
- DynamoDB table not found
- CloudFormation export errors
- Pipeline not triggering
- CDK bootstrap failures
- Failed tenant stack cleanup
