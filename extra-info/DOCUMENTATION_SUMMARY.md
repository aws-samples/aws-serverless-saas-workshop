# Workshop Documentation Summary

This document provides a consolidated overview of all labs in the Serverless SaaS Workshop, including key changes, bug fixes, deployment notes, and architecture updates.

## Quick Reference

| Lab | Focus | Deployment Time | Key Features |
|-----|-------|----------------|--------------|
| Lab 1 | Basic Serverless App | ~10-15 min | Lambda, API Gateway, DynamoDB, CloudFront |
| Lab 2 | SaaS Shared Services | ~10-15 min | Tenant management, Cognito, Admin UI |
| Lab 3 | Multi-Tenant Microservices | ~13-15 min | Pooled architecture, tenant isolation |
| Lab 4 | Tenant Data Isolation | ~18-20 min | IAM policies, STS credentials, row-level security |
| Lab 5 | Tier-Based Deployment | ~20-25 min | CodePipeline, CDK, automated deployments |
| Lab 6 | Tenant Throttling | ~20-25 min | API Gateway usage plans, rate limiting |
| Lab 7 | Cost Attribution | ~10-15 min | CloudWatch metrics, CUR analysis |

## Lab 1: Basic Serverless Web Application

**Purpose**: Introduce fundamental serverless architecture patterns

**Architecture**:
- Lambda functions for product/order management
- API Gateway REST API
- DynamoDB single table
- CloudFront distribution
- S3 static website hosting

**Key Features**:
- Basic CRUD operations
- Python 3.14 runtime
- CloudWatch logs with 60-day retention

**Deployment**:
```
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**See**: `workshop/Lab1/LAB1_SUMMARY.md` for detailed information

---

## Lab 2: SaaS Shared Services

**Purpose**: Add multi-tenancy infrastructure with tenant and user management

**Architecture**:
- 16 Lambda functions for tenant/user management
- 2 DynamoDB tables (TenantDetails, TenantUserMapping)
- 2 Cognito User Pools (PooledTenant, OperationUsers)
- Admin API Gateway
- 2 CloudFront distributions (Admin UI, Landing UI)

**Critical Bugs Fixed**:
1. **Duplicate CloudWatch Log Groups**: Removed 176 lines of duplicate definitions
2. **DynamoDB Table Name Mismatch**: Added environment variable for table name
3. **API Gateway Execution Logs Cleanup**: Added AdminApiGatewayId output
4. **Duplicate Admin User Creation**: Fixed CloudFormation to create only one admin user
5. **API Gateway Execution Logs Retention**: Documented technical limitation (circular dependency)

**Deployment**:
```
cd workshop/Lab2/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --profile serverless-saas-demo
```

**See**: `workshop/Lab2/LAB2_SUMMARY.md` for detailed information

---

## Lab 3: Multi-Tenant Microservices

**Purpose**: Demonstrate pooled multi-tenant architecture with business logic separation

**Architecture**:
- **Shared Stack**: 16 Lambda functions, tenant/user management, Admin API Gateway
- **Tenant Stack**: 10 Lambda functions, product/order operations, Tenant API Gateway
- Pooled DynamoDB tables (Product-lab3, Order-lab3)
- 3 CloudFront distributions (Admin, Landing, Application)

**Key Features**:
- Two API Gateways (Admin and Tenant)
- Pooled architecture with tenant ID partitioning
- Automatic creation of 3 sample tenants
- Business Services Authorizer

**Critical Fixes Applied**:
1. **YAML Syntax Error**: Fixed unquoted colon in Description field
2. **Duplicate CloudWatch Log Groups**: Removed duplicate definitions
3. **Tenant Creation Logic**: Modified to create tenants only when both stacks deployed
4. **Automatic Tenant Creation**: Updated condition to prevent errors

**Deployment**:
```
cd workshop/Lab3/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

**See**: `workshop/Lab3/LAB3_SUMMARY.md` for detailed information

---

## Lab 4: Tenant Data Isolation

**Purpose**: Implement fine-grained access control using IAM policies and STS credentials

**Architecture**:
- **Shared Stack**: Same as Lab 3
- **Tenant Stack**: 11 Lambda functions including Business Services Authorizer
- 3 IAM roles for tenant data isolation
- Pooled DynamoDB tables with IAM policy enforcement

