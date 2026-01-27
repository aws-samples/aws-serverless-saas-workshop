# Lab 7: Cost Attribution in a Pooled Model

## Quick Reference

**Deployment Time:** ~10-15 minutes | **Cleanup Time:** ~10-15 minutes

### Quick Start
```
# Deploy
cd workshop/Lab7/scripts
./deployment.sh --profile serverless-saas-demo

# Cleanup
echo "yes" | ./cleanup.sh --profile serverless-saas-demo
```

**Important:** Wait 5-10 minutes after cleanup before redeploying due to S3 eventual consistency.

### What You'll Deploy

**Main Stack (serverless-saas-lab7):**
- **Lambda Functions** - Product service functions (Python 3.14)
- **1 DynamoDB Table** - Product table for sample data
- **1 Lambda Layer** - Metrics publishing layer for cost tracking
- **CloudWatch Metrics** - Custom metrics for tenant usage tracking
- **1 S3 Bucket** - Sample CUR data storage

**Tenant Stack (serverless-saas-tenant-lab7):**
- **Lambda Functions** - Tenant-specific product operations
- **CloudWatch Metrics** - Tenant-level usage metrics
- **Cost Attribution** - Tracks Lambda invocations, duration, and DynamoDB operations per tenant

### Key Features
- **Cost Attribution** - Track costs per tenant in pooled architecture
- **Custom Metrics** - CloudWatch metrics for tenant usage patterns
- **Lambda Layers** - Reusable metrics publishing layer
- **Sample CUR Data** - Pre-populated Cost and Usage Report data
- **Tenant Usage Analysis** - Analyze tenant-level resource consumption
- CloudWatch log groups with 60-day retention
- Resource tagging for cost tracking

---

## Overview

Lab 7 demonstrates how to implement cost attribution in a pooled multi-tenant SaaS architecture. In a pooled model, multiple tenants share the same infrastructure resources (Lambda functions, DynamoDB tables, etc.), making it challenging to determine the cost per tenant. This lab shows you how to:

- Capture tenant-level consumption metrics using CloudWatch
- Aggregate daily usage data per tenant
- Leverage AWS Cost and Usage Reports (CUR) to get service costs
- Calculate and attribute costs to individual tenants based on their usage

By the end of this lab, you'll understand how to track and attribute costs to tenants in a shared infrastructure environment, which is essential for pricing strategies, profitability analysis, and business decision-making.

## Learning Objectives

- Understand the challenges of cost attribution in pooled multi-tenant architectures
- Learn how to capture and aggregate tenant-level metrics
- Use CloudWatch Logs Insights to query tenant consumption data
- Leverage AWS Cost and Usage Reports for service cost data
- Implement a cost attribution algorithm to apportion costs among tenants
- Schedule automated cost attribution calculations using EventBridge

## Prerequisites

Before starting this lab, ensure you have:

- **AWS Account**: With appropriate permissions to create Lambda, DynamoDB, S3, Athena, Glue, and EventBridge resources
- **AWS CLI**: Configured with profile `serverless-saas-demo`
- **SAM CLI**: Version 1.70.0 or later
- **Python 3.14**: Installed on your local machine
- **Docker**: Running (required for SAM local testing)

**Lab Independence**: This lab is completely independent and does NOT require Lab 3 or any other lab to be deployed first. The deployment script automatically generates sample data in two ways:

1. **Sample CUR Data**: The AWSCURInitializer Lambda function creates sample Cost and Usage Report (CUR) data in S3
2. **Sample Lambda Invocations**: The deployment script runs 30 Lambda invocations (10 create + 10 update + 10 get) to generate CloudWatch Logs for cost attribution analysis

While Lab 7's cost attribution analysis is more meaningful with real tenant activity from Lab 3, it works independently with its own generated sample data.

## Architecture

Lab 7 deploys a cost attribution system that consists of:

### Resource Naming

Lab 7 follows a consistent naming convention to ensure resource isolation and easy identification:

