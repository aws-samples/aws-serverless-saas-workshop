# Deployment and Cleanup Updates Summary

## Changes Made

### 1. Removed `--use-container` Flag
**Reason**: Docker is not required for this workshop deployment.

**Files Updated**:
- `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
- `workshop/QUICK_REFERENCE.md`
- `workshop/.kiro/steering/deployment-cleanup-guide.md`
- `workshop/Lab1/server/README.md`

**Before**:
```
sam build -t template.yaml --use-container
```

**After**:
```
sam build -t template.yaml
```

---

### 2. Added AWS Profile `serverless-saas-demo`
**Reason**: Standardize AWS profile usage across all commands.

**Profile Name**: `serverless-saas-demo`

**Files Updated**:
- `workshop/DEPLOYMENT_CLEANUP_MANUAL.md` (all AWS CLI commands)
- `workshop/QUICK_REFERENCE.md` (all AWS CLI commands)
- `workshop/scripts/cleanup.sh` (added profile export)
- `workshop/.kiro/steering/deployment-cleanup-guide.md`
- `workshop/Lab1/server/README.md`

**Example Changes**:
```
# Before
aws cloudformation describe-stacks --stack-name serverless-saas-workshop-lab1

# After
aws cloudformation describe-stacks \
  --stack-name serverless-saas-workshop-lab1 \
  --profile serverless-saas-demo
```

**Cleanup Script**:
```
# Removed export, added profile to each command
# Example:
aws cloudformation delete-stack --stack-name "$1" --profile serverless-saas-demo
```

**Deployment Scripts** (Labs 2, 3, 5, 6):
```
# Removed export, kept AWS_PROFILE variable with default
AWS_PROFILE="serverless-saas-demo"

# Added profile to each AWS CLI command
aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$AWS_PROFILE"
```

---

### 3. Changed Cleanup Script to Automatic Mode and Added Profile Flag
**Reason**: Streamline cleanup process and use profile flag instead of export.

**File Updated**: `workshop/scripts/cleanup.sh`

**Changes**:
- Default mode is now **automatic** (no prompts)
- Added `-i` flag for **interactive mode** (with prompts)
- Changed `skip_flag` logic to default to `true`
- **Removed `export AWS_PROFILE`** and added `--profile serverless-saas-demo` to each AWS CLI command

**Before**:
```
# Default: Interactive mode with prompts
./cleanup.sh

# Skip prompts
./cleanup.sh -s
```

**After**:
```
# Default: Automatic mode (no prompts)
./cleanup.sh

# Interactive mode with prompts
./cleanup.sh -i
```

**Implementation**:
```
skip_flag='true'
interactive_flag=''
while getopts 'i' flag; do
    case "${flag}" in
    i) 
        skip_flag=''
        interactive_flag='true'
        ;;
    *) error "Unexpected option ${flag}!" && exit 1 ;;
    esac
