# Lab 5 Deployment Script Comparison

## Critical Differences Between Old and New Scripts

### 1. **AWS Profile Handling** ✅ IMPROVED
**Old Script:**
- Used `aws configure get region` to get region
- No profile parameter support
- Relied on default AWS credentials

**New Script:**
- Accepts `--profile` parameter
- Uses `get_profile_arg()` function to build profile arguments
- Sets `PROFILE_ARG` variable for consistent use across all AWS CLI commands
- Properly passes profile to all AWS CLI and SAM CLI commands

### 2. **Region Configuration** ✅ IMPROVED
**Old Script:**
- Used `REGION=$(aws configure get region)` - relied on AWS CLI config
- No explicit region parameter

**New Script:**
- Defaults to `us-west-2`
- Accepts `--region` parameter
- Explicitly passes `--region` to all AWS CLI commands

### 3. **Error Handling** ✅ IMPROVED
**Old Script:**
- Basic error checking with `if [[ $? -ne 0 ]]`
- No `set -e` (script continues on errors)
- Minimal validation

**New Script:**
- Uses `set -e` (exits on any error)
- Comprehensive prerequisite validation
- Better error messages with colors
- Validates AWS credentials before proceeding

### 4. **Git/CodeCommit Push** ⚠️ POTENTIAL ISSUE
**Old Script:**
```
REPO_URL="codecommit::${REGION}://aws-serverless-saas-workshop"
git remote add cc $REPO_URL
if [[ $? -ne 0 ]]; then
    echo "Setting url to remote cc"
    git remote set-url cc $REPO_URL
fi
# ... later ...
git push cc $CURRENT_BRANCH:main --force
```

**New Script:**
```
REPO_URL="codecommit::${AWS_REGION}://aws-serverless-saas-workshop"
git remote add cc $REPO_URL 2>/dev/null || git remote set-url cc $REPO_URL
# ... later ...
git remote set-url cc $REPO_URL 2>/dev/null || git remote add cc $REPO_URL
git push cc $CURRENT_BRANCH:main --force
```

**ISSUE:** The new script sets the remote URL twice (once after creating repo, once before push). This is redundant but shouldn't cause issues. However, the `git push` command may hang if:
- Git credential helper is not configured for CodeCommit
- The `codecommit::` URL scheme is not recognized
- AWS CLI credential helper for git is not installed

### 5. **CDK Deployment** ✅ IMPROVED
**Old Script:**
```
cd ../server/TenantPipeline/
npm install && npm run build 
cdk bootstrap  
cdk deploy --require-approval never
```

**New Script:**
```
cd ../server/TenantPipeline/ || exit

print_message "$YELLOW" "  Cleaning previous npm installation for TenantPipeline..."
rm -rf node_modules package-lock.json || true

npm install || {
    print_message "$RED" "Error: npm install failed"
    exit 1
}

npm run build || {
    print_message "$RED" "Error: npm build failed"
    exit 1
}

print_message "$YELLOW" "  Bootstrapping CDK..."
if [[ -n "$AWS_PROFILE" ]]; then
  cdk bootstrap --profile "$AWS_PROFILE" --region "$AWS_REGION" || {
      print_message "$RED" "Error: CDK bootstrap failed"
      exit 1
  }
else
  cdk bootstrap --region "$AWS_REGION" || {
      print_message "$RED" "Error: CDK bootstrap failed"
      exit 1
  }
fi

print_message "$YELLOW" "  Deploying CDK stack..."
if [[ -n "$AWS_PROFILE" ]]; then
  cdk deploy --profile "$AWS_PROFILE" --require-approval never --region "$AWS_REGION" || {
      print_message "$RED" "Error: CDK deploy failed"
      exit 1
  }
else
  cdk deploy --require-approval never --region "$AWS_REGION" || {
      print_message "$RED" "Error: CDK deploy failed"
      exit 1
  }
fi
```

**IMPROVEMENTS:**
- Cleans node_modules before install (prevents stale dependencies)
- Properly passes profile and region to CDK commands
- Better error handling with exit on failure
- More verbose logging

### 6. **SAM Deployment** ✅ IMPROVED
**Old Script:**
```
sam build -t shared-template.yaml
sam deploy --config-file shared-samconfig.toml --region=$REGION --parameter-overrides ...
```

**New Script:**
```
sam build -t shared-template.yaml --use-container || {
    print_message "$RED" "Error: SAM build failed"
    exit 1
}

sam deploy \
    $PROFILE_ARG \
    --config-file shared-samconfig.toml \
    --region "$AWS_REGION" \
    --stack-name "$SHARED_STACK_NAME" \
    --parameter-overrides EventEngineParameter=$IS_RUNNING_IN_EVENT_ENGINE \
    --no-fail-on-empty-changeset || {
    print_message "$RED" "Error: SAM deployment failed"
    exit 1
}
```

**IMPROVEMENTS:**
- Uses `--use-container` for consistent builds
- Properly passes profile argument
- Explicit stack name parameter
- `--no-fail-on-empty-changeset` flag
- Better error handling

### 7. **Client Deployment** ✅ IMPROVED
**Old Script:**
- No cleanup of node_modules before install
- Basic error checking

**New Script:**
```
print_message "$YELLOW" "  Cleaning previous npm installation for Admin UI..."
rm -rf node_modules package-lock.json || true

npm install --legacy-peer-deps || {
    print_message "$RED" "Error: npm install failed for Admin UI"
    exit 1
}
```

**IMPROVEMENTS:**
- Cleans node_modules before each client build
- Better error messages
- Consistent error handling

## ROOT CAUSE OF DEPLOYMENT HANG ✅ IDENTIFIED

The deployment is hanging at "Checking CodeCommit repository..." because:

1. **REGION MISMATCH**: The git remote `cc` is configured with `us-east-1` but the script uses `us-west-2`
   ```
   # Current remote (WRONG):
   cc codecommit::us-east-1://aws-serverless-saas-workshop
   
   # Script expects (CORRECT):
   cc codecommit::us-west-2://aws-serverless-saas-workshop
   ```

2. **Git push hangs** when trying to push to a CodeCommit repository in the wrong region
3. The script does `git remote set-url` but this happens AFTER the repository check, so if the remote already exists with wrong region, it doesn't get updated properly

## SOLUTION ✅

Fix the git remote URL to use the correct region:

```
# Remove the old remote with wrong region
git -C workshop/Lab5 remote remove cc

# The deployment script will recreate it with the correct region (us-west-2)
```

OR manually update the remote URL:

```
git -C workshop/Lab5 remote set-url cc codecommit::us-west-2://aws-serverless-saas-workshop
```

The script logic is actually correct - it does `git remote set-url` before pushing. However, the issue is that the remote was created from a previous deployment attempt with the wrong region, and the script's logic to update it may not be working as expected.

## RECOMMENDATIONS

1. ✅ Keep all the improvements from the new script (profile handling, error handling, validation)
2. ⚠️ Fix the git push issue by either:
   - Installing git-remote-codecommit
   - Using HTTPS URL with credential helper
   - Adding timeout to git push command
3. ✅ Keep the enhanced logging and colored output
4. ✅ Keep the SAM bucket validation and creation logic
5. ✅ Keep the node_modules cleanup before builds
