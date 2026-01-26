# Lab6 Deployment Guide

## Overview

Lab6 implements **tier-based throttling** using AWS API Gateway Usage Plans. This lab demonstrates how to apply different rate limits and quotas based on tenant subscription tiers (Basic, Standard, Premium, Platinum).

## What's New in Lab6

### Tier-Based Throttling
- **Basic Tier**: 50 requests/day, 10 req/sec rate limit, 20 burst
- **Standard Tier**: 1000 requests/day, 50 req/sec rate limit, 100 burst  
- **Premium Tier**: 5000 requests/day, 100 req/sec rate limit, 200 burst
- **Platinum Tier**: 10000 requests/day, 300 req/sec rate limit, 300 burst

### Architecture Changes
- API Gateway Usage Plans for each tier
- API Keys associated with each tier
- Custom resource to associate usage plans with tenant APIs
- Throttling enforcement at the API Gateway level

## Prerequisites

- AWS CLI configured with appropriate credentials
- Python 3.9+ with pylint installed
- SAM CLI installed
- Docker installed (for SAM build with containers)
- Sufficient AWS permissions to create CloudFormation stacks, Lambda functions, API Gateway, DynamoDB tables, and Cognito User Pools

## Quick Start

### Option 1: Standard Deployment (15-25 minutes)

```
cd aws-serverless-saas-workshop/Lab6/scripts
./deployment.sh
```

### Option 2: Screen Session Deployment (Recommended for Remote Connections)

```
cd aws-serverless-saas-workshop/Lab6/scripts
./deploy-with-screen.sh

# To reconnect and monitor:
screen -r lab6-deployment

# To detach (keep running): Ctrl+A, then D
```

## Deployment Steps

The deployment script performs the following steps:

1. **Code Validation**: Runs pylint on all Python files
2. **Shared Infrastructure Deployment**:
   - DynamoDB tables (TenantDetails, Settings, TenantUserMapping, TenantStackMapping)
   - Cognito User Pools (Operation Users and Pooled Tenant)
   - S3 buckets and CloudFront distributions for UI
   - API Gateway with Usage Plans for each tier
   - Lambda functions for tenant management
3. **Pooled Tenant Deployment**:
   - Product and Order service Lambda functions
   - Tenant-specific API Gateway
   - Custom resource to associate usage plans
   - DynamoDB tables for products and orders

## Post-Deployment

After successful deployment, you'll see:

```
Admin site URL: https://d2rl4gm5chfj3q.cloudfront.net
Landing site URL: https://d3pokxjgt2ftr.cloudfront.net
App site URL: https://d2sip2r3llji1l.cloudfront.net
```

## Testing Throttling

Use the provided test script to verify tier-based throttling:

```
cd aws-serverless-saas-workshop/Lab6/scripts

# Get a JWT token for a basic tier tenant
# (You'll need to create a tenant and login first)
TOKEN="your-jwt-token-here"

# Run throttling test (sends 1000 concurrent requests)
./test-basic-tier-throttling.sh $TOKEN
```

Expected behavior:
- Basic tier tenants will see 429 (Too Many Requests) errors after exceeding limits
- Higher tier tenants can make more requests before hitting limits

## Cleanup

To remove all Lab6 resources:

```
cd aws-serverless-saas-workshop/Lab6/scripts
./cleanup.sh
```

This will delete:
- All tenant stacks
- Pooled tenant stack
- Shared infrastructure stack
- S3 buckets (including versioned objects)
- Cognito User Pools
- CDKToolkit stack (if present)

## Troubleshooting

### Build Failures

If SAM build fails:
```
# Check Docker is running
docker ps

# Try building without container
cd ../server
sam build -t shared-template.yaml
```

### Deployment Failures

Check CloudFormation console for detailed error messages:
```
aws cloudformation describe-stack-events \
  --stack-name serverless-saas-workshop-shared-lab6 \
  --max-items 20
```

### Usage Plan Not Applied

If throttling isn't working:
1. Check that the custom resource executed successfully
2. Verify API key is associated with the correct usage plan
3. Check API Gateway stage has usage plan attached

```
# List usage plans
aws apigateway get-usage-plans

# Get usage plan details
aws apigateway get-usage-plan --usage-plan-id <plan-id>
```

## Resource Naming Convention

All Lab6 resources use the `-lab6` suffix for isolation:
- DynamoDB Tables: `ServerlessSaaS-TenantDetails-lab6`, `ServerlessSaaS-Settings-lab6`
- Cognito Pools: `PooledTenant-ServerlessSaaS-lab6-UserPool`
- Lambda Functions: `serverless-saas-lab6-*`
- S3 Buckets: `*-lab6`

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     API Gateway                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Basic Tier   │  │ Standard     │  │ Premium/     │     │
│  │ Usage Plan   │  │ Usage Plan   │  │ Platinum     │     │
│  │ 50 req/day   │  │ 1K req/day   │  │ 5K-10K/day   │     │
│  │ 10 req/sec   │  │ 50 req/sec   │  │ 100-300/sec  │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                            │                                 │
└────────────────────────────┼─────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   Authorizer    │
                    │   (validates    │
                    │   JWT + tier)   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Lambda         │
                    │  Functions      │
                    │  (Product/      │
                    │   Order)        │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  DynamoDB       │
                    │  (per-tenant    │
                    │   tables)       │
                    └─────────────────┘
```

## Key Differences from Lab5

| Feature | Lab5 | Lab6 |
|---------|------|------|
| Focus | CI/CD Pipeline | Tier-based Throttling |
| Deployment | Pipeline-based | Direct SAM deploy |
| API Gateway | Basic setup | Usage Plans + API Keys |
| Tenant Isolation | Stack-based | Stack + Rate limiting |
| Complexity | High (pipeline) | Medium (usage plans) |

## Next Steps

After completing Lab6:
1. Create tenants with different tiers
2. Test throttling behavior for each tier
3. Monitor API Gateway metrics in CloudWatch
4. Experiment with custom usage plan configurations
5. Proceed to Lab7 for advanced features
