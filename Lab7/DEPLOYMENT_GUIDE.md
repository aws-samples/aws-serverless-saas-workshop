# Lab7 - Multi-Tenant Cost Attribution Deployment Guide

## Overview

Lab7 demonstrates how to implement cost attribution in a multi-tenant SaaS application using AWS Cost and Usage Reports (CUR), AWS Glue, Amazon Athena, and CloudWatch Logs Insights. This lab shows how to track and allocate AWS service costs (DynamoDB and Lambda) to individual tenants based on their actual usage.

## Architecture

The cost attribution system consists of:

1. **AWS Cost and Usage Report (CUR)** - Sample cost data stored in S3
2. **AWS Glue Crawler** - Catalogs CUR data for querying
3. **Amazon Athena** - Queries total service costs from CUR data
4. **CloudWatch Logs** - Captures tenant usage metrics from Lambda functions
5. **EventBridge Rules** - Triggers cost attribution calculations every 1 minute
6. **Lambda Functions** - Calculates and stores cost attribution data
7. **DynamoDB Table** - Stores tenant cost attribution results

## Prerequisites

- AWS CLI configured with appropriate credentials
- SAM CLI installed
- Python 3.9 or later
- Sufficient AWS permissions to create CloudFormation stacks, Lambda functions, DynamoDB tables, S3 buckets, Glue resources, and IAM roles

## Deployment Steps

### Step 1: Navigate to Lab7 Directory

```bash
cd aws-serverless-saas-workshop/Lab7
```

### Step 2: Run the Deployment Script

The deployment script handles everything needed for the workshop:

```bash
./deployment.sh
```

This script will:
1. Deploy the main Lab7 CloudFormation stack
2. Upload sample CUR data to S3
3. Initialize the Glue crawler to catalog CUR data
4. Deploy the tenant stack with Lambda functions
5. Generate 60 Lambda invocations (30 create + 30 update) to simulate tenant activity

**Deployment takes approximately 3-4 minutes.**

### Step 3: Wait for Cost Attribution

After deployment completes, wait **90 seconds** for the EventBridge rules to trigger the cost attribution Lambda functions. These functions run every 1 minute.

## Deployed Resources

### Main Stack: `serverless-saas-workshop-lab7`

- **S3 Bucket**: `serverless-saas-lab7-cur-{ShortId}` - Stores CUR data
- **Glue Database**: `costexplorerdb-lab7` - Catalogs CUR data
- **Glue Crawler**: `AWSCURCrawler-Multi-tenant-lab7` - Crawls CUR data
- **DynamoDB Table**: `TenantCostAndUsageAttribution-lab7` - Stores cost attribution results
- **Lambda Functions**:
  - `serverless-saas-lab7-aws-cur-initializer` - Initializes Glue crawler
  - `serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant` - Calculates DynamoDB costs
  - `serverless-saas-lab7-get-lambda-usage-and-cost-by-tenant` - Calculates Lambda costs
- **EventBridge Rules**:
  - `CalculateDynamoUsageAndCostByTenant-lab7` - Runs every 1 minute
  - `CalculateLambdaUsageAndCostByTenant-lab7` - Runs every 1 minute

### Tenant Stack: `stack-pooled-lab7`

- **Lambda Functions**:
  - `create-product-pooled-lab7` - Creates products in DynamoDB
  - `update-product-pooled-lab7` - Updates products in DynamoDB
- **DynamoDB Table**: `Product-pooled-lab7` - Stores product data
- **IAM Role**: `tenant-lambda-execution-role-pooled-lab7` - Execution role for Lambda functions

## How Cost Attribution Works

### 1. Tenant Lambda Functions Log Usage Metrics

Each tenant Lambda function logs usage data in JSON format to CloudWatch Logs:

```json
{
  "message": "Request completed",
  "tenant_id": "pooled",
  "ReadCapacityUnits": [1],
  "WriteCapacityUnits": [1]
}
```

**Note**: In this demo, RCU/WCU values are hardcoded to `[1]` for simplicity. In production, you would capture actual consumed capacity from DynamoDB responses.

### 2. EventBridge Triggers Cost Attribution (Every 1 Minute)

Two EventBridge rules run every 1 minute:
- One for DynamoDB cost attribution
- One for Lambda cost attribution

