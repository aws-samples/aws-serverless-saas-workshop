# Workshop Quick Reference Card

## Prerequisites Checklist
- [ ] AWS CLI installed and configured
- [ ] AWS profile `serverless-saas-demo` configured
- [ ] AWS SAM CLI installed
- [ ] Python 3.14 installed
- [ ] Node.js installed (for Labs 2-6)
- [ ] Valid AWS credentials configured

## Verify AWS Profile
```bash
aws sts get-caller-identity --profile serverless-saas-demo
```

## One-Line Deploy Commands

```bash
# Lab 1
cd workshop/Lab1/server && sam build && sam deploy --config-file samconfig.toml --profile serverless-saas-demo

# Lab 2
cd workshop/Lab2/server && ./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com

# Lab 3
cd workshop/Lab3/server && ./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com

# Lab 4
cd workshop/Lab4/server && ./deployment.sh -s -c -e admin@example.com -te tenant-admin@example.com

# Lab 5
cd workshop/Lab5/server && ./deployment.sh -s -c

# Lab 6
cd workshop/Lab6/server && ./deploy-with-screen.sh

# Lab 7
cd workshop/Lab7 && sam build && sam deploy --config-file samconfig.toml --profile serverless-saas-demo
```

## One-Line Cleanup

```bash
# All Labs (automatic - no prompts)
cd workshop/scripts && ./cleanup.sh

# Interactive mode (with confirmations)
cd workshop/scripts && ./cleanup.sh -i
```

## Default Credentials

```
Admin User:
  username: admin-user
  password: SaaS#Workshop2026

Tenant Admin:
  username: tenant-admin
  password: SaaS#Workshop2026
```

## Stack Names

| Lab | Stack Name(s) |
|-----|---------------|
| Lab 1 | `serverless-saas-workshop-lab1` |
| Lab 2 | `stack-pooled` |
| Lab 3 | `stack-pooled`, `stack-<tenant-id>` |
| Lab 4 | `stack-pooled`, `stack-<tenant-id>` |
| Lab 5 | `serverless-saas`, `serverless-saas-pipeline` |
| Lab 6 | `stack-pooled`, `stack-<tenant-id>` |
| Lab 7 | `serverless-saas-cost-per-tenant-lab7` |

## Quick Verification

```bash
# List all workshop stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --profile serverless-saas-demo | grep -E "serverless-saas|stack-"

# Check log groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/serverless-saas \
  --profile serverless-saas-demo

# List S3 buckets
aws s3 ls --profile serverless-saas-demo | grep serverless-saas
```

## Common Issues

| Issue | Solution |
|-------|----------|
| Profile not found | Configure with `aws configure --profile serverless-saas-demo` |
| Stack already exists | Delete stack or use `--no-confirm-changeset` |
| Build fails | Check Python/Node.js versions |
| Deployment timeout | Check CloudWatch logs for errors |
| Cleanup fails | Run cleanup script with `-i` flag for interactive mode |

## Important Files

- **Full Manual**: `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
- **Cleanup Script**: `workshop/scripts/cleanup.sh`
- **Lab Credentials**: `workshop/credentials.txt`
- **This Reference**: `workshop/QUICK_REFERENCE.md`

## CloudWatch Logs

- **Retention**: 60 days (all labs)
- **Lambda Logs**: `/aws/lambda/${StackName}-<FunctionName>`
- **API Gateway Logs**: `/aws/api-gateway/access-logs-serverless-saas-*`
- **Total Log Groups**: 84 (74 Lambda + 10 API Gateway)

## Support Commands

```bash
# Get stack outputs
aws cloudformation describe-stacks \
  --stack-name <stack-name> \
  --profile serverless-saas-demo \
  --query 'Stacks[0].Outputs'

# Get stack events (for troubleshooting)
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --profile serverless-saas-demo \
  --max-items 20

# Tail Lambda logs
sam logs -n <function-name> \
  --stack-name <stack-name> \
  --profile serverless-saas-demo \
  --tail

# Check SAM version
sam --version

# Check AWS CLI version
aws --version

# Verify AWS profile
aws sts get-caller-identity --profile serverless-saas-demo
```
