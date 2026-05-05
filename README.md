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

### Required tools

| Tool | Version | Notes |
|------|---------|-------|
| AWS CLI | v2.x+ | With a configured named profile |
| SAM CLI | ≥ 1.70.0 | Earlier versions don't support Python 3.14 runtime |
| Python | 3.14 | Matches the Lambda runtime |
| Node.js | v20.x or v22.x (LTS) | For Angular client builds. Avoid odd-numbered versions |
| Docker | 20.x+ | Must be running for `sam build` |
| AWS CDK CLI | Latest | Required for Labs 5–6 only (`npm install -g aws-cdk`) |
| Git | Any | |

**AWS Account:** permissions to create Lambda, API Gateway, DynamoDB, Cognito, S3, CloudFormation, CodePipeline, CloudWatch, Athena, Glue, and IAM resources. For development `AdministratorAccess` is simplest.

**Region:** `us-east-1` (default) or `us-west-2`. Other regions may work but have not been tested.

### Install AWS CLI

macOS:

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
```

Linux:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

Configure a named profile:

```bash
aws configure --profile workshop-dev
# Enter AWS Access Key ID, Secret Access Key, default region (us-east-1), output (json)

aws sts get-caller-identity --profile workshop-dev
```

### Install SAM CLI

```bash
pip3 install --upgrade aws-sam-cli
sam --version
```

### Install Python 3.14

macOS (Homebrew):

```bash
brew install python@3.14
python3.14 --version
```

Linux (from source):

```bash
sudo dnf install openssl-devel libffi-devel bzip2-devel zlib-devel xz-devel sqlite-devel readline-devel
curl -fsSL -o Python-3.14.0.tgz https://www.python.org/ftp/python/3.14.0/Python-3.14.0.tgz
tar xzf Python-3.14.0.tgz
cd Python-3.14.0
./configure --enable-optimizations
make -j$(nproc)
sudo make altinstall
python3.14 --version
```

### Install Node.js LTS (v20 or v22)

Recommended — nvm:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# Restart terminal, then:
nvm install 22
nvm use 22
nvm alias default 22
node --version      # should print v22.x.x
```

