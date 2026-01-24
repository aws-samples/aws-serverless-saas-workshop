# AWS Serverless SaaS Workshop - Baseline Documentation

**Date Created:** January 18, 2026  
**Git Branch:** checkpoint-lab7  
**Git Commit:** 2c5b69c - chore(lab7): remove build artifacts from git tracking  
**Workshop Location:** `/Users/lancdieg/Documents/SA work/2026/Demos/AWS Serverless SaaS Demo/workshop`

## Purpose

This document captures the baseline state of the AWS Serverless SaaS Workshop before modernization efforts begin. It serves as a reference point for tracking changes and validating that all requirements are met.

## Workshop Overview

The AWS Serverless SaaS Workshop is a hands-on learning experience consisting of 7 progressive labs that teach developers how to build multi-tenant SaaS solutions using AWS Serverless services.

### Lab Structure

1. **Lab 1**: Basic serverless web application (DynamoDB, Lambda, API Gateway, Cognito)
2. **Lab 2**: SaaS shared services (tenant onboarding, user management, registration service)
3. **Lab 3**: Multi-tenancy in microservices (authentication, Lambda authorizer, data partitioning)
4. **Lab 4**: Tenant data isolation in pooled model (IAM policies, scoped credentials)
5. **Lab 5**: Tier-based deployment strategies (pooled vs siloed, CodePipeline)
6. **Lab 6**: Tenant throttling and quotas (API Gateway usage plans, API keys)
7. **Lab 7**: Cost attribution in pooled model (CloudWatch metrics, tenant-level cost tracking)

## Directory Structure

```
workshop/
├── .git/                           # Git repository
├── .gitignore                      # Git ignore rules
├── Lab1/                           # Lab 1: Basic serverless web application
│   ├── client/                     # Frontend application
│   ├── server/                     # Backend SAM templates and Lambda functions
│   │   └── template.yaml           # SAM template (Python 3.9)
│   └── scripts/                    # Deployment scripts
│       ├── deployment.sh
│       ├── cleanup.sh
│       └── geturl.sh
├── Lab2/                           # Lab 2: SaaS shared services
│   ├── client/
│   ├── server/
│   │   └── template.yaml           # SAM template (Python 3.9)
│   └── scripts/
│       ├── deployment.sh
│       ├── cleanup.sh
│       ├── deploy-updates.sh
│       └── geturl.sh
├── Lab3/                           # Lab 3: Multi-tenancy in microservices
│   ├── client/
│   ├── server/
│   │   ├── shared-template.yaml    # Shared services template (Python 3.9)
│   │   └── tenant-template.yaml    # Tenant-specific template (Python 3.9)
│   └── scripts/
│       ├── deployment.sh
│       ├── cleanup.sh
│       ├── deploy-updates.sh
│       └── geturl.sh
├── Lab4/                           # Lab 4: Tenant data isolation
│   ├── client/
│   ├── server/
│   │   ├── shared-template.yaml    # Python 3.9
│   │   └── tenant-template.yaml    # Python 3.9
│   └── scripts/
│       ├── deployment.sh
│       ├── cleanup.sh
│       └── geturl.sh
├── Lab5/                           # Lab 5: Tier-based deployment
│   ├── client/
│   ├── server/
│   │   ├── shared-template.yaml    # Python 3.9
│   │   ├── tenant-template.yaml    # Python 3.9
│   │   └── tenant-buildspec.yml    # CodeBuild spec
│   └── scripts/
│       ├── deployment.sh
│       ├── cleanup.sh
│       ├── deploy-updates.sh
│       ├── deploy-with-screen.sh
│       └── geturl.sh
├── Lab6/                           # Lab 6: Tenant throttling
│   ├── client/
│   ├── server/
│   │   ├── shared-template.yaml    # Python 3.9
│   │   ├── tenant-template.yaml    # Python 3.9
│   │   └── tenant-buildspec.yml
│   └── scripts/
│       ├── deployment.sh
│       ├── cleanup.sh
│       ├── deploy-with-screen.sh
│       ├── geturl.sh
│       └── test-basic-tier-throttling.sh
├── Lab7/                           # Lab 7: Cost attribution
│   ├── ProductService/
│   │   └── product_service.py
│   ├── TenantUsageAndCost/
│   │   └── tenant_usage_and_cost.py
│   ├── layers/
│   │   └── logger.py
│   ├── SampleCUR/                  # Sample Cost and Usage Reports
│   ├── template.yaml               # Main template (Python 3.9)
│   ├── tenant-template.yaml        # Tenant template (Python 3.9)
│   └── scripts/
│       ├── deployment.sh
│       └── cleanup.sh
├── scripts/                        # Root-level orchestration scripts
│   ├── deploy-all-labs.sh
│   ├── cleanup-all-labs.sh
│   └── [various utility scripts]
├── Solution/                       # Solution code for all labs
│   ├── Lab1/
│   ├── Lab2/
│   ├── Lab3/
│   ├── Lab4/
│   ├── Lab5/
│   ├── Lab6/
│   └── Lab7/
├── event-engine-assets/            # Event Engine deployment assets
├── README.md                       # Main workshop README
├── RESOURCE_NAMING_CONVENTION.md   # Resource naming standards
├── WORKSHOP_DEPLOYMENT_GUIDE.md    # Deployment guide
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── LICENSE-SAMPLECODE
├── LICENSE-SUMMARY
└── THIRD-PARTY-LICENSES.txt
```

## Current State Analysis

### Python Runtime Status
- **Current Version:** Python 3.9
- **Target Version:** Python 3.14
- **Files Requiring Updates:** All SAM template.yaml files across all labs

### Cloud9 References
- Cloud9Setup directory has been removed ✅
- All Cloud9 references removed from documentation ✅
- Documentation updated with local development environment instructions ✅

### Resource Tagging
- RESOURCE_NAMING_CONVENTION.md exists
- Need to verify if all CloudFormation/SAM templates implement tagging
- Tags should include: TenantId, Environment, Application, Lab, CostCenter, Owner

### Deployment Scripts
- Each lab has deployment.sh, cleanup.sh, and geturl.sh scripts
- Root-level orchestration scripts exist: deploy-all-labs.sh, cleanup-all-labs.sh
- Scripts use AWS profile (need to verify profile name)

### Lab Independence
- Labs 3-7 have both shared-template.yaml and tenant-template.yaml
- Need to verify resource naming prevents conflicts between labs
- Each lab should be independently deployable

## Files Requiring Updates

### SAM Templates (Python Runtime Update)
