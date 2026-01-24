---
inclusion: always
---

# Workshop Deployment and Cleanup Steering Guide

When the user mentions "deploy", "deployment", "cleanup", "clean up", or asks about deploying/cleaning any lab, you MUST read and reference the comprehensive deployment manual located at:

**`workshop/DEPLOYMENT_CLEANUP_MANUAL.md`**

## CRITICAL: Script Execution Rules

**⚠️ NEVER EVER run scripts with `bash` command! ⚠️**

This is a CRITICAL requirement that must ALWAYS be followed. All workshop scripts have proper shebang lines (`#!/bin/bash`) and MUST be executed directly:

✅ **CORRECT:**
```bash
./scripts/deployment.sh -s -c --profile serverless-saas-demo
./scripts/cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

❌ **ABSOLUTELY WRONG - NEVER DO THIS:**
```bash
bash scripts/deployment.sh -s -c --profile serverless-saas-demo
bash scripts/cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

**Why this matters:**
- Scripts use `${BASH_SOURCE[0]}` to determine their location
- Running with `bash` breaks path resolution and causes deployment failures
- Scripts must be executable: `chmod +x scripts/*.sh`
- This is NOT optional - using `bash` WILL cause errors

## CRITICAL: AWS Profile Parameter

**The `--profile` parameter is REQUIRED for all scripts!**

All scripts have been updated to accept the AWS profile via the `--profile` parameter instead of hardcoding it. This makes the scripts more flexible and follows AWS CLI best practices.

**Important:**
- Scripts NO LONGER export `AWS_PROFILE="serverless-saas-demo"` internally
- You MUST pass `--profile <profile-name>` to every script invocation
- Default profile in documentation is `serverless-saas-demo` but any profile can be used
- If `--profile` is omitted, AWS CLI will use the default profile from `~/.aws/config`

## Key Instructions

1. **Always read the manual first** when deployment or cleanup is mentioned
2. **Follow the exact commands** specified in the manual for each lab
3. **Verify prerequisites** before attempting deployment
4. **Use the appropriate cleanup method** based on the lab
5. **Execute scripts directly** (not with `bash` command)

## Quick Command Reference

**IMPORTANT: All commands MUST include `--profile serverless-saas-demo`**

### Lab 1 Deployment
```bash
cd workshop/Lab1/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

### Lab 1 Cleanup
```bash
cd workshop/Lab1/scripts
./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
```

### Lab 2 Deployment
```bash
cd workshop/Lab2/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --profile serverless-saas-demo
```

### Lab 3 Deployment
```bash
cd workshop/Lab3/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

### Lab 4 Deployment
```bash
cd workshop/Lab4/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

### Lab 5 Deployment
```bash
cd workshop/Lab5/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

### Lab 6 Deployment
```bash
cd workshop/Lab6/scripts
./deployment.sh -s -c --profile serverless-saas-demo
```

### Lab 7 Deployment
```bash
cd workshop/Lab7
sam build -t template.yaml
sam deploy --config-file samconfig.toml --profile serverless-saas-demo
```

### Global Cleanup
```bash
cd workshop/scripts
./cleanup.sh --profile serverless-saas-demo
# Runs automatically without prompts

# Or interactive mode with confirmations:
./cleanup.sh --profile serverless-saas-demo -i
```

## Important Notes

- **CRITICAL**: NEVER use `bash` command to run scripts - always execute directly with `./script.sh`
- **CRITICAL**: The `--profile` parameter is REQUIRED for all script invocations
- **Default email for all labs**: `lancdieg@amazon.com` (used for admin and tenant accounts)
- Scripts no longer hardcode AWS profile - it must be passed via `--profile` parameter
- Default profile in documentation is `serverless-saas-demo` but any valid AWS profile can be used
- All labs use AWS SAM for deployment
- Default region is `us-west-2`
- All CloudWatch logs have 60-day retention
- Cleanup script runs automatically without prompts (use `-i` for interactive mode)
- Cleanup script handles all resource types (stacks, S3, logs, Cognito, CodeCommit)

## When User Asks to Deploy

1. Read `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
2. Identify which lab they want to deploy
3. Verify prerequisites (AWS CLI, SAM CLI, Docker)
4. Show the exact commands from the manual
5. Explain what will be deployed
6. Offer to execute the commands if in autopilot mode

## When User Asks to Cleanup

1. Read `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
2. Explain what will be deleted
3. Show the cleanup command
4. Warn about data loss
5. Offer to execute if in autopilot mode

## Verification Steps

After deployment, always suggest verification:
- Check CloudFormation stack status
- Verify CloudWatch log groups exist with 60-day retention
- Test API endpoints if applicable
- Check outputs for URLs and resource names

After cleanup, always suggest verification:
- Confirm stacks are deleted
- Verify log groups are removed
- Check S3 buckets are deleted
- Confirm Cognito pools are removed
