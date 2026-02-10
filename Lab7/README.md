# Lab 7: Cost Attribution in a Pooled Multi-Tenant Model

Implement per-tenant cost attribution for shared infrastructure by combining AWS Cost and Usage Reports (CUR) with CloudWatch Logs usage metrics.

## Architecture Overview

Lab 7 deploys **two CloudFormation stacks** that work together:

```
Tenant Stack (stack-pooled-lab7)          Main Stack (serverless-saas-lab7)
┌──────────────────────────────┐          ┌──────────────────────────────────┐
│ Product Lambdas (create,     │          │ Sample CUR Data (S3)             │
│   update, get) with          │──logs──▶ │   └─▶ Glue Crawler              │
│   PowerTools structured      │          │       └─▶ Athena (SQL queries)   │
│   logging (tenant_id,        │          │                                  │
│   consumed_rcu/wcu)          │          │ Attribution Lambdas (EventBridge │
│                              │          │   every 5 min):                  │
│ Product DynamoDB Table       │          │   • DynamoDB cost by tenant      │
│   (provisioned 5 RCU/5 WCU) │          │   • Lambda cost by tenant        │
└──────────────────────────────┘          │                                  │
                                          │ Results → DynamoDB table         │
                                          └──────────────────────────────────┘
```

**AWS services used:** Lambda, DynamoDB, S3, Glue, Athena, EventBridge, CloudWatch Logs, IAM

### Cost Attribution Flow

1. **Capture usage** — Product Lambdas log `tenant_id`, `consumed_rcu`, and `consumed_wcu` per request using PowerTools structured logging
2. **Get total costs** — Attribution Lambdas query Athena (backed by CUR data in S3) for total DynamoDB/Lambda costs
3. **Aggregate tenant usage** — `filter_log_events` API counts per-tenant RCU/WCU and invocations from CloudWatch Logs
4. **Calculate attribution** — Tenant cost = (tenant usage / total usage) × total service cost
5. **Store results** — Attribution records written to `TenantCostAndUsageAttribution-lab7` DynamoDB table

### Attribution Formulas

- **DynamoDB:** `tenant_cost = ((tenant_RCU × 5 + tenant_WCU) / (total_RCU × 5 + total_WCU)) × total_cost`
  *(RCU weighted 5× because reads are ~5× cheaper than writes)*
- **Lambda:** `tenant_cost = (tenant_invocations / total_invocations) × total_cost`

## Directory Structure

```
Lab7/
├── template.yaml              # Main stack — CUR infra, attribution Lambdas, EventBridge
├── tenant-template.yaml       # Tenant stack — product Lambdas, product DynamoDB table
├── samconfig.toml             # SAM config for main stack
├── tenant-samconfig.toml      # SAM config for tenant stack
├── TenantUsageAndCost/        # Attribution Lambda code (DynamoDB + Lambda cost calc)
├── ProductService/            # Product CRUD Lambdas with capacity tracking
├── layers/                    # PowerTools logger layer
├── SampleCUR/                 # Sample Cost and Usage Report parquet files
├── scripts/
│   ├── deployment.sh          # Full deployment (~10-15 min)
│   ├── cleanup.sh             # Full cleanup (~5-10 min)
│   └── geturl.sh              # Display deployed resource info
├── payload.json               # Sample Lambda test payload
└── extra-info/
    └── LAB_REFERENCE.md       # Operational quick-reference
```

## Prerequisites

- **AWS CLI** configured with a named profile
- **SAM CLI** ≥ 1.70.0
- **Python 3.14**
- **Docker** running (required for SAM build)

> **Lab Independence:** This lab is fully standalone — it does NOT require any other lab to be deployed. The deployment script generates its own sample CUR data and Lambda invocations.

## Key Concepts

1. **Pooled cost attribution** — In shared infrastructure, costs can't be read from AWS tags alone. You must instrument code to capture per-tenant usage metrics and apportion total costs proportionally.

2. **Structured logging for metering** — Product Lambdas use `aws-lambda-powertools` to emit JSON logs with `tenant_id`, `consumed_rcu`, and `consumed_wcu` fields. The `filter_log_events` API (not Logs Insights) is used for accurate counting that avoids cold-start indexing delays.

3. **CUR + Athena for total costs** — Sample CUR parquet files are loaded into S3, cataloged by a Glue Crawler, and queried via Athena SQL to get total service costs (DynamoDB, Lambda).

4. **Scheduled attribution** — EventBridge rules trigger attribution Lambdas every 5 minutes. Each run queries CloudWatch Logs for tenant usage, queries Athena for total costs, calculates proportional attribution, and writes results to DynamoDB.

5. **Provisioned vs. on-demand tracking** — The tenant product table uses provisioned capacity (5 RCU / 5 WCU) with `ReturnConsumedCapacity='TOTAL'` to capture actual capacity unit consumption per operation.

## Deployment

```bash
cd workshop/Lab7/scripts
./deployment.sh --profile <your-profile>
```

**~10-15 minutes.** The script: deploys both stacks, uploads CUR data, runs the Glue Crawler, generates 30 test Lambda invocations, and waits for log indexing.

After deployment, wait **5 minutes** for the first EventBridge-triggered attribution run.

### Verify

```bash
# Check attribution results (wait 5 min after deploy)
aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7 \
  --profile <your-profile> --region us-east-1

# Check EventBridge rules
aws events list-rules --name-prefix "Calculate" \
  --query "Rules[?contains(Name, 'lab7')]" \
  --profile <your-profile> --region us-east-1
```

## Cleanup

```bash
cd workshop/Lab7/scripts
echo "yes" | ./cleanup.sh --profile <your-profile>
```

**~5-10 minutes.** Wait 5-10 minutes before redeploying due to S3 eventual consistency.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Empty attribution table after 10 min | EventBridge not triggering or Lambda errors | Check logs: `aws logs tail /aws/lambda/serverless-saas-lab7-dynamodb-cost` |
| Athena query failures | Glue Crawler incomplete | Re-trigger: `aws lambda invoke --function-name serverless-saas-lab7-aws-cur-initializer out.json` |
| Stack deletion fails | CUR S3 bucket has `DeletionPolicy: Retain` | Empty and delete bucket manually, then retry |

## Operational Reference

See [extra-info/LAB_REFERENCE.md](extra-info/LAB_REFERENCE.md) for verification commands, attribution formulas, and detailed troubleshooting.
