# AWS Serverless SaaS Workshop - Baseline State Documentation

**Date:** January 18, 2026  
**Branch:** checkpoint-lab7  
**Purpose:** Document the current state of the workshop before modernization begins

## Overview

This document captures the baseline state of the AWS Serverless SaaS Workshop repository before any modernization changes are applied. This serves as a reference point for tracking changes and validating the modernization effort.

## Git Information

- **Current Branch:** checkpoint-lab7
- **Repository Location:** `/Users/lancdieg/Documents/SA work/2026/Demos/AWS Serverless SaaS Demo/workshop`
- **Backup Tag:** Will be created as `pre-modernization-baseline`

## Workshop Structure

The workshop consists of 7 progressive labs teaching multi-tenant SaaS development:

### Lab 1: Basic Serverless Web Application
- **Location:** `workshop/Lab1/`
- **Components:** DynamoDB, Lambda, API Gateway, Cognito
- **SAM Template:** `Lab1/server/template.yaml`
- **Scripts:** deployment.sh, cleanup.sh, geturl.sh
- **Status:** Has deployment scripts

### Lab 2: SaaS Shared Services
- **Location:** `workshop/Lab2/`
- **Components:** Tenant onboarding, user management, registration service
- **Scripts:** deployment.sh, cleanup.sh, geturl.sh
- **Status:** Has deployment scripts

### Lab 3: Multi-Tenancy in Microservices
- **Location:** `workshop/Lab3/`
- **Components:** Authentication, Lambda authorizer, data partitioning
- **Scripts:** deployment.sh, cleanup.sh, geturl.sh
- **Status:** Has deployment scripts

### Lab 4: Tenant Data Isolation
- **Location:** `workshop/Lab4/`
- **Components:** IAM policies, scoped credentials
- **Scripts:** No deployment scripts found in main Lab4 directory
- **Status:** Missing deployment scripts

### Lab 5: Tier-Based Deployment
- **Location:** `workshop/Lab5/`
- **Components:** Pooled vs siloed, CodePipeline
- **Scripts:** deployment.sh, cleanup.sh, geturl.sh
- **Status:** Has deployment scripts

### Lab 6: Tenant Throttling and Quotas
- **Location:** `workshop/Lab6/`
- **Components:** API Gateway usage plans, API keys
- **Scripts:** deployment.sh, cleanup.sh, geturl.sh
- **Status:** Has deployment scripts

### Lab 7: Cost Attribution
- **Location:** `workshop/Lab7/`
- **Components:** CloudWatch metrics, tenant-level cost tracking
- **SAM Template:** `Lab7/template.yaml`
- **Scripts:** deployment.sh, cleanup.sh
- **Status:** Has deployment scripts (no geturl.sh)

## Current Infrastructure Templates

### SAM Templates Found
```
workshop/Lab1/server/template.yaml
workshop/Lab7/template.yaml
workshop/Solution/Lab1/server/template.yaml
workshop/Solution/Lab2/server/template.yaml
workshop/Solution/Lab7/template.yaml
```

### Nested Templates
Lab 6 has nested templates in:
```
workshop/Lab6/server/.aws-sam/build/LambdaFunctions/template.yaml
workshop/Lab6/server/.aws-sam/build/APIGatewayLambdaPermissions/template.yaml
workshop/Lab6/server/.aws-sam/build/APIs/template.yaml
workshop/Lab6/server/.aws-sam/build/DynamoDBTables/template.yaml
workshop/Lab6/server/.aws-sam/build/Cognito/template.yaml
workshop/Lab6/server/.aws-sam/build/UserInterface/template.yaml
workshop/Lab6/server/.aws-sam/build/CustomResources/template.yaml
```

Lab 5 has nested templates in:
```
workshop/Lab5/server/.aws-sam/build/LambdaFunctions/template.yaml
workshop/Lab5/server/.aws-sam/build/APIGatewayLambdaPermissions/template.yaml
```

## Deployment Scripts Status

### Labs with Complete Script Sets (deployment.sh, cleanup.sh, geturl.sh)
- Lab 1 ✓
- Lab 2 ✓
- Lab 3 ✓
- Lab 5 ✓
- Lab 6 ✓

