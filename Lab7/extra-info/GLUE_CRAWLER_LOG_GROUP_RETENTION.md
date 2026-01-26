# AWS Glue Crawler CloudWatch Log Group Retention Configuration

## Overview

This document describes the addition of a CloudWatch log group resource for the AWS Glue Crawler in Lab7 with a 60-day retention period.

## Problem Statement

The AWS Glue Crawler (`AWSCURCrawler-Multi-tenant-lab7`) automatically creates a CloudWatch log group when it runs, but without explicit configuration, the log group has no retention policy (logs are kept indefinitely). This can lead to unnecessary storage costs and doesn't align with the workshop's 60-day retention standard.

## Solution

Added an explicit `AWS::Logs::LogGroup` resource in the CloudFormation template to pre-create the log group with a 60-day retention period before the Glue Crawler runs.

## Changes Made

### 1. Template Changes (`workshop/Lab7/template.yaml`)

**Added new CloudWatch log group resource** (after line 63):

```yaml
AWSCURCrawlerLogGroup:
  Type: AWS::Logs::LogGroup
  Properties:
    LogGroupName: /aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7
    RetentionInDays: 60
    Tags:
      - Key: Application
        Value: serverless-saas-workshop
      - Key: Lab
        Value: lab7
```

**Updated AWSCURCrawler resource** to depend on the log group (line 219):

```yaml
AWSCURCrawler:
  Type: 'AWS::Glue::Crawler'
  DependsOn:
    - AWSCURDatabase
    - AWSCURCrawlerComponentFunction
    - AWSCURCrawlerLogGroup  # Added this dependency
  Properties:
    Name: AWSCURCrawler-Multi-tenant-lab7
    # ... rest of properties
```

### 2. Cleanup Script Verification

The existing cleanup script (`workshop/Lab7/scripts/cleanup.sh`) already handles the Glue Crawler log group deletion correctly:

- **Step 2** deletes all CloudWatch log groups containing 'lab7' in their name
- The query `logGroups[?contains(logGroupName, 'lab7')]` matches `/aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7`
- No changes needed to the cleanup script

## Benefits

1. **Cost Control**: Logs are automatically deleted after 60 days, preventing indefinite storage costs
2. **Consistency**: Aligns with the 60-day retention policy used for all other Lab7 log groups
3. **Predictability**: Log group is created with correct settings before the crawler runs
4. **Automatic Cleanup**: Existing cleanup script handles deletion without modification

## Log Group Details

- **Log Group Name**: `/aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7`
- **Retention Period**: 60 days (2 months)
- **Tags**:
  - Application: serverless-saas-workshop
  - Lab: lab7

## AWS Glue Crawler Log Group Naming Convention

AWS Glue Crawlers automatically create CloudWatch log groups with the pattern:
```
/aws-glue/crawlers/<crawler-name>
```

For our crawler named `AWSCURCrawler-Multi-tenant-lab7`, the log group is:
```
/aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7
```

## Testing

To verify the changes work correctly:

1. Deploy Lab7:
   ```
   cd workshop/Lab7/scripts
   ./deployment.sh --profile serverless-saas-demo
   ```

2. Verify the log group was created with correct retention:
   ```
   aws logs describe-log-groups \
     --log-group-name-prefix /aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7 \
     --region us-east-1 \
     --profile serverless-saas-demo \
     --query 'logGroups[0].[logGroupName,retentionInDays]' \
     --output table
   ```

   Expected output:
   ```
   -----------------------------------------------------------------------
   |                         DescribeLogGroups                          |
   +--------------------------------------------------------------------+
   |  /aws-glue/crawlers/AWSCURCrawler-Multi-tenant-lab7               |
   |  60                                                                |
   +--------------------------------------------------------------------+
   ```

3. Run cleanup and verify log group is deleted:
   ```
   cd workshop/Lab7/scripts
   echo "yes" | ./cleanup.sh --profile serverless-saas-demo
   ```

## References

- AWS CloudFormation `AWS::Logs::LogGroup` documentation
- AWS Glue Crawler CloudWatch logging
- Lab7 deployment and cleanup scripts
- Workshop retention policy standard (60 days)

## Related Files

- `workshop/Lab7/template.yaml` - CloudFormation template with log group resource
- `workshop/Lab7/scripts/cleanup.sh` - Cleanup script that handles log group deletion
- `workshop/Lab7/scripts/deployment.sh` - Deployment script

## Date

January 25, 2026