**Key Features**:
- IAM policy-based row-level security
- STS credential generation per request
- Tenant-scoped access to DynamoDB
- Cross-tenant data access prevention

**Critical Bugs Fixed**:
1. **Lambda Authorizer IAM Role Name Mismatch**: Added region suffix to role ARN
2. **SAM Configuration Region Mismatch**: Updated tenant-samconfig.toml to us-west-2
3. **Region Configuration Consistency**: Updated all labs to use consistent region

**Deployment**:
```
cd workshop/Lab4/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

**See**: `workshop/Lab4/LAB4_SUMMARY.md` for detailed information

---

## Lab 5: Tier-Based Deployment Strategies

**Purpose**: Automate tenant infrastructure deployment using CodePipeline and CDK

**Architecture**:
- **Shared Stack**: Same as Lab 3/4
- **Pipeline Stack (CDK)**: CodePipeline, CodeBuild, CodeCommit, Lambda trigger
- S3 bucket with predictable naming pattern
- CloudWatch logs with 60-day retention

**Key Features**:
- Automated pipeline deployment on tenant creation
- Tier-based infrastructure (Basic, Standard, Premium, Platinum)
- CDK infrastructure as code
- Python 3.14 runtime support

**Critical Enhancements**:
1. **CloudWatch Log Groups**: Added 60-day retention
2. **Predictable S3 Bucket Naming**: Added ShortId suffix
3. **CodeBuild Image Update**: Updated to AMAZON_LINUX_2023_5
4. **Python Runtime Update**: Updated buildspec to Python 3.11
5. **Empty Tenant Handling**: Lambda handles empty tenant table

**Deployment**:
```
cd workshop/Lab5/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**See**: `workshop/Lab5/LAB5_SUMMARY.md` for detailed information

---

## Lab 6: Tenant-Based Throttling

**Purpose**: Implement rate limiting and throttling based on tenant tiers

**Architecture**:
- **Shared Stack**: Same as Lab 5
- **Pipeline Stack (CDK)**: Same as Lab 5 with throttling configuration
- API Gateway usage plans for tier-based rate limiting

**Key Features**:
- Tenant-based throttling policies
- API Gateway usage plans
- Tier-specific rate limits
- Automated pipeline deployment with throttling

**Critical Fixes Applied**:
1. **Stack Naming Standardization**: Removed "workshop" keyword
2. **Parameter Duplication Fix**: Fixed duplicate parameters in shared-template.yaml
3. **Application UI Deployment Fix**: Fixed stack name query
4. **Python 3.14 Compatibility**: Added --use-container flag
5. **Deploy Stage Parameter Fix**: Added required CloudFormation parameters