See the [Node.js LTS Setup](#nodejs-lts-setup--troubleshooting) section below if you hit version errors.

### Install Docker (or Finch)

macOS/Windows: install Docker Desktop from [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop).

Linux:

```bash
sudo dnf install docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect
docker info
```

Alternative — Finch (AWS open-source):

```bash
brew install --cask finch
finch vm init
finch vm start
finch info
```

SAM CLI 1.133+ auto-detects Finch when Docker is absent.

### Install AWS CDK CLI (Labs 5–6 only)

```bash
npm install -g aws-cdk
cdk --version
```

### Verify everything

Run this one-liner to check every required tool:

```bash
for cmd in aws sam python3.14 node npm docker cdk git; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "✓ $cmd: $($cmd --version 2>&1 | head -1)"
    else
        echo "✗ $cmd: NOT INSTALLED"
    fi
done
```

All tools should print a version.

## Optional: Python Virtual Environment

The deployment scripts run `pylint` to validate Python code before deploying. If `pylint` is not installed, validation is skipped with a warning — but setting up a virtual environment ensures consistent, clean results.

```bash
cd workshop

# Create the virtual environment (Python 3.14 matches the Lambda runtime)
python3.14 -m venv .venv_py314

# Activate it
source .venv_py314/bin/activate

# Install pylint
pip install pylint

# Deactivate when done (or just close the terminal)
deactivate
```

The deployment scripts automatically detect `.venv_py314` and use it for code validation. You do not need to activate the venv before running scripts — they find it by path.

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

| Lab | Deploy | Cleanup |
|-----|--------|---------|
| 1 | `cd Lab1/scripts && ./deployment.sh -s -c --profile <p>` | `cd Lab1/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 2 | `cd Lab2/scripts && ./deployment.sh -s -c --email <e> --profile <p>` | `cd Lab2/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 3 | `cd Lab3/scripts && ./deployment.sh -s -c --email <e> --tenant-email <te> --profile <p>` | `cd Lab3/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 4 | `cd Lab4/scripts && ./deployment.sh -s -c --email <e> --tenant-email <te> --profile <p>` | `cd Lab4/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 5 | `cd Lab5/scripts && ./deployment.sh -s -c --profile <p>` | `cd Lab5/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 6 | `cd Lab6/scripts && ./deployment.sh -s -c --profile <p>` | `cd Lab6/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |
| 7 | `cd Lab7/scripts && ./deployment.sh --profile <p>` | `cd Lab7/scripts && echo "yes" \| ./cleanup.sh --profile <p>` |

**Common flags:** `-s` (server/backend), `-c` (client/frontend), `--email <email>` (Labs 2–6), `--tenant-email <email>` (Labs 3–4).

### What `deploy-all.sh` does

1. `sam build` + `sam package` in parallel for each lab (uses Docker/Finch for reproducible builds)
2. Creates the orchestration stack `serverless-saas-lab`, which creates 10 nested stacks in parallel
3. Angular clients are built with real API Gateway URLs and synced to S3
4. `set-log-retention.sh` applies 60-day retention on all Lambda log groups
5. If `--email` was provided, `create-workshop-users.sh` runs automatically and prints credentials

### What `cleanup-all.sh` does (deletion order matters)

1. CloudFront distributions deleted first (must be removed before their S3 origins)
2. S3 bucket contents emptied
3. Nested CloudFormation stacks deleted
4. Root stack deleted
5. Cognito User Pools auto-deleted when their owning stack is deleted
6. CloudWatch log groups left to expire via retention policy

Why the order matters: deleting an S3 bucket while CloudFront still references it leaves a window where a malicious actor can create a bucket with the same name and serve attacker-controlled content through your CloudFront distribution (**Origin Hijacking**). The script enforces the correct order — **do not interrupt it**.

### Cognito user creation

`scripts/create-workshop-users.sh` creates admin users in every OperationUsers pool (Labs 2–6) and tenant admin users in Labs 3–4.

```bash
./scripts/create-workshop-users.sh --email <your-email> --profile <your-profile>
```

Creates the following users with the default temporary password `SaaS#Workshop2026` (users must change on first login):

- `admin` in Lab2, Lab3, Lab4, Lab5, Lab6 OperationUsers pools
- `tenant1-admin` in Lab3, Lab4 TenantUsers pools
- `tenant2-admin` in Lab4 TenantUsers pool

Credentials are also written to `scripts/workshop-credentials.txt`. **Delete this file after noting the credentials** — it's gitignored so it won't be committed, but leaving it on disk is a security risk:

```bash
rm scripts/workshop-credentials.txt
```

## Post-deployment verification

```bash
# Every stack CREATE_COMPLETE?
aws cloudformation describe-stacks --profile <your-profile> --region us-east-1 \
    --query 'Stacks[?contains(StackName, `serverless-saas`)].[StackName,StackStatus]' \
    --output table

# Every workshop log group has 60-day retention?
aws logs describe-log-groups --profile <your-profile> \
    --query 'logGroups[?contains(logGroupName, `serverless-saas`)].{Name:logGroupName,Retention:retentionInDays}' \
    --output table

# API Gateway smoke test (Lab 1)
LAB1_URL=$(aws cloudformation describe-stacks --profile <your-profile> --region us-east-1 \
    --stack-name serverless-saas-lab \
    --query 'Stacks[0].Outputs[?OutputKey==`Lab1APIGatewayURL`].OutputValue' \
    --output text)
curl "$LAB1_URL/products"
```

## Post-cleanup verification

```bash
# Should return no stacks
aws cloudformation list-stacks --profile <your-profile> --region us-east-1 \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `serverless-saas`)].StackName' \
    --output text

# Should return no workshop S3 buckets
aws s3 ls --profile <your-profile> | grep serverless-saas
```

## Node.js LTS Setup & Troubleshooting

The Angular clients in Labs 1–6 are built with `ng build`, which requires a specific range of Node.js versions.

### Why LTS only

Node.js releases follow an even/odd pattern:

- **Even-numbered releases** (v20, v22, v24) are promoted to LTS (Long-Term Support) about six months after release
- **Odd-numbered releases** (v21, v23) are not LTS and have frequent breaking changes

This workshop's Angular build toolchain is tested on **v20.x** and **v22.x** LTS only. Other versions may fail with errors like:

- `Error: Cannot find module '@angular-devkit/...'`
- `OpenSSL error: ERR_OSSL_EVP_UNSUPPORTED`
- `digital envelope routines::unsupported`
- `npm ERR! peer dep missing:`

If you see any of these, check your Node.js version first:

```bash
node --version
```

Accepted output: `v20.x.x` or `v22.x.x`. Anything else → upgrade or downgrade.

### Switch Node version with nvm

```bash
# Install v22 LTS
nvm install 22
nvm use 22
nvm alias default 22

# Or switch to v20 LTS
nvm install 20
nvm use 20
```

### Common Node issues

**npm install fails with "peer dep missing":** the labs use `npm install --legacy-peer-deps`. If you run `npm install` by hand:

```bash
rm -rf node_modules package-lock.json
npm install --legacy-peer-deps
```

**OpenSSL / digital envelope errors:** reset your environment:

```bash
unset NODE_OPTIONS
node --version     # confirm v20 or v22
rm -rf node_modules package-lock.json
npm install --legacy-peer-deps
npm run build
```

**Global Angular CLI conflicts:** an old `@angular/cli` globally installed can shadow the project-local one:

```bash
npm uninstall -g @angular/cli
# The labs use node_modules/.bin/ng (project-local) — no global install needed
```

## Common Failure Modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `deploy-all.sh` fails on a single nested stack | Transient CloudWatch log group race or IAM propagation | Re-run the same command. `deploy-all.sh` retries in place. |
| CloudFront 403 after deploy | Distribution still propagating | Wait 15–20 minutes, then retry. |
| CloudFront 403 persists after 30 minutes | Origin Access Control not correctly wired | Check `DefaultCacheBehavior` and `TargetOriginId` in stack outputs. |
| Cognito domain conflict during `sam deploy` | Previous deploy left the domain reserved | Use `--stack-name <unique-name>`; Cognito hosted-UI domains are globally unique. |
| `cleanup-all.sh` hangs on S3 delete | CloudFront not fully deleted yet | Wait; never kill the script. Origin Hijacking risk if you force delete buckets now. |
| `sam build` fails with Docker error | Docker daemon not running | Start Docker Desktop or Finch: `finch vm start`. |
| Node.js / Angular build failures | Non-LTS Node version | See [Node.js LTS Setup](#nodejs-lts-setup--troubleshooting) above. |
| Python 3.14 not found | Wrong Python version in path | Install Python 3.14 and verify `python3.14 --version`. |

## Hard Rules

1. **Never run scripts with `bash`.** Always `./script.sh`. Running with `bash` bypasses the shebang and breaks `set -euo pipefail`.
2. **`--profile <name>` is required** on every script invocation. No fallback to default credentials.
3. **Don't interrupt `cleanup-all.sh`** — CloudFront must delete before S3 to prevent Origin Hijacking.
4. **Delete `workshop-credentials.txt`** after noting your admin password.
5. **Do not delete the SAM managed bucket** (`aws-sam-cli-managed-default-samclisourcebucket-*`) as part of workshop cleanup. It's shared across SAM projects.

## Resource Naming Convention

Every workshop resource follows a predictable naming pattern so that `cleanup-all.sh` can delete by pattern, Lab 7 cost attribution can filter by `Service: lab<N>` tag, and `create-workshop-users.sh` can find Cognito pools per lab.

### Lab identifiers

Each lab is identified by its lowercase name: `lab1`, `lab2`, `lab3`, `lab4`, `lab5`, `lab6`, `lab7`. Use this value as the `Service` tag (**not** `Lab` — that tag key is not in the Workshop Studio allowed Cost Allocation set).

### Stack names

| Pattern | Example | Purpose |
|---|---|---|
| `serverless-saas-lab` | `serverless-saas-lab` | Root orchestration stack (from `deploy-all.sh`) |
| `serverless-saas-workshop-<lab>` | `serverless-saas-workshop-lab1` | Per-lab nested stack (or standalone) |
| `stack-<tier>-lab5` | `stack-platinum-lab5` | Dynamic tenant stack from Lab 5 pipeline |

### DynamoDB tables

| Pattern | Example |
|---|---|
| `ServerlessSaaS-<Entity>-lab<N>` | `ServerlessSaaS-TenantDetails-lab2` |
| `ServerlessSaaS-<Entity>-lab<N>-<tenant-id>` | `ServerlessSaaS-Products-lab4-tenant1` |

### Cognito User Pools

| Pattern | Example |
|---|---|
| `OperationUsers-lab<N>` | `OperationUsers-lab2` |
| `TenantUsers-lab<N>` | `TenantUsers-lab3` |
| `TenantUsers-lab<N>-<tenant-id>` | `TenantUsers-lab4-tenant1` (silo model) |

### S3 buckets

S3 bucket names must be globally unique, so they include the account ID and region:

| Pattern | Example |
|---|---|
| `serverless-saas-admin-<account>-<region>` | `serverless-saas-admin-111122223333-us-east-1` |
| `serverless-saas-landing-<account>-<region>` | `serverless-saas-landing-111122223333-us-east-1` |
| `serverless-saas-app-<account>-<region>` | `serverless-saas-app-111122223333-us-east-1` |

### Required resource tags

Every CloudFormation-managed resource must carry at minimum:

```yaml
Tags:
  - Key: Workshop
    Value: serverless-saas
  - Key: Service
    Value: lab1            # or lab2, lab3, etc. — NEVER use `Lab` as a tag key
  - Key: Environment
    Value: prod            # or dev, staging
  - Key: Project
    Value: aws-serverless-saas-workshop
  - Key: CreatedBy
    Value: CloudFormation
```

For Lab 7 tenant resources, add `TenantId`:

```yaml
  - Key: TenantId
    Value: !Ref TenantIdParameter
```

### Custom Cognito user attributes

- `custom:tenantId` — tenant UUID
- `custom:userRole` — `SystemAdmin` or `TenantAdmin`

Set at user-creation time by `create-workshop-users.sh`.

## Project Structure

```text
workshop/
├── Lab1/ – Lab7/        # Individual lab folders (server/, client/, scripts/)
├── Solution/            # Reference implementations (DO NOT MODIFY)
├── scripts/             # Orchestration support (main-template.yaml, create-workshop-users.sh)
├── deploy-all.sh        # Deploy all labs in parallel via nested CloudFormation stacks
├── cleanup-all.sh       # Clean up all labs with secure deletion order
├── LICENSE              # CC-BY-SA 4.0
├── LICENSE-SAMPLECODE   # MIT-0 (sample code)
├── CONTRIBUTING.md      # Contribution guidelines
└── README.md            # This file
```

## Additional Resources

- [AWS SaaS Architecture Lens](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)

## License

This workshop content is licensed under [CC-BY-SA 4.0](LICENSE). Sample code is licensed under [MIT-0](LICENSE-SAMPLECODE). See [THIRD-PARTY-LICENSES.txt](THIRD-PARTY-LICENSES.txt) for third-party attributions.