### Labs with Partial Scripts
- Lab 7: Has deployment.sh and cleanup.sh, missing geturl.sh

### Labs Missing Scripts
- Lab 4: No deployment scripts found in main directory

### Solution Directory Scripts
All solution labs (Lab1-Lab7) have deployment and geturl scripts in `workshop/Solution/LabX/scripts/`

## Root-Level Scripts

### Current Root Scripts
- `workshop/scripts/` directory exists with README.md

### Missing Root Scripts (To Be Created)
- deploy-all-labs.sh
- cleanup-all-labs.sh

## Documentation Files

### Existing Documentation
- `workshop/README.md` - Main workshop README
- `workshop/BASELINE_DOCUMENTATION.md` - Baseline documentation
- `workshop/RESOURCE_NAMING_CONVENTION.md` - Resource naming standards
- `workshop/WORKSHOP_DEPLOYMENT_GUIDE.md` - Deployment guide
- `workshop/CODE_OF_CONDUCT.md`
- `workshop/CONTRIBUTING.md`
- `workshop/LICENSE`

### Lab-Specific READMEs
- Need to verify existence in each lab directory

## Cloud9 References

### Cloud9 Directory
- `workshop/Cloud9Setup/` - ✅ REMOVED as part of modernization

### Cloud9 References in Documentation
- ✅ All markdown files updated with local development instructions
- ✅ Replaced with local development environment setup

## Python Runtime Status

### Current Python Version
- **Expected:** Python 3.9 (based on requirements)
- **Target:** Python 3.14

### Files Requiring Runtime Updates
- All `template.yaml` files with Lambda function definitions
- All Lambda layer configurations
- Python requirements.txt files

## Resource Tagging Status

### Current State
- Need to verify if resources have tags
- Need to check compliance with RESOURCE_NAMING_CONVENTION.md

### Required Tags (Per Requirements)
- TenantId (where applicable)
- Environment
- Application: serverless-saas-workshop
- Lab: lab1, lab2, etc.
- CostCenter
- Owner

## TODO Comments

### Status
- Need to search all Python files for TODO comments
- Must preserve all TODOs during modernization (for workshop participants)

## Known Issues and Gaps

### Missing Components
1. Lab 4 deployment scripts
2. Lab 7 geturl.sh script
3. Root-level orchestration scripts (deploy-all-labs.sh, cleanup-all-labs.sh)
4. Individual lab README.md files (need verification)

### Modernization Requirements
1. Update Python runtime from 3.9 to 3.14
2. Add resource tagging to all CloudFormation/SAM templates
3. Remove Cloud9 references and directory
4. Create/improve deployment scripts for all labs
5. Create root-level orchestration scripts
6. Ensure lab independence (unique resource naming)
7. Create comprehensive README.md for each lab

## File Counts

### Template Files
- Primary SAM templates: 5 found
- Nested templates: Multiple in Lab5 and Lab6 .aws-sam/build directories

### Script Files
- Deployment scripts: 9 found (including Solution directory)
- Cleanup scripts: 6 found
- Geturl scripts: 8 found

### Documentation Files
- Root-level docs: 7 files
- Lab-specific READMEs: To be verified

## Next Steps

1. Create git tag for baseline backup
2. Begin Task 2: Update Python runtime across all labs
3. Systematically work through remaining tasks in implementation plan

## Validation Checklist

- [x] Git branch verified (checkpoint-lab7)
- [x] Directory structure documented
- [x] SAM templates identified
- [x] Deployment scripts cataloged
- [x] Missing components identified
- [x] Modernization requirements understood
- [x] Git backup tag created (pre-modernization-baseline)
- [x] Ready to proceed with Task 2

## Notes

- The workshop has a mix of complete and incomplete lab setups
- Solution directory contains reference implementations
- Some labs have complex nested template structures
- Lab independence will require careful resource naming strategy
- ✅ Cloud9 setup directory has been completely removed

---

**Document Status:** Complete  
**Next Action:** Create git backup tag and mark Task 1 as complete