**CloudFormation Stacks:**
- Main Stack: `serverless-saas-lab7` (cost attribution infrastructure)
- Tenant Stack: `serverless-saas-tenant-lab7` (tenant-specific product operations)

**Naming Pattern:**
All resources created by Lab 7 include `lab7` in their names to ensure isolation from other labs. This prevents accidental deletion of resources from other labs during cleanup.

**Key Resources:**

**Main Stack Resources:**
- Lambda Functions: `serverless-saas-lab7-<FunctionName>-<UniqueId>`
  - `AWSCURInitializer-<UniqueId>`
  - `GetDynamoDBUsageAndCostByTenant-<UniqueId>`
  - `GetLambdaUsageAndCostByTenant-<UniqueId>`
- DynamoDB Table: `TenantCostAndUsageAttributionTable-lab7`
- S3 Bucket: `serverless-saas-lab7-cur-<UniqueId>` (Cost and Usage Report data)
- Lambda Layer: `serverless-saas-lab7-MetricsLayer-<UniqueId>`
- CloudWatch Log Groups: `/aws/lambda/serverless-saas-lab7-<FunctionName>-<UniqueId>`
- Glue Crawler: `serverless-saas-lab7-cur-crawler`
- Glue Database: `serverless-saas-lab7-cur-database`
- EventBridge Rules: `serverless-saas-lab7-<RuleName>`

**Tenant Stack Resources:**
- Lambda Functions: `serverless-saas-tenant-lab7-<FunctionName>-<UniqueId>`
- DynamoDB Table: `Product-lab7`
- CloudWatch Log Groups: `/aws/lambda/serverless-saas-tenant-lab7-<FunctionName>-<UniqueId>`

**Lab Isolation:**
The cleanup script (`scripts/cleanup.sh`) uses lab-specific filtering to ensure it only deletes resources belonging to Lab 7. It will NOT delete resources from other labs (Lab1-Lab6), even if they are deployed in the same AWS account.

The cleanup script specifically queries for stacks containing `lab7` in their names:
```bash
aws cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, 'lab7')].StackName"
```

For more details on resource naming and lab isolation, see:
- [Cleanup Isolation Documentation](../extra-info/CLEANUP_ISOLATION.md)
- [Deployment Manual](../extra-info/DEPLOYMENT_CLEANUP_MANUAL.md)

### Main Stack (serverless-saas-lab7)

**Lambda Functions**:
- `AWSCURInitializer`: Initializes sample Cost and Usage Report data
- `GetDynamoDBUsageAndCostByTenant`: Calculates DynamoDB cost per tenant
- `GetLambdaUsageAndCostByTenant`: Calculates Lambda cost per tenant

**Data Storage**:
- `CURBucket`: S3 bucket containing sample Cost and Usage Report files
- `TenantCostAndUsageAttributionTable`: DynamoDB table storing daily cost attribution results

**Analytics**:
- AWS Glue Crawler: Catalogs CUR data for Athena queries
- Amazon Athena: Queries CUR data using SQL

**Automation**:
- EventBridge Rules: Schedule Lambda functions to run every 5 minutes

### Cost Attribution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Cost Attribution Process                     │
└─────────────────────────────────────────────────────────────────┘

Step 1: Generate Sample Data (Automatic)
┌──────────────────────────────────────┐
│  Deployment Script                   │
│  ├─ AWSCURInitializer Lambda         │
│  │  └─ Creates sample CUR data       │
│  └─ 30 Lambda Invocations            │
│     ├─ 10 create-product calls       │
│     ├─ 10 update-product calls       │
│     └─ 10 get-products calls         │
│                                      │
│  Generates:                          │
│  • Sample Cost and Usage Reports     │
│  • CloudWatch Logs with tenant data  │
│  • DynamoDB capacity unit metrics    │
└──────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  CloudWatch Logs                     │
│  • Tenant-level metrics              │
│  • Request completion logs           │
│  • Capacity unit consumption         │
└──────────────────────────────────────┘

