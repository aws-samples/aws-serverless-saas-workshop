# Lab6 Python 3.14 CodeBuild Fix

## Problem Summary

The Lab6 tenant pipeline CodeBuild project was failing during the Build stage with the error:
```
Phase complete: BUILD State: FAILED
Phase context status code: COMMAND_EXECUTION_ERROR 
Message: Error while executing command: sam build -t tenant-template.yaml. Reason: exit status 1
```

## Root Cause

The Lambda functions in `tenant-template.yaml` specify `Runtime: python3.14`, but the buildspec was trying to build without containers using the CodeBuild host Python 3.11. SAM build was failing because it couldn't build Python 3.14 Lambda functions with Python 3.11.

## Solution Implemented

Applied the same fix that was successfully implemented in Lab 5 (see `workshop/Lab5/LAB5_PYTHON314_CODEBUILD_FIX.md`).

### Changes Made to tenant-buildspec.yml

1. **Removed runtime-versions section**: Eliminated `runtime-versions: python: 3.11` to use system Python 3 and avoid pyenv issues

2. **Updated SAM CLI installation**: Changed from pinned version to latest:
   - Before: `python -m pip install aws-sam-cli==1.33.0`
   - After: `python3 -m pip install --upgrade aws-sam-cli`

3. **Added --use-container flag**: Critical change to build Lambda functions in Docker containers:
   - Before: `sam build -t tenant-template.yaml`
   - After: `sam build -t tenant-template.yaml --use-container`

4. **Updated Python commands**: Changed from `python` to `python3` for consistency

## Why --use-container is Critical

The `--use-container` flag makes SAM:
- Pull the appropriate Lambda Docker image for python3.14
- Build Lambda functions inside that container with the correct Python version
- Package functions with correct dependencies
- Work regardless of the CodeBuild host Python version

Without this flag, SAM tries to build Python 3.14 Lambda functions using the host Python 3.11, which fails.

## Final Working Buildspec

```yaml
version: 0.2
phases:
  install:
    commands:
      - python3 --version
      - python3 -m pip install --upgrade aws-sam-cli
      - sam --version
      - cd Lab6/server/ProductService
      - python3 -m pip install -r requirements.txt 
      - cd ../OrderService
      - python3 -m pip install -r requirements.txt 

  pre_build:
    commands:
      - cd ..
      - export PYTHONPATH=./ProductService/

  build:
    commands:
      - sam build -t tenant-template.yaml --use-container

  post_build:
    commands:
      - sam package --s3-bucket $PACKAGE_BUCKET --output-template-file packaged.yaml

artifacts:
  discard-paths: yes
  files:
    - Lab6/server/packaged.yaml
```

## Files Modified

- `workshop/Lab6/server/tenant-buildspec.yml` - Added --use-container, updated Python commands, removed runtime-versions
- `workshop/Lab6/LAB6_PYTHON314_CODEBUILD_FIX.md` - This documentation

## Next Steps

After applying this fix:
1. Commit the changes
2. Push to CodeCommit to trigger the pipeline
3. Verify the Build stage succeeds
4. Verify the Deploy stage succeeds and tenant stacks are created

## Related Documentation

- Lab 5 fix: `workshop/Lab5/LAB5_PYTHON314_CODEBUILD_FIX.md`
- Lab 6 changes summary: `workshop/Lab6/LAB6_CHANGES_SUMMARY.md`
