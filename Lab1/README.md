# Lab 1: Basic Serverless Web Application

Build a product and order management app using API Gateway, Lambda, DynamoDB, and CloudFront — no servers to manage.

## Architecture

```
Browser → CloudFront → S3 (Angular UI)
                 ↓
           API Gateway (REST)
                 ↓
         Lambda Functions (Python 3.14)
                 ↓
            DynamoDB
```

**Resources deployed:**
- 10 Lambda functions — CRUD for products (5) and orders (5)
- 2 DynamoDB tables — `Product-lab1`, `Order-lab1` (on-demand billing)
- 1 REST API Gateway with CloudWatch logging
- 1 CloudFront distribution + S3 bucket for the Angular 14 UI
- 1 shared Lambda layer (logger, utils, JSON serialization)
- IAM roles with least-privilege DynamoDB access per service

## Directory Structure

```
Lab1/
├── server/              # SAM backend
│   ├── template.yaml    # CloudFormation/SAM template (all infra)
│   ├── samconfig.toml   # SAM deployment config
│   ├── ProductService/  # Product CRUD Lambda handlers
│   ├── OrderService/    # Order CRUD Lambda handlers
│   └── layers/          # Shared layer (logger.py, utils.py)
├── client/Application/  # Angular 14 frontend
├── scripts/             # Deploy, cleanup, and URL retrieval scripts
└── extra-info/          # Operational reference docs
```

## Prerequisites

- **AWS CLI** v2.x+ with a configured profile
- **SAM CLI** v1.x+
- **Python 3.14**
- **Docker** (required for `sam build`)
- **Node.js LTS** (v20.x or v22.x) — for client build only

## Deploy

```bash
cd workshop/Lab1/scripts

# Full deploy (server + client) — ~10-15 min
./deployment.sh -s -c --profile <your-profile>

# Server only
./deployment.sh -s --profile <your-profile>

# Client only (server must be deployed first)
./deployment.sh -c --profile <your-profile>
```

**Flags:** `-s` server, `-c` client, `--stack-name <name>` (default: `serverless-saas-lab1`), `--region <region>` (default: `us-east-1`).

The deployment script validates prerequisites, builds with SAM, deploys the CloudFormation stack, uploads the Angular app to S3, and outputs application URLs.

### Get URLs

```bash
./geturl.sh --profile <your-profile>
```

Returns the CloudFront URL, API Gateway URL, and S3 bucket name.

## Verify

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile <your-profile> \
  --query 'Stacks[0].StackStatus'
# Expected: "CREATE_COMPLETE"

# Test the API
API_URL=$(aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab1 \
  --profile <your-profile> \
  --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayURL`].OutputValue' \
  --output text)

# Create a product
curl -X POST ${API_URL}/product \
  -H "Content-Type: application/json" \
  -d '{"category":"Electronics","name":"Echo Dot","price":"49.99","sku":"ECHO-001"}'

# List products
curl -X GET ${API_URL}/products
```

## Cleanup

```bash
cd workshop/Lab1/scripts
echo "yes" | ./cleanup.sh --profile <your-profile>
```

**Time:** 15-20 minutes (CloudFront deletion is the bottleneck).

The script deletes in a secure order: CloudFormation stack first (removes CloudFront), waits for completion, then deletes S3 buckets. This prevents CloudFront Origin Hijacking. **Do not interrupt the process.**

## Key Concepts

- **Serverless CRUD** — Each API operation maps to a dedicated Lambda function
- **SAM (Serverless Application Model)** — Infrastructure-as-code for Lambda, API Gateway, and DynamoDB
- **Lambda Layers** — Shared code (logging via AWS Lambda Powertools, JSON serialization via jsonpickle)
- **CloudFront + S3** — Static site hosting with CDN and Origin Access Identity
- **Resource tagging** — All resources tagged with Application, Lab, Environment, Owner, CostCenter
- **Lab isolation** — All resource names include `lab1` so cleanup never affects other labs

## Troubleshooting

| Problem | Solution |
|---|---|
| `sam build` fails | Ensure Docker is running and Python 3.14 is installed |
| API returns 500 | Check Lambda logs: `aws logs tail /aws/lambda/serverless-saas-lab1-<fn> --profile <p> --follow` |
| CloudFront 403 | Wait 15-20 min for propagation; verify stack is `CREATE_COMPLETE` |
| Client deploy fails | Deploy server first (`-s` flag), then client (`-c`) |
| Angular build fails | Use Node.js LTS (v20.x or v22.x); odd-numbered versions may fail |
| Stack deletion stuck | CloudFront takes 15-30 min — do not interrupt |

## Additional Resources

- [Lab 1 Operational Reference](extra-info/LAB_REFERENCE.md) — commands, API endpoints, resource naming
- [Deployment & Cleanup Manual](../extra-info/DEPLOYMENT_CLEANUP_MANUAL.md)

## Next Lab

**Lab 2:** Introducing SaaS Shared Services — adds tenant management and user authentication.