Step 2: Aggregate Usage
┌──────────────────────────────────────┐
│  Lambda Functions (Scheduled)        │
│  ├─ GetDynamoDBUsageAndCostByTenant  │
│  └─ GetLambdaUsageAndCostByTenant    │
│                                      │
│  Uses CloudWatch Logs Insights to:   │
│  • Query tenant consumption          │
│  • Aggregate by day                  │
│  • Calculate usage percentages       │
└──────────────────────────────────────┘
           │
           ▼
Step 3: Get Service Costs
┌──────────────────────────────────────┐
│  Cost and Usage Reports              │
│  ├─ Sample CUR files in S3           │
│  ├─ Glue Crawler (catalog)           │
│  └─ Athena (SQL queries)             │
│                                      │
│  Provides:                           │
│  • Daily DynamoDB cost               │
│  • Daily Lambda cost                 │
└──────────────────────────────────────┘
           │
           ▼
Step 4: Calculate Attribution
┌──────────────────────────────────────┐
│  Cost Attribution Algorithm          │
│                                      │
│  Formula:                            │
│  Tenant Cost = Total Service Cost ×  │
│                (Tenant Usage /       │
│                 Total Usage)         │
└──────────────────────────────────────┘
           │
           ▼
Step 5: Store Results
┌──────────────────────────────────────┐
│  DynamoDB Table                      │
│  TenantCostAndUsageAttributionTable  │
│                                      │
│  Stores:                             │
│  • Date                              │
│  • TenantId                          │
│  • Service Name                      │
│  • Usage Metrics                     │
│  • Cost Attribution                  │
└──────────────────────────────────────┘
```

### Key Components

**CloudWatch Logs Insights Queries**:
- Aggregate DynamoDB Read/Write Capacity Units by tenant
- Count Lambda invocations per tenant
- Group metrics by day for daily attribution

**Cost and Usage Reports**:
- Sample CUR files in Parquet format
- Queried via Athena to get daily service costs
- Real-world scenario: Enable CUR in your AWS account for actual cost data

**Attribution Algorithm**:
```
Tenant Usage Percentage = (Tenant Usage / Total Usage) × 100
Tenant Cost = Total Service Cost × (Tenant Usage Percentage / 100)
```

## Deployment Steps

### Step 1: Review the Code Structure

1. Navigate to the Lab7 directory:
```
cd workshop/Lab7
```

2. Review the directory structure:
```
Lab7/
├── SampleCUR/              # Sample Cost and Usage Report files
├── TenantUsageAndCost/     # Lambda function for cost attribution
│   └── tenant_usage_and_cost.py
├── ProductService/         # Sample product service (for testing)
├── layers/                 # Lambda layers
├── template.yaml           # Main CloudFormation template
└── scripts/
    └── deployment.sh       # Deployment script
```

3. Open `TenantUsageAndCost/tenant_usage_and_cost.py` in your IDE to understand the cost attribution logic.

### Step 2: Review and Add Missing Code

The cost attribution Lambda function has several TODO comments where you need to add code. Let's complete them:

#### Calculating DynamoDB Cost Attribution

1. Open `TenantUsageAndCost/tenant_usage_and_cost.py`

2. Locate the `calculate_daily_dynamodb_attribution_by_tenant` method

3. Find the comment `# TODO: Get total cost of DynamoDB for the current date` and replace it with:
```python
total_dynamodb_cost = __get_total_service_cost('AmazonDynamoDB', start_date_time, end_date_time)
```

4. Find the `usage_by_tenant_by_day_query` variable and replace it with:
```python
usage_by_tenant_by_day_query = 'filter @message like /ReadCapacityUnits|WriteCapacityUnits/ \
    | fields tenant_id as TenantId, ReadCapacityUnits.0 as RCapacityUnits, WriteCapacityUnits.0 as WCapacityUnits \
    | stats sum(RCapacityUnits) as ReadCapacityUnits, sum(WCapacityUnits) as WriteCapacityUnits by TenantId, dateceil(@timestamp, 1d) as timestamp'
```