**Deployment**:
```
cd workshop/Lab6/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

**See**: `workshop/Lab6/LAB6_SUMMARY.md` for detailed information

---

## Lab 7: Cost Attribution

**Purpose**: Track and attribute costs to individual tenants in pooled architecture

**Architecture**:
- **Main Stack**: Product service Lambda functions, Lambda layer for metrics
- **Tenant Stack**: Tenant-specific product operations
- CloudWatch custom metrics for tenant usage
- Sample CUR data for cost analysis

**Key Features**:
- Cost attribution per tenant
- Custom CloudWatch metrics
- Lambda layers for metrics publishing
- Tenant usage analysis

**Critical Fixes Applied**:
1. **Region Mismatch**: Updated tenant-samconfig.toml to us-east-1
2. **Lambda Tags Format**: Converted Tags to array format
3. **S3 Bucket Configuration**: Added explicit s3_bucket
4. **CloudFormation Parameters**: Added required parameters
5. **Retry Logic Removed**: Simplified deployment script

**Deployment**:
```
cd workshop/Lab7/scripts
./deployment.sh --profile serverless-saas-demo
```

**Important**: Wait 5-10 minutes after cleanup before redeploying.

**See**: `workshop/Lab7/LAB7_SUMMARY.md` for detailed information

---

## Common Patterns Across All Labs

### Resource Naming Convention
- Stack names: `serverless-saas-{shared|tenant}-lab{N}`
- DynamoDB tables: `{TableName}-lab{N}`
- S3 buckets: `serverless-saas-lab{N}-{purpose}-{ShortId}`

### Resource Tagging
All resources tagged with:
- Application: serverless-saas
- Lab: lab{N}
- Environment: prod
- Owner: serverless-saas-lab{N}
- CostCenter: serverless-saas-lab{N}

### CloudWatch Logs
- All Lambda functions: 60-day retention
- API Gateway access logs: 60-day retention
- API Gateway execution logs: Infinite retention (technical limitation)
- CodeBuild logs: 60-day retention

### Python Runtime
- All Lambda functions use Python 3.14 runtime
- CodeBuild uses Python 3.11 for SAM builds

### AWS Profile Support
- All scripts support `--profile` parameter
- Default profile: serverless-saas-demo
- Can be overridden with `--profile <profile-name>`

### Cleanup Process
All cleanup scripts follow secure deletion order:
1. Delete CloudFormation stacks (includes CloudFront distributions)
2. Wait for stack DELETE_COMPLETE
3. Delete S3 buckets (safe after CloudFront is gone)
4. Delete CloudWatch log groups
5. Delete Cognito User Pools (Lab 2+)
6. Delete CodeCommit repositories (Lab 5+)

**Security Note**: This order prevents CloudFront Origin Hijacking vulnerability.

---

## Cross-Lab Dependencies

### Lab Progression
- **Lab 1**: Standalone - no dependencies
- **Lab 2**: Standalone - no dependencies
- **Lab 3**: Standalone - creates its own complete infrastructure (Cognito, tenant management, shared services)
- **Lab 4**: Standalone - self-contained with IAM-based isolation
- **Lab 5**: Standalone - self-contained with tier-based deployment
- **Lab 6**: Standalone - self-contained with tenant throttling
- **Lab 7**: Standalone - generates its own sample data for cost attribution
- **Lab 6**: Extends Lab 5 with throttling
- **Lab 7**: Standalone - demonstrates cost attribution

### Shared Concepts
- **Tenant Management**: Labs 2-6
- **Pooled Architecture**: Labs 3-6
- **API Gateway**: All labs
- **CloudFront**: Labs 1-6
- **CodePipeline**: Labs 5-6
- **CDK**: Labs 5-6

---

## Troubleshooting Guide

### Common Issues

**1. Node.js Version**
- Requires Node.js LTS (v20.x or v22.x)
- See `workshop/NODEJS_LTS_SETUP.md`

**2. AWS Profile**
- All scripts require `--profile` parameter
- Default: serverless-saas-demo

**3. Region Configuration**
- Default region: us-west-2 (Labs 1-4) or us-east-1 (Labs 5-7)
- Can be overridden with `--region` parameter

**4. S3 Bucket Conflicts**
- Wait 5-10 minutes between cleanup and redeployment
- S3 eventual consistency requires propagation time

**5. CDK Bootstrap (Lab 5+)**
- Required for Labs 5-6
- Run once per account/region combination

**6. CloudFormation Stack Deletion**
- CloudFront distributions take 15-30 minutes to delete
- Wait for DELETE_COMPLETE before redeploying

---

## Additional Documentation

### Global Documentation
- `workshop/DEPLOYMENT_CLEANUP_MANUAL.md` - Comprehensive deployment guide
- `workshop/DEPLOYMENT_SCRIPTS_REVIEW.md` - Script analysis and best practices
- `workshop/CLOUDFRONT_SECURITY_FIX.md` - CloudFront Origin Hijacking prevention
- `workshop/RESOURCE_NAMING_CONVENTION.md` - Naming standards
- `workshop/PREREQUISITES.md` - Workshop requirements
- `workshop/NODEJS_LTS_SETUP.md` - Node.js installation guide

### Lab-Specific Documentation
Each lab has an `extra-info/` folder containing detailed documentation about:
- Deployment fixes and enhancements
- Bug fixes and resolutions
- Architecture changes
- Resource naming updates
- Security improvements

---

## Requirements Validated

All labs validate the following requirements:
- **4.1**: Resource tagging completeness
- **4.2**: Cleanup script completeness
- **9.1**: Deployment success
- **10.1**: Script functionality
- **10.2**: Error handling
- **10.3**: Profile parameter support

---

## Contact and Support

For issues or questions:
1. Check lab-specific `LAB{N}_SUMMARY.md` files
2. Review `extra-info/` folders for detailed documentation
3. Consult `workshop/DEPLOYMENT_CLEANUP_MANUAL.md` for deployment guidance
4. Review `workshop/TROUBLESHOOTING.md` (if available)
