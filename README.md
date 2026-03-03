# AWS Serverless SaaS Workshop

A hands-on workshop for building multi-tenant SaaS applications on AWS Serverless. Through seven progressive labs, you'll implement tenant isolation, tiered deployments (pooled and siloed), API throttling, and per-tenant cost attribution using Lambda, API Gateway, DynamoDB, Cognito, and more.

## Lab Overview

| Lab | Title | Description | Key AWS Services |
|-----|-------|-------------|------------------|
| [1](Lab1/README.md) | Basic Serverless Web App | Product/order CRUD with Lambda, API Gateway, DynamoDB, and CloudFront | Lambda, API Gateway, DynamoDB, CloudFront, S3 |
| [2](Lab2/README.md) | SaaS Shared Services | Tenant registration, user management, and admin UI with dual Cognito pools | Cognito, Lambda, API Gateway, DynamoDB |
| [3](Lab3/README.md) | Multi-Tenant Microservices | Pooled data partitioning, tenant-aware authorizers, and per-tenant observability | API Gateway, Lambda, DynamoDB, CloudWatch, X-Ray |
| [4](Lab4/README.md) | Tenant Data Isolation | IAM policy-based row-level isolation using STS scoped credentials | IAM, STS, DynamoDB, API Gateway |
| [5](Lab5/README.md) | Tier-Based Deployments | Pooled (Basic/Standard/Premium) vs. siloed (Platinum) with automated CodePipeline provisioning | CodePipeline, CodeBuild, CodeCommit, CDK |
| [6](Lab6/README.md) | API Throttling & Quotas | Per-tier rate limiting via API Gateway Usage Plans and API Keys | API Gateway (Usage Plans, API Keys) |
| [7](Lab7/README.md) | Cost Attribution | Per-tenant cost attribution using CUR data, Athena, Glue, and CloudWatch Logs metering | Athena, Glue, EventBridge, CloudWatch Logs |

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| AWS CLI | v2.x+ | With a configured named profile |
| SAM CLI | ≥ 1.70.0 | |
| Python | 3.14 | Lambda runtime |
| Node.js | v20.x or v22.x (LTS) | For Angular client builds; avoid odd-numbered versions |
| Docker | 20.x+ | Must be running for `sam build` |
| AWS CDK CLI | Latest | Required for Labs 5–6 only (`npm install -g aws-cdk`) |
| Git | Any | |

**AWS Account:** Permissions to create Lambda, API Gateway, DynamoDB, Cognito, S3, CloudFormation, CodePipeline, CloudWatch, and IAM resources.

**Region:** `us-east-1` (default) or `us-west-2`.

See [extra-info/PREREQUISITES.md](extra-info/PREREQUISITES.md) for detailed installation instructions.

## Optional: Python Virtual Environment

The deployment scripts run `pylint` to validate Python code before deploying. If `pylint` is not installed, validation is skipped with a warning — but setting up a virtual environment ensures consistent, clean results.

```bash
cd workshop

# Create the virtual environment
python3 -m venv .venv_py313

# Activate it
source .venv_py313/bin/activate

# Install pylint
pip install pylint

# Deactivate when done (or just close the terminal)
deactivate
```

The deployment scripts automatically detect `.venv_py313` and use it for code validation. You do not need to activate the venv before running scripts — they find it by path.

> **Note:** This is entirely optional. All labs deploy successfully without it; pylint validation will simply be skipped.

## Quick Start — Deploy All Labs

> **⏱ ~15–20 minutes.** Run in your terminal — do NOT run from an automated agent.

```bash
cd workshop

# Deploy all 7 labs in parallel (with automatic Cognito user creation)
./deploy-all.sh --email <your-email> --profile <your-profile>

# Deploy without user creation (create users separately later)
./deploy-all.sh --profile <your-profile>
./scripts/create-workshop-users.sh --email <your-email> --profile <your-profile>
```

### Rollback Behavior

By default, `deploy-all.sh` runs with `--disable-rollback`. This means if a stack fails, CloudFormation preserves the failed resources instead of rolling back, so you can inspect what went wrong and re-run the same command to retry without needing cleanup first.

```bash
# Default behavior (rollback disabled — recommended for workshop/debugging)
./deploy-all.sh --email <your-email> --profile <your-profile>

# Explicitly enable rollback (production-style — failed stacks auto-rollback)
./deploy-all.sh --email <your-email> --profile <your-profile> --enable-rollback
```

Why disable rollback is the default:
- Failed stacks are preserved for analysis — you can inspect CloudFormation events and logs
- Re-running the same command updates the existing stack, retrying only the failed resources
- No need to run cleanup between attempts, saving significant time

### Cleanup All Labs

> **⏱ ~15–30 minutes.** CloudFront deletion is the bottleneck.

```bash
cd workshop
echo "yes" | ./cleanup-all.sh --profile <your-profile>
```

**⚠ Important:**
- Always execute scripts directly (`./script.sh`), never with `bash script.sh`
- `--profile` is **required** on every command
- Do not interrupt cleanup — secure deletion order prevents CloudFront Origin Hijacking

## Individual Lab Deployment

Each lab is self-contained and can be deployed independently. See each lab's README for full details.

```bash
# Example: Deploy Lab 1
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile <your-profile>
./geturl.sh --profile <your-profile>

# Cleanup Lab 1
echo "yes" | ./cleanup.sh --profile <your-profile>
```

**Common flags:** `-s` (server/backend), `-c` (client/frontend), `--email <email>` (Labs 2–6), `--tenant-email <email>` (Labs 3–4).

## Project Structure

```
workshop/
├── Lab1/ – Lab7/        # Individual lab folders (server/, client/, scripts/, extra-info/)
├── Solution/            # Reference implementations (DO NOT MODIFY)
├── scripts/             # Orchestration support (main-template.yaml, create-workshop-users.sh)
├── extra-info/          # Shared reference docs (prerequisites, deployment manual, naming conventions)
├── deploy-all.sh        # Deploy all labs in parallel via nested CloudFormation stacks
├── cleanup-all.sh       # Clean up all labs with secure deletion order
├── LICENSE              # CC-BY-SA 4.0
├── LICENSE-SAMPLECODE   # MIT-0 (sample code)
├── CONTRIBUTING.md      # Contribution guidelines
└── README.md            # This file
```

## Additional Resources

- [Deployment & Cleanup Manual](extra-info/DEPLOYMENT_CLEANUP_MANUAL.md) — detailed deployment/cleanup procedures and troubleshooting
- [Prerequisites Guide](extra-info/PREREQUISITES.md) — installation instructions and verification
- [Resource Naming Convention](extra-info/RESOURCE_NAMING_CONVENTION.md) — how resources are named per lab
- [Node.js LTS Setup](extra-info/NODEJS_LTS_SETUP.md) — resolving Node.js version issues
- [AWS SaaS Architecture Lens](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)

## License

This workshop content is licensed under [CC-BY-SA 4.0](LICENSE). Sample code is licensed under [MIT-0](LICENSE-SAMPLECODE). See [THIRD-PARTY-LICENSES.txt](THIRD-PARTY-LICENSES.txt) for third-party attributions.
