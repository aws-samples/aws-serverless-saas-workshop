# Workshop Lab Stack Architecture

This document defines the correct CloudFormation stack architecture for each lab in the Serverless SaaS Workshop.

## Stack Mapping by Lab

### Lab 1: Basic Serverless Web Application
**Stacks: 1**
- `serverless-saas-lab1` - Main application stack

### Lab 2: SaaS Shared Services
**Stacks: 1**
- `serverless-saas-lab2` - Shared services stack

### Lab 3: Multi-Tenancy in Microservices
**Stacks: 2**
- `serverless-saas-shared-lab3` - Shared services
- `serverless-saas-tenant-lab3` - Tenant-specific resources

### Lab 4: Tenant Data Isolation (Pooled Model)
**Stacks: 2**
- `serverless-saas-shared-lab4` - Shared services with isolation
- `serverless-saas-tenant-lab4` - Tenant resources with isolation

### Lab 5: Tier-Based Deployment Strategies
**Stacks: 2**
- `serverless-saas-shared-lab5` - Shared services
- `serverless-saas-pipeline-lab5` - CI/CD pipeline for Lab5 (DISTINCT from Lab6)

### Lab 6: Throttling and Rate Limiting
**Stacks: 3+**
- `serverless-saas-shared-lab6` - Shared services
- `serverless-saas-pipeline-lab6` - CI/CD pipeline for Lab6 (DISTINCT from Lab5)
- `stack-lab6-pooled` - Pooled tenant stack (created by pipeline)
- Additional tenant stacks may be created with pattern: `stack-*-lab6`

**Note**: Lab6's pipeline automatically creates tenant stacks. The pooled stack is created during deployment and additional tier-specific stacks may be created based on tenant tier configuration.

### Lab 7: Cost Attribution (Pooled Model)
**Stacks: 2**
- `serverless-saas-lab7` - Main application stack
- `stack-pooled-lab7` - Pooled tenant stack

## Critical Distinctions

### Lab5 vs Lab6 Pipeline Stacks
These are **COMPLETELY INDEPENDENT** CI/CD pipelines:
- `serverless-saas-pipeline-lab5` belongs ONLY to Lab5
- `serverless-saas-pipeline-lab6` belongs ONLY to Lab6

When Lab5 is deleted, ONLY `serverless-saas-pipeline-lab5` should be removed.
When Lab6 is deleted, ONLY `serverless-saas-pipeline-lab6` should be removed.

### Lab6 and Lab7 Tenant Stacks
Lab6 and Lab7 create additional tenant stacks dynamically:

**Lab6 Tenant Stack Pattern**: `stack-*-lab6`
- Examples: `stack-lab6-pooled`, `stack-basic-lab6`, `stack-premium-lab6`
- Created by the Lab6 pipeline based on tenant tier configuration
- All tenant stacks follow the pattern and include "lab6" in the name

**Lab7 Tenant Stack**: `stack-pooled-lab7`
- Single pooled tenant stack for cost attribution analysis
- Created during Lab7 deployment

## Isolation Verification Requirements

When verifying lab isolation during cleanup:

1. **Core Stacks**: Verify all core stacks for the deleted lab are removed
2. **Tenant Stacks**: For Lab6 and Lab7, verify tenant stacks matching their patterns are removed
3. **Other Labs**: Verify NO stacks from other labs are affected
4. **Pipeline Stacks**: Verify Lab5 and Lab6 pipeline stacks are correctly distinguished

## Resource Filtering Patterns

Workshop resources follow these naming patterns:
- Stack names: `serverless-saas-*`, `stack-*-lab*`
- S3 buckets: `serverless-saas-*`, `*-lab*-*`
- Log groups: `/aws/lambda/serverless-saas-*`, `/aws/lambda/*-lab*-*`
- Cognito pools: `serverless-saas-*`, `*-lab*-*`
- DynamoDB tables: `serverless-saas-*`, `*-lab*-*`
- IAM roles: `serverless-saas-*`, `*-lab*-*`

## Implementation Notes

### Resource Tracker
The `ResourceTracker` class maintains:
- `LAB_STACK_MAPPING`: Core stacks for each lab
- `LAB_TENANT_STACK_PATTERNS`: Regex patterns for Lab6 and Lab7 tenant stacks

### State Comparator
The `StateComparator.verify_isolation()` method:
- Checks core stacks are deleted for the target lab
- Uses regex patterns to verify tenant stacks for Lab6/Lab7
- Ensures other labs' stacks (including their tenant stacks) remain intact
- Distinguishes between Lab5 and Lab6 pipeline stacks

## Testing Implications

When testing lab isolation:
1. Deploy all labs in parallel
2. For each lab deletion:
   - Verify core stacks are removed
   - For Lab6/Lab7: Verify tenant stacks matching patterns are removed
   - Verify other labs' stacks remain (including their tenant stacks)
   - Verify Lab5 pipeline stack is NOT affected when Lab6 is deleted
   - Verify Lab6 pipeline stack is NOT affected when Lab5 is deleted
