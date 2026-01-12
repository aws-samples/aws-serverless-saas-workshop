# Lab5 Deployment Guide - Avoiding Connection Timeouts

## Quick Start

Run the deployment in a persistent screen session:

```bash
cd aws-serverless-saas-workshop/Lab5/scripts
./deploy-with-screen.sh
```

This will start the deployment in a way that survives connection drops.

## What's New in the Updated Script

The deployment script now includes:

1. **Automatic Code Push** - Pushes your current branch to CodeCommit main before deploying the pipeline
2. **DynamoDB Wait** - Waits for all DynamoDB tables to be fully active before proceeding
3. **Better Error Handling** - Clear error messages and exit codes
4. **Status Messages** - Visual feedback for each deployment step

## Common Issues

If you encounter errors during deployment, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for detailed solutions.

### Quick Fixes

**Pipeline deploying old code?**
```bash
# The script now auto-pushes, but if needed manually:
git push cc HEAD:main --force
aws codepipeline start-pipeline-execution --name serverless-saas-pipeline
```

**Stack in ROLLBACK_COMPLETE?**
```bash
# Check the failure reason
aws cloudformation describe-stack-events --stack-name stack-lab5-pooled \
  --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[ResourceStatusReason]' \
  --output text
```

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for complete solutions.

## Screen Session Commands

### During Deployment

- **Detach from session** (deployment keeps running): `Ctrl+A`, then press `D`
- **Reconnect to session**: `screen -r lab5-deployment`
- **View all sessions**: `screen -ls`

### If You Get Disconnected

Simply reconnect:
```bash
screen -r lab5-deployment
```

### To Stop a Running Deployment

```bash
# First, reconnect to the session
screen -r lab5-deployment

# Then press Ctrl+C to stop the deployment

# Or kill the session entirely
screen -X -S lab5-deployment quit
```

## Manual Deployment (without screen)

If you prefer to run the deployment directly:

```bash
cd aws-serverless-saas-workshop/Lab5/scripts

# Full deployment (server + client)
./deployment.sh -s -c

# Or split into steps:
./deployment.sh -p    # Deploy pipeline only
./deployment.sh -b    # Deploy bootstrap server
./deployment.sh -c    # Deploy client
```

## Troubleshooting

### "A deployment session is already running"

This means a previous deployment is still active. You can:

1. **Reconnect to it**: `screen -r lab5-deployment`
2. **Kill it and start fresh**: `screen -X -S lab5-deployment quit`

### Check deployment logs

If running in screen, reconnect and scroll up to see logs:
- Reconnect: `screen -r lab5-deployment`
- Scroll mode: `Ctrl+A`, then `[` (use arrow keys, press `Esc` to exit)

### Connection keeps timing out even with screen

Make sure you're detaching properly (`Ctrl+A` then `D`) rather than closing the terminal window.

## Expected Deployment Time

- **Pipeline deployment**: ~5-10 minutes
- **Server deployment**: ~10-15 minutes  
- **Client deployment**: ~5-10 minutes
- **Total**: ~20-35 minutes

The deployment will continue even if you disconnect!
