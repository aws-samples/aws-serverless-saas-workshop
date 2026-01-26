# Workshop Master Scripts

This directory contains master scripts for deploying and cleaning up all labs in the AWS Serverless SaaS Workshop.

## Scripts Overview

- **deploy-all-labs.sh** - Deploy one or more labs with proper parameters
- **cleanup-all-labs.sh** - Clean up one or more labs in reverse order

## Prerequisites

Before running these scripts, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **SAM CLI** installed
3. **Node.js** and **npm** installed
4. **Python 3** installed
5. Sufficient AWS permissions to create:
   - CloudFormation stacks
   - Lambda functions
   - DynamoDB tables
   - S3 buckets
   - Cognito User Pools
   - API Gateway APIs
   - IAM roles and policies

## Deploy All Labs Script

### Usage

```
./deploy-all-labs.sh [OPTIONS]
```

### Options

- `--all` - Deploy all labs (default if no options provided)
- `--lab <number>` - Deploy specific lab (can be used multiple times)
- `--lab1-stack-name <name>` - Stack name for Lab1 (default: `serverless-saas-lab1`)
- `--email <email>` - Email address for Lab2 (required if deploying Lab2)
- `--skip-verification` - Skip prerequisite verification
- `--continue-on-error` - Continue deploying next lab even if current fails
- `--help` - Show help message

### Lab-Specific Requirements

- **Lab1**: Requires `--lab1-stack-name` (default provided)
- **Lab2**: Requires `--email` parameter
- **Lab3-7**: No additional parameters required

### Examples

**Deploy all labs:**
```
./deploy-all-labs.sh --all --email user@example.com
```

**Deploy specific labs:**
```
# Deploy only Lab5
./deploy-all-labs.sh --lab 5

# Deploy Lab5 and Lab6
./deploy-all-labs.sh --lab 5 --lab 6

# Deploy Lab1 with custom stack name
./deploy-all-labs.sh --lab 1 --lab1-stack-name my-custom-stack

# Deploy Lab2 with email
./deploy-all-labs.sh --lab 2 --email admin@example.com
```

**Deploy all labs with error handling:**
```
# Continue deploying even if a lab fails
./deploy-all-labs.sh --all --email user@example.com --continue-on-error
```

### What Each Lab Deploys

- **Lab1**: Basic serverless application with API Gateway and Lambda
- **Lab2**: Multi-tenant architecture with Cognito authentication
- **Lab3**: Tenant isolation with separate stacks (shared + tenant)
- **Lab4**: Advanced tenant isolation with custom domains
- **Lab5**: CI/CD pipeline with CodePipeline and CodeBuild
- **Lab6**: Tenant-specific throttling and API Gateway usage plans
- **Lab7**: Cost attribution with CloudWatch Logs Insights and Athena

### Deployment Time

- **Lab1**: ~3-5 minutes
- **Lab2**: ~5-7 minutes
- **Lab3**: ~7-10 minutes
- **Lab4**: ~8-12 minutes
- **Lab5**: ~10-15 minutes
- **Lab6**: ~12-18 minutes
- **Lab7**: ~5-6 minutes

**Total for all labs**: ~50-70 minutes

## Cleanup All Labs Script

### Usage

```
./cleanup-all-labs.sh [OPTIONS]
```

### Options

- `--all` - Cleanup all labs (default if no options provided)
- `--lab <number>` - Cleanup specific lab (can be used multiple times)
- `--help` - Show help message

### Examples

**Cleanup all labs:**
```
./cleanup-all-labs.sh
# or
./cleanup-all-labs.sh --all
```

**Cleanup specific labs:**
```
# Cleanup only Lab5
./cleanup-all-labs.sh --lab 5

# Cleanup Lab5 and Lab6
./cleanup-all-labs.sh --lab 5 --lab 6
```

### Cleanup Order

Labs are cleaned up in **reverse order** (Lab7 → Lab1) to handle dependencies properly. When cleaning up specific labs, they are automatically sorted in reverse order.

### What Gets Cleaned Up

For each lab, the cleanup script removes:

1. **S3 Buckets** - Emptied and deleted
2. **CloudFormation Stacks** - All lab-specific stacks
3. **DynamoDB Tables** - All lab-specific tables
4. **CloudWatch Log Groups** - All Lambda function logs
5. **EventBridge Rules** - Scheduled rules (Lab7)
6. **IAM Roles** - Lab-specific execution roles

### Cleanup Time

- **Per lab**: ~2-3 minutes
- **All labs**: ~15-20 minutes

## Individual Lab Scripts

Each lab also has its own deployment and cleanup scripts in `Lab{N}/scripts/`:

### Lab1
```
# Deploy
cd Lab1/scripts
./deployment.sh -s -c --stack-name serverless-saas-lab1

# Cleanup
./cleanup.sh --stack-name serverless-saas-lab1
```

### Lab2
```
# Deploy
cd Lab2/scripts
./deployment.sh -s -c --email user@example.com

# Cleanup
./cleanup.sh
```

### Lab3-6
```
# Deploy
cd Lab{N}/scripts
./deployment.sh -s -c

# Cleanup
./cleanup.sh
```

### Lab7
```
# Deploy
cd Lab7/scripts
./deployment.sh

# Cleanup
./cleanup.sh
```

## Logs

All scripts create timestamped log files:

- **Deployment logs**: `logs/deploy-all-labs-YYYYMMDD-HHMMSS.log`
- **Cleanup logs**: `logs/cleanup-all-labs-YYYYMMDD-HHMMSS.log`
- **Individual lab logs**: `Lab{N}/scripts/deployment-YYYYMMDD-HHMMSS.log`

## Troubleshooting

### Deployment Failures

1. **Check prerequisites**: Run with `--skip-verification` to bypass checks
2. **Review logs**: Check the timestamped log file for detailed errors
3. **AWS credentials**: Ensure AWS CLI is configured correctly
4. **Resource limits**: Check AWS service quotas for your account
5. **Continue on error**: Use `--continue-on-error` to deploy remaining labs

### Cleanup Issues

1. **Stack deletion failures**: Manually delete resources blocking stack deletion
2. **S3 bucket errors**: Ensure buckets are empty before deletion
3. **Partial cleanup**: Run cleanup script again to retry failed deletions
4. **Manual verification**: Check AWS Console for remaining resources

### Common Issues

**Lab2 email requirement:**
```
# Error: Lab2 requires --email parameter
# Solution: Provide email address
./deploy-all-labs.sh --lab 2 --email admin@example.com
```

**Stack already exists:**
```
# Error: Stack already exists
# Solution: Run cleanup first
./cleanup-all-labs.sh --lab 5
./deploy-all-labs.sh --lab 5
```

**Permission denied:**
```
# Error: Permission denied
# Solution: Make scripts executable
chmod +x deploy-all-labs.sh cleanup-all-labs.sh
```

## Best Practices

1. **Clean before deploy**: Always cleanup before redeploying a lab
2. **Use email parameter**: Provide a valid email for Lab2 to receive Cognito notifications
3. **Monitor logs**: Watch log files during deployment for real-time progress
4. **Verify cleanup**: Check AWS Console after cleanup to ensure all resources are removed
5. **Sequential deployment**: Deploy labs in order (1→7) for best results
6. **Resource naming**: Use consistent naming conventions for easy identification

## Resource Naming Convention

All resources follow the pattern: `serverless-saas-lab{N}-{resource-type}-{optional-suffix}`

Examples:
- CloudFormation stacks: `serverless-saas-lab5`
- Lambda functions: `serverless-saas-lab5-create-tenant`
- DynamoDB tables: `ServerlessSaaS-Settings-lab5`
- S3 buckets: `serverless-saas-lab5-admin-{ShortId}`

See [RESOURCE_NAMING_CONVENTION.md](../RESOURCE_NAMING_CONVENTION.md) for complete details.

## Support

For issues or questions:
1. Check individual lab DEPLOYMENT_GUIDE.md files
2. Review TROUBLESHOOTING.md files in each lab
3. Check CloudFormation stack events in AWS Console
4. Review CloudWatch Logs for Lambda function errors

## Contributing

When modifying these scripts:
1. Follow the workshop development guide conventions
2. Test in a fresh AWS account
3. Update this README with any changes
4. Commit with conventional commit format