5. Find the `total_usage_by_day_query` variable and replace it with:
```python
total_usage_by_day_query = 'filter @message like /ReadCapacityUnits|WriteCapacityUnits/ \
    | fields ReadCapacityUnits.0 as RCapacityUnits, WriteCapacityUnits.0 as WCapacityUnits \
    | stats sum(RCapacityUnits) as ReadCapacityUnits, sum(WCapacityUnits) as WriteCapacityUnits by dateceil(@timestamp, 1d) as timestamp'
```

6. Find the code block with `# TODO: Save the tenant attribution data inside a dynamodb table` and replace it with:
```python
response = attribution_table.put_item(
Item=
   {
      "Date": start_date_time,
      "TenantId#ServiceName": tenant_id+"#"+"DynamoDB",
      "TenantId": tenant_id,
      "TotalRCU": Decimal(str(total_RCU)),
      "TenantTotalRCU": Decimal(str(total_RCU_By_Tenant)),
      "TotalWCU": Decimal(str(total_WCU)),
      "TenantTotalWCU": Decimal(str(total_WCU_By_Tenant)),
      "TenantAttributionPercentage": Decimal(str(tenant_attribution_percentage)),
      "TenantServiceCost": Decimal(str(tenant_dynamodb_cost)),
      "TotalServiceCost": Decimal(str(total_dynamodb_cost))
   }
)
```

#### Calculating Lambda Cost Attribution

1. Locate the `calculate_daily_lambda_attribution_by_tenant` method

2. Find the `usage_by_tenant_by_day_query` variable and replace it with:
```python
usage_by_tenant_by_day_query='filter @message like /Request completed/ \
      | fields tenant_id as TenantId , CountLambdaInvocations.0 As LambdaInvocations\
      | stats count (tenant_id) as CountLambdaInvocations by TenantId, dateceil(@timestamp, 1d) as timestamp'
```

3. Find the `total_usage_by_day_query` variable and replace it with:
```python
total_usage_by_day_query = 'filter @message like /Request completed/ \
      | fields CountLambdaInvocations.0 As LambdaInvocations, timestamp\
      | stats count (tenant_id) as CountLambdaInvocations by dateceil(@timestamp, 1d) as timestamp'
```

4. **Save all files** before proceeding to deployment.

### Step 3: Deploy Lab 7

**IMPORTANT**: Ensure you saved ALL files from the previous step.

Deploy the lab using the deployment script:

```
cd workshop/Lab7/scripts
./deployment.sh --profile serverless-saas-demo
```

**Deployment Time**: Approximately 10-15 minutes

The deployment script will:
1. Create an S3 bucket for sample CUR files
2. Copy sample CUR data to the bucket
3. Set up AWS Glue Crawler and Athena for CUR queries
4. Deploy Lambda functions for cost attribution
5. Create DynamoDB table for storing attribution results
6. Set up EventBridge rules to run Lambda functions every 5 minutes
7. **Generate sample data automatically**:
   - Upload sample CUR data via AWSCURInitializer Lambda
   - Run 30 Lambda invocations (10 create + 10 update + 10 get) to generate CloudWatch Logs
   - Wait 4 minutes for CloudWatch Logs ingestion and indexing

Wait for the deployment to complete successfully before proceeding.

### Step 4: Verify the Deployment

Check the CloudFormation stack status:

```
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab7 \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' \
  --profile serverless-saas-demo
```

Expected output:
- **Status**: `CREATE_COMPLETE`
- **Outputs**: Contains resource ARNs and names

## Verification

### Verify EventBridge Rules

1. Navigate to the **Amazon EventBridge** console
2. Click **Rules** in the left navigation menu
3. Verify the following rules exist:
   - `CalculateDynamoUsageAndCostByTenant`
   - `CalculateLambdaUsageAndCostByTenant`
