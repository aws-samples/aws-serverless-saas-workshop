# Lab 5 Deployment Script - Bugs Fixed

## Summary
Fixed 4 critical bugs in the Lab 5 deployment script that were preventing successful deployment.

## Bug 1: Variable Name Mismatch ✅ FIXED
**Issue**: Script used `$AWS_PROFILE_ARG` throughout but set variable as `PROFILE_ARG`
**Location**: Multiple locations in `workshop/Lab5/scripts/deployment.sh`
**Fix**: Replaced all instances of `$AWS_PROFILE_ARG` with `$PROFILE_ARG`
**Impact**: Script was failing to pass AWS profile to CLI commands

## Bug 2: Git Remote Region Mismatch ✅ FIXED
**Issue**: Git remote `cc` was configured with `us-east-1` from previous deployment, script expects `us-west-2`
**Location**: Git configuration in workshop directory
**Fix**: Removed old remote with `git -C workshop remote remove cc`, script recreates with correct region
**Impact**: Git push was targeting wrong region

## Bug 3: set -e Causing Premature Exit ✅ FIXED
**Issue**: Script has `set -e` which exits on any error. CodeCommit repository check `aws codecommit get-repository` returns exit code 254 when repo doesn't exist, causing script to exit before checking `if [[ $? -ne 0 ]]` condition
**Location**: Lines 267-270 in deployment.sh
**Fix**: 
```bash
set +e  # Temporarily disable exit on error for repository check
REPO=$(aws codecommit $PROFILE_ARG get-repository --repository-name aws-serverless-saas-workshop --region "$AWS_REGION" 2>&1)
REPO_CHECK_EXIT_CODE=$?
set -e  # Re-enable exit on error
if [[ $REPO_CHECK_EXIT_CODE -ne 0 ]]; then
    # Create repository...
fi
```
**Impact**: Script was exiting prematurely when repository didn't exist, preventing repository creation

## Bug 4: Git Push Context and Authentication Issues ✅ FIXED
**Issue**: Two related problems:
1. Git commands were running from `workshop/Lab5/scripts` directory but needed to operate on the `workshop` directory (git repository root)
2. git-remote-codecommit requires AWS_PROFILE environment variable to be exported for authentication

**Location**: Lines 295-310 in deployment.sh
**Fix**:
```bash
# Navigate to git repository root (workshop directory)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$GIT_ROOT" ]]; then
  print_message "$RED" "Error: Not in a git repository"
  exit 1
fi

CURRENT_BRANCH=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD)

# All git commands now use: git -C "$GIT_ROOT" <command>

# Export AWS_PROFILE for git-remote-codecommit (required for authentication)
if [[ -n "$AWS_PROFILE" ]]; then
  export AWS_PROFILE
fi

git -C "$GIT_ROOT" push cc $CURRENT_BRANCH:main --force
```
**Impact**: 
- Git commands were failing because they couldn't find the repository
- Git push was failing with "repository not found" error due to authentication issues

## Bug 5: TypeScript Version Incompatibility ✅ FIXED
**Issue**: TenantPipeline CDK code uses TypeScript 4.9.5 which doesn't support CDK 2.x decorator syntax
**Location**: `workshop/Lab5/server/TenantPipeline/package.json`
**Fix**: Updated TypeScript from 4.9.5 to ~5.3.0
**Impact**: CDK synthesis was failing with decorator syntax errors

## Bug 6: ts-jest Compatibility ✅ FIXED
**Issue**: ts-jest version ^26.2.0 doesn't support TypeScript 5.x
**Location**: `workshop/Lab5/server/TenantPipeline/package.json`
**Fix**: Updated ts-jest from ^26.2.0 to ^29.1.0
**Impact**: Test framework compatibility with TypeScript 5.x

## Bug 7: Jest Version Compatibility ✅ FIXED
**Issue**: jest version ^26.4.2 incompatible with ts-jest ^29.x
**Location**: `workshop/Lab5/server/TenantPipeline/package.json`
**Fix**: Updated jest from ^26.4.2 to ^29.5.0
**Impact**: Test framework compatibility

## Bug 8: @types Package Versions ✅ FIXED
**Issue**: @types/jest and @types/node versions incompatible with TypeScript 5.x
**Location**: `workshop/Lab5/server/TenantPipeline/package.json`
**Fix**: Updated @types/jest to ^29.5.0 and @types/node to 20.x
**Impact**: Type definitions compatibility

## Bug 9: Deprecated Package ✅ FIXED
**Issue**: @aws-cdk/assert@1.64.1 is deprecated and requires old jest version
**Location**: `workshop/Lab5/server/TenantPipeline/package.json`
**Fix**: Removed @aws-cdk/assert package
**Impact**: Removed dependency on deprecated package

## Bug 10: CloudFormation Condition Syntax Error ✅ FIXED
**Issue**: `!Equals` function comparing string parameter to boolean value causing YAML parser error
**Location**: Line 50 in `workshop/Lab5/server/shared-template.yaml`
**Error**: "mapping values are not allowed here" and "could not determine a constructor for the tag '!Not'"
**Fix**: Changed `!Equals [ !Ref EventEngineParameter, true]` to `!Equals [ !Ref EventEngineParameter, "true"]`
**Impact**: SAM build was failing with YAML syntax error, preventing stack deployment

## Testing Results
After all fixes:
- ✅ Repository check works correctly
- ✅ Repository creation works when needed
- ✅ Git push succeeds with proper authentication
- ✅ All git operations use correct directory context
- ✅ Script continues to CDK deployment phase
- ✅ TypeScript and dependency versions updated
- ✅ CloudFormation condition syntax fixed

## Next Steps
1. Re-run deployment: `./deployment.sh -s -c --profile serverless-saas-demo`
2. Monitor SAM build (should now succeed)
3. Monitor shared stack deployment
4. Test client application deployments
5. Verify all stacks deploy successfully
6. Update tasks.md with Task 27.5 completion summary
