# AWS Profile Flag Implementation Summary

## Overview
All deployment and cleanup scripts have been updated to accept AWS profile as a command-line parameter instead of using hardcoded or exported environment variables.

## Changes Made

### 1. Cleanup Script (`workshop/scripts/cleanup.sh`)
**Changes:**
- Added `--profile` parameter parsing using `getopts` with long option support
- Made `--profile` a required parameter
- Removed hardcoded `AWS_PROFILE` default value
- All AWS CLI commands use `--profile "$AWS_PROFILE"` flag
- Added validation to ensure profile is provided

**Usage:**
```bash
# Required profile parameter
./cleanup.sh --profile serverless-saas-demo

# With interactive mode
./cleanup.sh --profile serverless-saas-demo -i
```

### 2. Lab2 Deployment Script (`workshop/Lab2/scripts/deployment.sh`)
**Status:** ✅ Already implemented correctly
- Has `--profile` parameter with validation
- Uses `--profile "$AWS_PROFILE"` on all AWS CLI commands
- No hardcoded defaults

### 3. Lab3 Deployment Script (`workshop/Lab3/scripts/deployment.sh`)
**Changes:**
- Removed hardcoded `AWS_PROFILE="serverless-saas-demo"` default
- Added `--profile` parameter parsing
- Added profile validation (required parameter)
- Updated credential validation to use `--profile "$AWS_PROFILE"`
- Updated help text to include `--profile` parameter

**Usage:**
```bash
./deployment.sh -s -c --email admin@example.com --profile serverless-saas-demo
```

### 4. Lab5 Deployment Script (`workshop/Lab5/scripts/deployment.sh`)
**Changes:**
- Removed hardcoded `AWS_PROFILE="serverless-saas-demo"` default
- Added `--profile` parameter parsing
- Added profile validation (required parameter)
- Updated credential validation to use `--profile "$AWS_PROFILE"`
- Updated help text to include `--profile` parameter

**Usage:**
```bash
./deployment.sh -s -c --profile serverless-saas-demo
```

### 5. Lab6 Deployment Script (`workshop/Lab6/scripts/deployment.sh`)
**Changes:**
- Removed hardcoded `AWS_PROFILE="serverless-saas-demo"` default
- Added `--profile` parameter parsing
- Added profile validation (required parameter)
- Added proper usage function with examples
- All AWS CLI commands already use `--profile "$AWS_PROFILE"`

**Usage:**
```bash
./deployment.sh -s -c --profile serverless-saas-demo
```

### 6. Steering Document (`workshop/.kiro/steering/deployment-cleanup-guide.md`)
**Changes:**
- Updated all command examples to include `--profile serverless-saas-demo`
- Added emphasis that `--profile` is REQUIRED for all commands
- Updated "Important Notes" section to clarify profile usage
- Maintained that documentation always uses `serverless-saas-demo` as the example profile

## Implementation Pattern

All scripts now follow this consistent pattern:

1. **No default profile value** - Variable initialized as empty string
2. **Required parameter** - Scripts exit with error if `--profile` not provided
3. **Validation** - Profile is validated before any AWS operations
4. **Consistent usage** - All AWS CLI commands use `--profile "$AWS_PROFILE"`
5. **Clear help text** - Usage examples show `--profile` parameter

## Benefits

1. **Flexibility** - Scripts can work with any AWS profile
2. **No environment pollution** - No `export AWS_PROFILE` needed
3. **Explicit configuration** - Profile must be specified on command line
4. **Documentation clarity** - All examples show `--profile serverless-saas-demo`
5. **Consistency** - Same pattern across all scripts

## Testing Checklist

- [ ] Lab2 deployment with `--profile` parameter
- [ ] Lab3 deployment with `--profile` parameter
- [ ] Lab5 deployment with `--profile` parameter
- [ ] Lab6 deployment with `--profile` parameter
- [ ] Cleanup script with `--profile` parameter
- [ ] Cleanup script with `--profile` and `-i` flags
- [ ] Error handling when `--profile` is missing
- [ ] Verify no `export AWS_PROFILE` statements remain

## Migration Notes

**Before:**
```bash
export AWS_PROFILE=serverless-saas-demo
./deployment.sh -s -c
```

**After:**
```bash
./deployment.sh -s -c --profile serverless-saas-demo
```

## Files Modified

1. `workshop/scripts/cleanup.sh`
2. `workshop/Lab3/scripts/deployment.sh`
3. `workshop/Lab5/scripts/deployment.sh`
4. `workshop/Lab6/scripts/deployment.sh`
5. `workshop/.kiro/steering/deployment-cleanup-guide.md`

## Files Already Correct

1. `workshop/Lab2/scripts/deployment.sh` - Already implemented correctly

## Files Not Modified (No deployment scripts)

1. `workshop/Lab1/server/` - Uses SAM CLI directly
2. `workshop/Lab4/scripts/` - (Not reviewed in this session)
3. `workshop/Lab7/` - Uses SAM CLI directly
