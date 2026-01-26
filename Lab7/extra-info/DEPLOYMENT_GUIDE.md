# Lab7 - Multi-Tenant Cost Attribution Deployment Guide

## Overview

Lab7 demonstrates how to implement cost attribution in a multi-tenant SaaS application using AWS Cost and Usage Reports (CUR), AWS Glue, Amazon Athena, and CloudWatch Logs Insights. This lab shows how to track and allocate AWS service costs (DynamoDB and Lambda) to individual tenants based on their actual usage.

## Architecture

The cost attribution system consists of:

1. **AWS Cost and Usage Report (CUR)** - Sample cost data stored in S3
2. **AWS Glue Crawler** - Catalogs CUR data for querying
3. **Amazon Athena** - Queries total service costs from CUR data
4. **CloudWatch Logs** - Captures tenant usage metrics from Lambda functions with structured logging
5. **EventBridge Rules** - Triggers cost attribution calculations every 5 minutes
6. **Lambda Functions** - Calculates and stores cost attribution data
7. **DynamoDB Table** - Stores tenant cost attribution results
8. **AWS Lambda PowerTools** - Provides structured logging, tracing, and metrics

### Attribution Timing and Accuracy

**EventBridge Schedule**: Attribution Lambdas run every 5 minutes (not every minute) to ensure accurate data collection.

**Why 5 minutes?** CloudWatch Logs Insights has an indexing delay of 1-3 minutes. Running attribution too frequently (e.g., every minute) can result in incomplete data because logs aren't fully indexed yet. The 5-minute schedule ensures all logs are queryable before attribution runs.

**Deployment Wait Time**: The deployment script waits 4 minutes after generating test invocations to allow CloudWatch Logs Insights to fully index all logs before the first attribution run.

### PowerTools Structured Logging

Lambda functions use AWS Lambda PowerTools for structured JSON logging with:
- **Structured JSON format** - Consistent, parseable log format
- **Tenant context** - Automatic tenant_id injection
- **X-Ray tracing** - Distributed tracing with correlation IDs
- **Consumed capacity tracking** - Actual DynamoDB RCU/WCU from responses

## Prerequisites

- AWS CLI configured with appropriate credentials
- SAM CLI installed
- Python 3.9 or later
- Sufficient AWS permissions to create CloudFormation stacks, Lambda functions, DynamoDB tables, S3 buckets, Glue resources, and IAM roles

## Deployment Steps

### Step 1: Navigate to Lab7 Directory

```
cd aws-serverless-saas-workshop/Lab7
```

### Step 2: Run the Deployment Script

The deployment script handles everything needed for the workshop:

```
cd scripts
./deployment.sh
```

This script will:
1. Deploy the main Lab7 CloudFormation stack
2. Upload sample CUR data to S3
3. Initialize the Glue crawler to catalog CUR data
4. Deploy the tenant stack with Lambda functions (using PowerTools)
5. Generate 30 Lambda invocations (10 create + 10 update + 10 get) to simulate tenant activity
6. Wait 4 minutes for CloudWatch Logs Insights indexing

**Deployment takes approximately 5-6 minutes.**

### Step 3: Wait for Cost Attribution

After deployment completes, wait **5 minutes** for the EventBridge rules to trigger the cost attribution Lambda functions. These functions run every 5 minutes.

## Deployed Resources

### Main Stack: `serverless-saas-lab7`

- **S3 Bucket**: `serverless-saas-lab7-cur-{ShortId}` - Stores CUR data
- **Glue Database**: `costexplorerdb-lab7` - Catalogs CUR data
- **Glue Crawler**: `AWSCURCrawler-Multi-tenant-lab7` - Crawls CUR data
- **DynamoDB Table**: `TenantCostAndUsageAttribution-lab7` - Stores cost attribution results
- **Lambda Functions**:
  - `serverless-saas-lab7-aws-cur-initializer` - Initializes Glue crawler
  - `serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant` - Calculates DynamoDB costs
  - `serverless-saas-lab7-get-lambda-usage-and-cost-by-tenant` - Calculates Lambda costs