4. Select one rule and verify:
   - **Event schedule**: Fixed rate of 5 minutes
   - **Target**: Lambda function for cost attribution
   - **Status**: Enabled

### Verify Cost Attribution Results

**Note**: Wait 5-10 minutes after deployment for the scheduled Lambda functions to run and populate the DynamoDB table.

1. Navigate to the **Amazon DynamoDB** console
2. Click **Explore items** under **Tables** in the left navigation menu
3. Select the `TenantCostAndUsageAttributionTable` table
4. Click **Scan** to view all items

You should see items with the following structure:

**DynamoDB Attribution Record**:
```json
{
  "Date": "2026-01-25",
  "TenantId#ServiceName": "tenant-123#DynamoDB",
  "TenantId": "tenant-123",
  "TotalRCU": 1000,
  "TenantTotalRCU": 250,
  "TotalWCU": 500,
  "TenantTotalWCU": 125,
  "TenantAttributionPercentage": 25.0,
  "TenantServiceCost": 0.50,
  "TotalServiceCost": 2.00
}
```

**Lambda Attribution Record**:
```json
{
  "Date": "2026-01-25",
  "TenantId#ServiceName": "tenant-123#Lambda",
  "TenantId": "tenant-123",
  "CountLambdaInvocations": 150,
  "TotalLambdaInvocations": 600,
  "TenantAttributionPercentage": 25.0,
  "TenantServiceCost": 0.30,
  "TotalServiceCost": 1.20
}
```

### Understanding the Attribution Data

Each record contains:

- **Date**: The date for which costs are attributed (YYYY-MM-DD)
- **TenantId#ServiceName**: Composite key (TenantId + Service)
- **TenantId**: Unique identifier for the tenant
- **Usage Metrics**:
  - DynamoDB: Read/Write Capacity Units (RCU/WCU)
  - Lambda: Invocation count
- **TenantAttributionPercentage**: Tenant's share of total usage (%)
- **TenantServiceCost**: Cost attributed to this tenant ($)
- **TotalServiceCost**: Total cost for the service across all tenants ($)

### Verify CloudWatch Logs

Check the Lambda function logs to ensure cost attribution is running successfully:

```
# Get DynamoDB attribution logs
aws logs tail /aws/lambda/GetDynamoDBUsageAndCostByTenant \
  --follow \
  --profile serverless-saas-demo

# Get Lambda attribution logs
aws logs tail /aws/lambda/GetLambdaUsageAndCostByTenant \
  --follow \
  --profile serverless-saas-demo
```

Look for log entries indicating successful attribution calculations.

### Query Attribution Data

You can query the attribution table to analyze cost trends:

```
# Get all attribution records for a specific tenant
aws dynamodb query \
  --table-name TenantCostAndUsageAttributionTable \
  --key-condition-expression "TenantId = :tenantId" \
  --expression-attribute-values '{":tenantId":{"S":"tenant-123"}}' \
  --profile serverless-saas-demo

# Get attribution for a specific date
aws dynamodb query \
  --table-name TenantCostAndUsageAttributionTable \
  --key-condition-expression "#date = :date" \
  --expression-attribute-names '{"#date":"Date"}' \
  --expression-attribute-values '{":date":{"S":"2026-01-25"}}' \
  --profile serverless-saas-demo
```

## Understanding Cost Attribution

### How DynamoDB Cost Attribution Works

1. **Generate Sample Data**: The deployment script automatically generates sample tenant usage data through Lambda invocations
2. **Aggregate Usage**: CloudWatch Logs Insights queries aggregate Read/Write Capacity Units by tenant per day
3. **Get Service Cost**: Athena queries the CUR to get total DynamoDB cost for the day
4. **Calculate Attribution**:
   ```
   Tenant RCU Percentage = (Tenant RCU / Total RCU) × 100
   Tenant WCU Percentage = (Tenant WCU / Total WCU) × 100
   Tenant Attribution % = (Tenant RCU % + Tenant WCU %) / 2
   Tenant Cost = Total DynamoDB Cost × (Tenant Attribution % / 100)
   ```