### 3. CloudWatch Logs Insights Queries Extract Usage Data

The cost attribution Lambda functions query CloudWatch Logs to:
- Extract RCU/WCU consumption per tenant
- Sum total RCU/WCU across all tenants
- Calculate each tenant's percentage of total usage

**Example Query for DynamoDB:**
```
filter @message like /ReadCapacityUnits|WriteCapacityUnits/
| fields tenant_id as TenantId, ReadCapacityUnits.0 as RCapacityUnits, WriteCapacityUnits.0 as WCapacityUnits
| stats sum(RCapacityUnits) as ReadCapacityUnits, sum(WCapacityUnits) as WriteCapacityUnits by TenantId
```

### 4. Athena Queries Total Service Costs

The system queries AWS Cost and Usage Report data via Athena to get total service costs:

```sql
SELECT sum(line_item_blended_cost) AS cost 
FROM curoutput 
WHERE line_item_product_code='AmazonDynamoDB'
```

### 5. Cost Allocation Calculation

For each tenant:
1. Calculate tenant's percentage of total usage
2. Multiply by total service cost
3. Store result in `TenantCostAndUsageAttribution-lab7` table

**Formula for DynamoDB:**
```
tenant_percentage = (tenant_RCU * 5 + tenant_WCU) / (total_RCU * 5 + total_WCU)
tenant_cost = tenant_percentage * total_service_cost
```

*Note: RCU is weighted 5x because it's approximately 5 times cheaper than WCU*

## Verification Steps

### 1. Check DynamoDB Table for Cost Attribution Data

Wait 90 seconds after deployment, then run:

```bash
aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7
```

**Expected Output:**

You should see items with:
- `Date` - Timestamp of the attribution calculation
- `TenantId#ServiceName` - Composite key (e.g., "pooled#DynamoDB", "pooled#AWSLambda")
- `TenantId` - Tenant identifier ("pooled")
- `TotalRCU` / `TotalWCU` - Total capacity units across all tenants
- `TenantTotalRCU` / `TenantTotalWCU` - Tenant's capacity units
- `TenantAttributionPercentage` - Tenant's percentage of total usage
- `TenantServiceCost` - Allocated cost for this tenant
- `TotalServiceCost` - Total service cost from CUR

### 2. Check CloudWatch Logs for Lambda Invocations

View logs from tenant Lambda functions:

```bash
# Create Product Function logs
aws logs tail /aws/lambda/create-product-pooled-lab7 --follow

# Update Product Function logs
aws logs tail /aws/lambda/update-product-pooled-lab7 --follow
```

You should see JSON log entries with `tenant_id`, `ReadCapacityUnits`, and `WriteCapacityUnits`.

### 3. Check Cost Attribution Lambda Logs

View logs from cost attribution functions:

```bash
# DynamoDB cost attribution
aws logs tail /aws/lambda/serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant --follow

# Lambda cost attribution
aws logs tail /aws/lambda/serverless-saas-lab7-get-lambda-usage-and-cost-by-tenant --follow
```

### 4. Verify EventBridge Rules are Running

Check that EventBridge rules are enabled and triggering:

```bash
aws events list-rules --name-prefix "Calculate" --query "Rules[?contains(Name, 'lab7')]"
```

Both rules should show `State: "ENABLED"` and `ScheduleExpression: "rate(1 minute)"`.

### 5. Query Cost Attribution with AWS CLI

Get cost attribution for a specific tenant and service:

```bash
aws dynamodb query \
  --table-name TenantCostAndUsageAttribution-lab7 \
  --key-condition-expression "TenantId#ServiceName = :pk" \
  --expression-attribute-values '{":pk":{"S":"pooled#DynamoDB"}}'
```

## Testing the System

### Generate Additional Lambda Invocations

To generate more tenant activity and see cost attribution update:

```bash
# Generate 10 more product creations
for i in {100..110}; do
  aws lambda invoke \
    --function-name create-product-pooled-lab7 \
    --cli-binary-format raw-in-base64-out \
    --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' \
    /dev/null
done

# Wait 90 seconds for cost attribution to run
sleep 90

# Check updated cost attribution
aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7
```

## Understanding the Results

### DynamoDB Cost Attribution