- **EventBridge Rules**:
  - `CalculateDynamoUsageAndCostByTenant-lab7` - Runs every 5 minutes
  - `CalculateLambdaUsageAndCostByTenant-lab7` - Runs every 5 minutes

### Tenant Stack: `stack-pooled-lab7`

- **Lambda Layer**: `lab7-powertools-layer` - AWS Lambda PowerTools with X-Ray SDK
- **Lambda Functions**:
  - `create-product-pooled-lab7` - Creates products in DynamoDB with PowerTools logging
  - `update-product-pooled-lab7` - Updates products in DynamoDB with PowerTools logging
  - `get-products-pooled-lab7` - Retrieves products from DynamoDB with PowerTools logging
- **DynamoDB Table**: `Product-pooled-lab7` - Stores product data (PROVISIONED billing mode)
- **IAM Role**: `tenant-lambda-execution-role-pooled-lab7` - Execution role for Lambda functions

## How Cost Attribution Works

### 1. Tenant Lambda Functions Log Usage Metrics

Each tenant Lambda function uses AWS Lambda PowerTools to log structured usage data in JSON format to CloudWatch Logs:

```json
{
  "level": "INFO",
  "location": "create_product:56",
  "message": "Request completed",
  "timestamp": "2026-01-16 21:44:18,299+0000",
  "service": "product-service",
  "tenant_id": "pooled",
  "consumed_rcu": 0,
  "consumed_wcu": 1.0,
  "operation": "create_product",
  "xray_trace_id": "1-696ab130-7b1ef6c66c6049bb342ac8ce"
}
```

**Key Fields:**
- `tenant_id` - Tenant identifier for cost attribution
- `consumed_rcu` - Actual read capacity units consumed from DynamoDB response
- `consumed_wcu` - Actual write capacity units consumed from DynamoDB response
- `operation` - Operation type (create_product, update_product, get_products)
- `xray_trace_id` - X-Ray trace ID for distributed tracing

### 2. EventBridge Triggers Cost Attribution (Every 5 Minutes)

Two EventBridge rules run every 5 minutes:
- One for DynamoDB cost attribution
- One for Lambda cost attribution

### 3. CloudWatch Logs Insights Queries Extract Usage Data

The cost attribution Lambda functions query CloudWatch Logs to:
- Extract RCU/WCU consumption per tenant
- Sum total RCU/WCU across all tenants
- Calculate each tenant's percentage of total usage

**Example Query for DynamoDB:**
```
filter ispresent(consumed_rcu) or ispresent(consumed_wcu)
| fields tenant_id as TenantId, consumed_rcu as RCapacityUnits, consumed_wcu as WCapacityUnits
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

```
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

```
# Create Product Function logs
aws logs tail /aws/lambda/create-product-pooled-lab7 --follow

# Update Product Function logs
aws logs tail /aws/lambda/update-product-pooled-lab7 --follow
```

You should see PowerTools structured JSON log entries with fields like:
- `tenant_id` - Tenant identifier
- `consumed_rcu` - Read capacity units consumed
- `consumed_wcu` - Write capacity units consumed
- `operation` - Operation type (create_product, update_product, get_products)
- `xray_trace_id` - X-Ray trace ID for distributed tracing

### 3. Check Cost Attribution Lambda Logs

View logs from cost attribution functions:

```
# DynamoDB cost attribution
aws logs tail /aws/lambda/serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant --follow

# Lambda cost attribution
aws logs tail /aws/lambda/serverless-saas-lab7-get-lambda-usage-and-cost-by-tenant --follow
```

### 4. Verify EventBridge Rules are Running

Check that EventBridge rules are enabled and triggering:

```
aws events list-rules --name-prefix "Calculate" --query "Rules[?contains(Name, 'lab7')]"
```

Both rules should show `State: "ENABLED"` and `ScheduleExpression: "rate(5 minute)"`.

### 5. Query Cost Attribution with AWS CLI

Get cost attribution for a specific tenant and service:

```
aws dynamodb query \
  --table-name TenantCostAndUsageAttribution-lab7 \
  --key-condition-expression "TenantId#ServiceName = :pk" \
  --expression-attribute-values '{":pk":{"S":"pooled#DynamoDB"}}'
```

## Testing the System

### Generate Additional Lambda Invocations

To generate more tenant activity and see cost attribution update:

```
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

### 1. Optimize EventBridge Schedule

Change from 5 minutes to daily for production:

```yaml
ScheduleExpression: rate(1 day)
```

### 2. Add More Services

Extend cost attribution to other AWS services:
- API Gateway
- S3
- CloudFront
- RDS

### 3. Implement Cost Alerts

Add CloudWatch Alarms to notify when tenant costs exceed thresholds.

### 4. Create Cost Dashboards

Use QuickSight or CloudWatch Dashboards to visualize tenant costs over time.

## Cleanup

To remove all Lab7 resources:

```
cd scripts
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
   ```
   aws events list-rules --query "Rules[?contains(Name, 'lab7')]"
   ```

2. **Check Lambda function logs for errors:**
   ```
   aws logs tail /aws/lambda/serverless-saas-lab7-get-dynamodb-usage-and-cost-by-tenant
   ```

3. **Verify CloudWatch Logs contain usage data:**
   ```
   aws logs tail /aws/lambda/create-product-pooled-lab7
   ```

### Athena Query Failures

1. **Check Glue Database exists:**
   ```
   aws glue get-database --name costexplorerdb-lab7
   ```

2. **Check Glue Crawler has run:**
   ```
   aws glue get-crawler --name AWSCURCrawler-Multi-tenant-lab7
   ```

3. **Manually trigger crawler if needed:**
   ```
   aws lambda invoke \
     --function-name serverless-saas-lab7-aws-cur-initializer \
     output.json
   ```

### No Lambda Invocations in Logs

Re-run the invocation generation:

```
for i in {1..10}; do
  aws lambda invoke \
    --function-name create-product-pooled-lab7 \
    --cli-binary-format raw-in-base64-out \
    --payload '{"productId":"prod-'$i'","productName":"Product '$i'","price":99.99}' \
    /dev/null
done
```

### Attribution Shows Fewer Invocations Than Expected

**Symptom**: DynamoDB table shows 26-28 invocations instead of 30.

**Cause**: CloudWatch Logs Insights indexing delay. Logs are written immediately but take 1-3 minutes to be indexed and queryable via Insights.

**Solutions**:

1. **Wait for next attribution run** (recommended):
   ```
   # Attribution runs every 5 minutes, wait and check again
   sleep 300
   aws dynamodb scan --table-name TenantCostAndUsageAttribution-lab7 --region us-east-1
   ```

2. **Verify all logs exist** (they should):
   ```
   # Check actual log count (should be 30)
   aws logs filter-log-events \
     --log-group-name /aws/lambda/create-product-pooled-lab7 \
     --filter-pattern "Request completed" \
     --start-time $(($(date +%s) - 3600))000 \
     --region us-east-1 \
     --output json | python3 -c "import sys, json; print(f'Count: {len(json.load(sys.stdin)[\"events\"])}')"
   ```

3. **Increase deployment wait time**:
   - Edit `scripts/deployment.sh` and increase `sleep 240` to `sleep 300` (5 minutes)
   - This gives more time for CloudWatch Logs Insights indexing

**Note**: In production, run attribution hourly or daily for complete accuracy. The 5-minute schedule is a balance between demo responsiveness and data accuracy.

## Additional Resources

- [AWS Cost and Usage Reports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)
- [AWS Glue Crawler](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html)
- [Multi-Tenant SaaS Cost Attribution Best Practices](https://aws.amazon.com/blogs/apn/a-reference-solution-for-saas-tenant-cost-attribution-and-tracking-on-aws/)

## Summary

Lab7 demonstrates a complete cost attribution system for multi-tenant SaaS applications. By combining AWS Cost and Usage Reports with CloudWatch Logs Insights, you can accurately track and allocate costs to individual tenants based on their actual resource consumption. This enables usage-based pricing models and helps identify cost optimization opportunities per tenant.