### How Lambda Cost Attribution Works

1. **Generate Sample Data**: The deployment script automatically runs Lambda invocations with tenant context
2. **Aggregate Usage**: CloudWatch Logs Insights counts Lambda invocations per tenant per day
3. **Get Service Cost**: Athena queries the CUR to get total Lambda cost for the day
4. **Calculate Attribution**:
   ```
   Tenant Invocation % = (Tenant Invocations / Total Invocations) × 100
   Tenant Cost = Total Lambda Cost × (Tenant Invocation % / 100)
   ```

**Note**: This lab uses invocation count as a proxy for Lambda cost. For more accurate attribution, you could also factor in execution duration and memory usage.

### Real-World Considerations

**Cost and Usage Reports**:
- This lab uses sample CUR files for demonstration
- In production, enable CUR in your AWS account (Billing Console → Cost & Usage Reports)
- AWS delivers CUR files to S3 daily (can take up to 24 hours to start)
- CUR queries may vary based on your discount plans and service usage

**Metrics Selection**:
- Choose metrics that represent the most significant cost drivers in your architecture
- For this workshop: DynamoDB capacity units and Lambda invocations
- Other services may require different metrics (e.g., S3 storage, API Gateway requests)

**Aggregation Frequency**:
- This lab runs every 5 minutes for quick demonstration
- Production systems typically run once or twice daily
- Consider your business needs for cost reporting frequency

**Data Retention**:
- The attribution table stores historical cost data
- Implement data lifecycle policies based on your retention requirements
- Consider archiving old data to S3 for long-term analysis

## Troubleshooting

### No Attribution Data in DynamoDB Table

**Symptom**: The `TenantCostAndUsageAttributionTable` is empty after 10+ minutes.

**Possible Causes**:
1. Lambda functions failing to execute
2. CloudWatch Logs Insights queries returning no results
3. EventBridge rules not triggering

**Solutions**:

1. **Wait for Scheduled Execution**:
   - The deployment script generates sample data automatically
   - EventBridge rules run every 5 minutes
   - Wait at least 10 minutes after deployment for initial results

2. **Check Lambda Function Logs**:
   ```
   aws logs tail /aws/lambda/GetDynamoDBUsageAndCostByTenant \
     --since 10m \
     --profile serverless-saas-demo
   ```
   Look for errors or exceptions

3. **Verify EventBridge Rules**:
   - Ensure rules are enabled
   - Check rule targets point to correct Lambda functions
   - Verify IAM permissions for EventBridge to invoke Lambda

4. **Test Lambda Functions Manually**:
   ```
   aws lambda invoke \
     --function-name GetDynamoDBUsageAndCostByTenant \
     --payload '{}' \
     response.json \
     --profile serverless-saas-demo
   
   cat response.json
   ```

### CloudWatch Logs Insights Query Errors

**Symptom**: Lambda logs show errors querying CloudWatch Logs Insights.

**Solutions**:

1. **Verify Log Groups Exist**:
   ```
   aws logs describe-log-groups \
     --log-group-name-prefix "/aws/lambda/serverless-saas-lab7" \
     --profile serverless-saas-demo
   ```

2. **Check IAM Permissions**:
   - Lambda execution role needs `logs:StartQuery` and `logs:GetQueryResults` permissions
   - Verify the role has access to Lab 7 log groups

3. **Adjust Date Range**:
   - If running Lab 7 days after initial deployment, modify the date range in the Lambda function
   - Update `start_date_time` and `end_date_time` variables

### Athena Query Failures

**Symptom**: Lambda logs show errors querying Athena for CUR data.

**Solutions**:

1. **Verify Glue Crawler Ran Successfully**:
   ```
   aws glue get-crawler \
     --name AWSCURCrawler-serverless-saas-lab7 \
     --profile serverless-saas-demo
   ```