The system tracks:
- **Total RCU/WCU** - Sum of all read/write capacity units across all tenants
- **Tenant RCU/WCU** - Capacity units consumed by specific tenant
- **Attribution Percentage** - Tenant's share of total usage
- **Tenant Cost** - Allocated cost based on usage percentage

### Lambda Cost Attribution

The system tracks:
- **Total Invocations** - Total Lambda invocations across all tenants
- **Tenant Invocations** - Invocations for specific tenant
- **Attribution Percentage** - Tenant's share of total invocations
- **Tenant Cost** - Allocated cost based on invocation percentage

## Key Concepts Demonstrated

1. **Usage-Based Cost Attribution** - Costs are allocated based on actual resource consumption
2. **CloudWatch Logs as Metrics Source** - Application logs provide tenant usage data
3. **Automated Cost Calculation** - EventBridge triggers regular cost attribution updates
4. **Multi-Service Attribution** - Separate attribution for DynamoDB and Lambda
5. **Proportional Cost Allocation** - Each tenant pays for their share of total usage

## Production Considerations

### 1. Capture Actual DynamoDB Capacity

Replace hardcoded values with actual consumed capacity:

```python
response = table.put_item(
    Item={...},
    ReturnConsumedCapacity='TOTAL'
)

consumed = response.get('ConsumedCapacity', {})
rcu = consumed.get('ReadCapacityUnits', 0)
wcu = consumed.get('WriteCapacityUnits', 0)

print(json.dumps({
    'message': 'Request completed',
    'tenant_id': tenant_id,
    'ReadCapacityUnits': [rcu],
    'WriteCapacityUnits': [wcu]
}))
```

### 2. Optimize EventBridge Schedule

Change from 1 minute to daily for production:

```yaml
ScheduleExpression: rate(1 day)
```

### 3. Add More Services

Extend cost attribution to other AWS services:
- API Gateway
- S3
- CloudFront
- RDS

### 4. Implement Cost Alerts

Add CloudWatch Alarms to notify when tenant costs exceed thresholds.

### 5. Create Cost Dashboards

Use QuickSight or CloudWatch Dashboards to visualize tenant costs over time.

## Cleanup

To remove all Lab7 resources:

```bash
./cleanup.sh
```

This will delete:
- Both CloudFormation stacks (main and tenant)
- S3 buckets
- DynamoDB tables
- Lambda functions
- CloudWatch Log Groups
- EventBridge Rules
- IAM Roles

**Cleanup takes approximately 2 minutes.**

## Troubleshooting

### Cost Attribution Data Not Appearing

1. **Check EventBridge Rules are enabled:**
   ```bash
   aws events list-rules --query "Rules[?contains(Name, 'lab7')]"
   ```

2. **Check Lambda function logs for errors:**
   ```bash
   aws logs tail /aws/lambda/serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant
   ```

3. **Verify CloudWatch Logs contain usage data:**
   ```bash
   aws logs tail /aws/lambda/create-product-pooled-lab7
   ```

### Athena Query Failures

1. **Check Glue Database exists:**
   ```bash
   aws glue get-database --name costexplorerdb-lab7
   ```

2. **Check Glue Crawler has run:**
   ```bash
   aws glue get-crawler --name AWSCURCrawler-Multi-tenant-lab7
   ```

3. **Manually trigger crawler if needed:**
   ```bash
   aws lambda invoke \
     --function-name serverless-saas-lab7-aws-cur-initializer \
     output.json
   ```

### No Lambda Invocations in Logs

Re-run the invocation generation:

```bash
for i in {1..10}; do
  aws lambda invoke \
    --function-name create-product-pooled-lab7 \
    --cli-binary-format raw-in-base64-out \
    --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' \
    /dev/null
done
```

## Additional Resources

- [AWS Cost and Usage Reports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)
- [AWS Glue Crawler](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html)
- [Multi-Tenant SaaS Cost Attribution Best Practices](https://aws.amazon.com/blogs/apn/a-reference-solution-for-saas-tenant-cost-attribution-and-tracking-on-aws/)

## Summary

Lab7 demonstrates a complete cost attribution system for multi-tenant SaaS applications. By combining AWS Cost and Usage Reports with CloudWatch Logs Insights, you can accurately track and allocate costs to individual tenants based on their actual resource consumption. This enables usage-based pricing models and helps identify cost optimization opportunities per tenant.