done
```

---

## Updated Documentation

### Main Deployment Manual
**File**: `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`

**Key Updates**:
1. Prerequisites section now emphasizes `serverless-saas-demo` profile
2. All AWS CLI commands include `--profile serverless-saas-demo`
3. Removed Docker requirement
4. Updated cleanup usage to show automatic mode as default
5. Updated all Lab deployment commands to remove `--use-container`

### Quick Reference Card
**File**: `workshop/QUICK_REFERENCE.md`

**Key Updates**:
1. Added profile verification command
2. Updated all one-line deploy commands
3. Updated cleanup commands to show new flags
4. Removed Docker from prerequisites
5. Added profile configuration to support commands

### Steering Guide
**File**: `workshop/.kiro/steering/deployment-cleanup-guide.md`

**Key Updates**:
1. Updated all command examples
2. Added profile requirement to important notes
3. Updated cleanup behavior description

### Lab1 README
**File**: `workshop/Lab1/server/README.md`

**Key Updates**:
1. Reformatted for clarity
2. Added profile to all commands
3. Removed `--use-container` flag
4. Separated Event Engine and standard deployment instructions

---

## Verification Commands

### Verify AWS Profile
```
aws sts get-caller-identity --profile serverless-saas-demo
```

### Test Cleanup Script (Dry Run)
```
# Interactive mode to see what would be deleted
cd workshop/scripts
./cleanup.sh -i
# Press 'n' for each prompt to skip deletion
```

### Deploy Lab1 with New Commands
```
cd workshop/Lab1/server
sam build -t template.yaml
sam deploy --config-file samconfig.toml --profile serverless-saas-demo
```

---

## Migration Guide for Existing Users

### If You Have Existing Deployments

1. **Configure the new profile**:
   ```
   aws configure --profile serverless-saas-demo
   ```

2. **Verify profile works**:
   ```
   aws sts get-caller-identity --profile serverless-saas-demo
   ```

3. **Use cleanup script to remove old resources**:
   ```
   cd workshop/scripts
   ./cleanup.sh
   # Runs automatically with new profile
   ```

4. **Redeploy with new commands**:
   ```
   cd workshop/Lab1/server
   sam build -t template.yaml
   sam deploy --config-file samconfig.toml --profile serverless-saas-demo
   ```

### If You're Starting Fresh

1. **Configure AWS profile**:
   ```
   aws configure --profile serverless-saas-demo
   ```

2. **Follow deployment manual**:
   - Read: `workshop/DEPLOYMENT_CLEANUP_MANUAL.md`
   - Quick ref: `workshop/QUICK_REFERENCE.md`

3. **Deploy any lab**:
   - All commands now use `--profile serverless-saas-demo`
   - No Docker required
   - Cleanup runs automatically

---

## Benefits of These Changes

### 1. Simplified Deployment
- No Docker dependency reduces setup complexity
- Faster builds without container overhead
- Fewer potential failure points

### 2. Consistent Profile Usage
- All commands use the same profile
- Easier to manage multiple AWS accounts
- Clear separation from other AWS projects

### 3. Streamlined Cleanup
- Automatic mode saves time
- No need to confirm each deletion
- Interactive mode still available when needed
- Consistent behavior across all labs

### 4. Better Documentation
- Clear command examples
- Consistent formatting
- Easy to copy-paste commands
- Comprehensive troubleshooting

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `workshop/DEPLOYMENT_CLEANUP_MANUAL.md` | Removed `--use-container`, added profile to all commands, updated cleanup usage |
| `workshop/QUICK_REFERENCE.md` | Updated all commands with profile, removed Docker, updated cleanup flags |
| `workshop/scripts/cleanup.sh` | Changed to automatic mode, added profile export, inverted flag logic |
| `workshop/.kiro/steering/deployment-cleanup-guide.md` | Updated all examples, added profile requirement |
| `workshop/Lab1/server/README.md` | Reformatted, added profile, removed `--use-container` |

---

## Testing Checklist

- [ ] Verify AWS profile is configured: `aws sts get-caller-identity --profile serverless-saas-demo`
- [ ] Test Lab1 deployment with new commands
- [ ] Verify CloudWatch log groups are created with 60-day retention
- [ ] Test cleanup script in automatic mode
- [ ] Test cleanup script in interactive mode with `-i` flag
- [ ] Verify all resources are deleted after cleanup
- [ ] Check documentation for consistency
- [ ] Verify steering file loads correctly

---

## Rollback Instructions

If you need to revert these changes:

1. **Restore cleanup script**:
   ```
   git checkout HEAD -- workshop/scripts/cleanup.sh
   ```

2. **Restore documentation**:
   ```
   git checkout HEAD -- workshop/DEPLOYMENT_CLEANUP_MANUAL.md
   git checkout HEAD -- workshop/QUICK_REFERENCE.md
   ```

3. **Use old commands**:
   ```
   sam build --use-container
   sam deploy --config-file samconfig.toml
   # Without --profile flag
   ```


---

## Update: Profile Flag Implementation (January 2026)

### Changed from `export` to `--profile` Flag

**Reason**: Use explicit profile flags on each AWS CLI command instead of environment variable export for better clarity and control.

**Files Updated**:
- `workshop/scripts/cleanup.sh`
- `workshop/Lab2/scripts/deployment.sh`
- `workshop/Lab3/scripts/deployment.sh`
- `workshop/Lab5/scripts/deployment.sh`
- `workshop/Lab6/scripts/deployment.sh`

**Changes Made**:

1. **Cleanup Script**:
   - Removed: `export AWS_PROFILE=serverless-saas-demo`
   - Added: `--profile serverless-saas-demo` to every AWS CLI command
   - Example: `aws cloudformation delete-stack --stack-name "$1" --profile serverless-saas-demo`

2. **Deployment Scripts**:
   - Removed: `export AWS_PROFILE="serverless-saas-demo"`
   - Kept: `AWS_PROFILE="serverless-saas-demo"` as a variable (default value)
   - Added: `--profile "$AWS_PROFILE"` to every AWS CLI command
   - Example: `aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$AWS_PROFILE"`

**Benefits**:
- Each command explicitly shows which profile is being used
- No reliance on environment variables that could be overridden
- Easier to debug which profile a specific command uses
- Consistent with AWS CLI best practices
- User can still override by changing the `AWS_PROFILE` variable at the top of deployment scripts

**Before**:
```
export AWS_PROFILE="serverless-saas-demo"
aws cloudformation describe-stacks --stack-name my-stack
```

**After**:
```
AWS_PROFILE="serverless-saas-demo"
aws cloudformation describe-stacks --stack-name my-stack --profile "$AWS_PROFILE"
```