2. **Check Athena Query Results Location**:
   - Ensure S3 bucket for Athena results exists
   - Verify Lambda has permissions to write to the bucket

3. **Test Athena Query Manually**:
   - Open Athena console
   - Run a sample query against the CUR database
   - Verify data is accessible

### Deployment Failures

**Symptom**: CloudFormation stack creation fails.

**Common Issues**:

1. **S3 Bucket Already Exists**:
   - S3 bucket names must be globally unique
   - The deployment script generates a unique bucket name
   - If deployment fails, clean up and retry

2. **IAM Permissions**:
   - Ensure your AWS profile has permissions to create all required resources
   - Required services: Lambda, DynamoDB, S3, Glue, Athena, EventBridge, IAM

3. **Resource Limits**:
   - Check AWS service quotas for your account
   - Particularly Lambda concurrent executions and DynamoDB tables

## Cleanup

**Important**: Only perform cleanup if you're running this workshop in your own AWS account.

### Automated Cleanup

Run the cleanup script to remove all Lab 7 resources:

```
cd workshop/Lab7/scripts
echo "yes" | ./cleanup.sh --profile serverless-saas-demo
```

The cleanup script will:
1. Delete the CloudFormation stack `serverless-saas-lab7`
2. Wait for stack deletion to complete (includes CloudFront propagation)
3. Empty and delete the CUR S3 bucket
4. Delete CloudWatch log groups
5. Remove Glue Crawler and database

**Cleanup Time**: Approximately 5-10 minutes

**Note**: Wait 5-10 minutes before redeploying Lab 7 to allow S3 bucket deletion to propagate globally.

### Manual Cleanup (if automated cleanup fails)

If the cleanup script fails, manually delete resources in this order:

1. **Delete CloudFormation Stack**:
   ```
   aws cloudformation delete-stack \
     --stack-name serverless-saas-lab7 \
     --profile serverless-saas-demo
   ```

2. **Wait for Stack Deletion**:
   ```
   aws cloudformation wait stack-delete-complete \
     --stack-name serverless-saas-lab7 \
     --profile serverless-saas-demo
   ```

3. **Delete S3 Bucket**:
   ```
   # Get bucket name
   BUCKET_NAME=$(aws s3 ls --profile serverless-saas-demo | grep serverless-saas-lab7-cur | awk '{print $3}')
   
   # Empty and delete bucket
   aws s3 rm s3://$BUCKET_NAME --recursive --profile serverless-saas-demo
   aws s3 rb s3://$BUCKET_NAME --profile serverless-saas-demo
   ```

4. **Delete CloudWatch Log Groups**:
   ```
   aws logs delete-log-group \
     --log-group-name /aws/lambda/GetDynamoDBUsageAndCostByTenant \
     --profile serverless-saas-demo
   
   aws logs delete-log-group \
     --log-group-name /aws/lambda/GetLambdaUsageAndCostByTenant \
     --profile serverless-saas-demo
   ```

5. **Delete Glue Resources**:
   ```
   aws glue delete-crawler \
     --name AWSCURCrawler-serverless-saas-lab7 \
     --profile serverless-saas-demo
   
   aws glue delete-database \
     --name athenacurcfn_serverless_saas_lab7 \
     --profile serverless-saas-demo
   ```

### Verify Cleanup

Confirm all resources are deleted:

```
# Check CloudFormation stack
aws cloudformation describe-stacks \
  --stack-name serverless-saas-lab7 \
  --profile serverless-saas-demo
# Should return: Stack with id serverless-saas-lab7 does not exist

# Check S3 buckets
aws s3 ls --profile serverless-saas-demo | grep serverless-saas-lab7
# Should return: (empty)

# Check DynamoDB tables
aws dynamodb list-tables \
  --profile serverless-saas-demo \
  --query 'TableNames[?contains(@, `TenantCostAndUsageAttribution`)]'
# Should return: []
```

## Key Takeaways

1. **Cost Attribution is Essential**: Understanding cost per tenant is critical for SaaS pricing, profitability analysis, and business decisions

2. **Metrics Drive Attribution**: Capturing detailed tenant-level metrics is the foundation of accurate cost attribution in pooled architectures

3. **Service-Specific Strategies**: Different AWS services require different attribution approaches:
   - DynamoDB: Capacity units consumed
   - Lambda: Invocations and duration
   - S3: Storage and requests
   - API Gateway: Request count

4. **Automation is Key**: Scheduled attribution calculations ensure up-to-date cost data without manual intervention

5. **CUR Provides Cost Data**: AWS Cost and Usage Reports are the authoritative source for actual AWS costs

6. **Pooled vs. Siloed**: 
   - Pooled tenants: Require consumption-based attribution (this lab)
   - Siloed tenants: Use AWS cost allocation tags (Lab 5)

7. **Business Value**: Cost attribution data enables:
   - Accurate pricing models
   - Profitability analysis per tenant
   - Identification of high-cost tenants
   - Optimization opportunities
   - Informed business decisions

## Next Steps

Congratulations! You've completed Lab 7 and learned how to implement cost attribution in a pooled multi-tenant SaaS architecture.

### What You've Accomplished

- ✅ Captured tenant-level consumption metrics
- ✅ Aggregated usage data using CloudWatch Logs Insights
- ✅ Queried AWS Cost and Usage Reports with Athena
- ✅ Calculated and attributed costs to individual tenants
- ✅ Automated cost attribution with EventBridge schedules
- ✅ Stored attribution results for analysis and reporting

### Workshop Completion

You have now completed all 7 labs of the AWS Serverless SaaS Workshop! You've built a comprehensive multi-tenant SaaS solution that includes:

- **Lab 1**: Basic serverless web application
- **Lab 2**: Tenant onboarding and user management
- **Lab 3**: Multi-tenancy with data partitioning and isolation
- **Lab 4**: Advanced tenant isolation with IAM policies
- **Lab 5**: Tier-based deployment strategies (pooled vs. siloed)
- **Lab 6**: Tenant throttling and quotas
- **Lab 7**: Cost attribution in pooled architectures

### Further Learning

To deepen your understanding of SaaS on AWS:

1. **AWS SaaS Factory**: Explore additional resources and reference architectures at [AWS SaaS Factory](https://aws.amazon.com/partners/programs/saas-factory/)

2. **Serverless SaaS Reference Solution**: Review the complete reference solution this workshop is based on

3. **AWS Well-Architected SaaS Lens**: Learn best practices for building SaaS solutions on AWS

4. **Cost Optimization**: Explore AWS Cost Explorer and Cost Anomaly Detection for deeper cost insights

5. **Advanced Metrics**: Implement additional metrics for other AWS services (S3, API Gateway, etc.)

6. **Real-World CUR**: Enable Cost and Usage Reports in your AWS account for production cost attribution

### Clean Up Workshop Resources

If you're done with the entire workshop, run the global cleanup script to remove all resources:

```
cd workshop/scripts
echo "yes" | ./cleanup.sh --profile serverless-saas-demo
```

This will clean up all labs (Lab 1-7) and shared infrastructure.

## Additional Resources

- [AWS Serverless SaaS Workshop](https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US)
- [AWS Cost and Usage Reports Documentation](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Amazon Athena Documentation](https://docs.aws.amazon.com/athena/)
- [AWS Glue Crawler Documentation](https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html)
- [SaaS Tenant Cost Attribution Strategies](https://aws.amazon.com/blogs/apn/calculating-tenant-costs-in-saas-environments/)

---

**Workshop Repository**: [AWS Serverless SaaS Workshop](https://github.com/aws-samples/aws-serverless-saas-workshop)

**Questions or Feedback**: Please open an issue in the GitHub repository.
