# Lab7 SAM Bucket Cleanup Fix

## Problem Statement

Lab7's cleanup script was not properly cleaning up its SAM bootstrap buckets (`sam-bootstrap-bucket-lab7` and `sam-bootstrap-bucket-tenant-lab7`), leaving them as orphaned resources that had to be cleaned up by the global cleanup script.

## Root Cause

The Lab7 cleanup script had a **path resolution bug** that prevented it from finding the `samconfig.toml` files:

### Original Code (Broken)
```bash
# Get the bucket name from samconfig.toml
SAM_BUCKET=$(grep s3_bucket ../samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")
```

### The Problem

1. **Missing `SCRIPT_DIR` variable**: Lab7's cleanup script did not use `${BASH_SOURCE[0]}` to determine its own location
2. **Relative path assumption**: The script used `../samconfig.toml` which assumes the script is run from the `scripts/` directory
3. **Actual execution context**: The script is executed from the workspace root as `workshop/Lab7/scripts/cleanup.sh`
4. **Path resolution failure**: When run from workspace root, `../samconfig.toml` tries to access a file in the parent of the workspace root (which doesn't exist)

### Why Other Labs Didn't Have This Issue

Other labs (Lab1-Lab6) have a different directory structure:
- Lab1-Lab6: `workshop/LabN/server/samconfig.toml` (samconfig in `server/` subdirectory)
- Lab7: `workshop/Lab7/samconfig.toml` (samconfig in lab root directory)

Lab1-Lab6 scripts use `../server/samconfig.toml` which works because:
- Script location: `workshop/LabN/scripts/cleanup.sh`
- Relative path: `../server/samconfig.toml` → `workshop/LabN/server/samconfig.toml` ✓

But Lab7's structure is different, and the script didn't account for this.

## The Fix

### Added Script Location Detection

```bash
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"  # Parent directory of scripts/ is the lab root
```

This ensures the script knows its own location regardless of where it's executed from.

### Updated SAM Bucket Cleanup

```bash
# Get the bucket name from samconfig.toml (in lab root directory)
SAM_BUCKET=$(grep s3_bucket "$LAB_DIR/samconfig.toml" 2>/dev/null | cut -d'=' -f2 | cut -d '"' -f2 || echo "")

# Get the bucket name from tenant-samconfig.toml (in lab root directory)
TENANT_SAM_BUCKET=$(grep s3_bucket "$LAB_DIR/tenant-samconfig.toml" 2>/dev/null | cut -d'=' -f2 | cut -d '"' -f2 || echo "")
```

Now the script uses absolute paths based on its own location:
- `$LAB_DIR/samconfig.toml` → `/full/path/to/workshop/Lab7/samconfig.toml` ✓
- `$LAB_DIR/tenant-samconfig.toml` → `/full/path/to/workshop/Lab7/tenant-samconfig.toml` ✓

## Verification

### Before Fix
```bash
$ workshop/Lab7/scripts/cleanup.sh --profile serverless-saas-demo
...
Step 9: Cleaning up SAM bootstrap buckets from samconfig.toml files
  No SAM bucket found in samconfig.toml
  No SAM bucket found in tenant-samconfig.toml
```

Result: SAM buckets left as orphaned resources

### After Fix
```bash
$ workshop/Lab7/scripts/cleanup.sh --profile serverless-saas-demo
...
Step 9: Cleaning up SAM bootstrap buckets from samconfig.toml files
  Found SAM bucket in samconfig.toml: sam-bootstrap-bucket-lab7
  Emptying bucket: sam-bootstrap-bucket-lab7
  Deleting bucket: sam-bootstrap-bucket-lab7
  SAM bootstrap bucket deleted
  Found SAM bucket in tenant-samconfig.toml: sam-bootstrap-bucket-tenant-lab7
  Emptying bucket: sam-bootstrap-bucket-tenant-lab7
  Deleting bucket: sam-bootstrap-bucket-tenant-lab7
  Tenant SAM bootstrap bucket deleted
```

Result: SAM buckets properly cleaned up by Lab7 script

## Key Lessons

1. **Always use `${BASH_SOURCE[0]}`**: Scripts must determine their own location to build absolute paths
2. **Never assume working directory**: Scripts can be executed from anywhere
3. **Test from different locations**: Run scripts from workspace root, lab directory, and scripts directory
4. **Follow the steering guide**: The deployment-cleanup-guide explicitly warns about this issue

## Related Documentation

- `workshop/extra-info/DEPLOYMENT_CLEANUP_MANUAL.md` - Deployment and cleanup procedures
- `.kiro/steering/deployment-cleanup-guide.md` - Script execution rules and best practices
- `workshop/extra-info/CLEANUP_ISOLATION.md` - Lab cleanup isolation strategy

## Impact

- **Before**: Lab7 left 2 orphaned SAM buckets that required global cleanup
- **After**: Lab7 properly cleans up all its resources, including SAM buckets
- **Benefit**: Complete lab isolation - each lab is fully responsible for its own cleanup

## Testing

To test the fix:

1. Deploy Lab7:
   ```bash
   cd workshop/Lab7/scripts
   ./deployment.sh --profile serverless-saas-demo
   ```

2. Verify SAM buckets exist:
   ```bash
   aws s3api list-buckets --query 'Buckets[?contains(Name, `lab7`)].Name' --output table --profile serverless-saas-demo
   ```

3. Run cleanup:
   ```bash
   echo "yes" | workshop/Lab7/scripts/cleanup.sh --profile serverless-saas-demo
   ```

4. Verify SAM buckets are deleted:
   ```bash
   aws s3api list-buckets --query 'Buckets[?contains(Name, `lab7`)].Name' --output table --profile serverless-saas-demo
   ```

Expected result: No Lab7 buckets remain

## Date

January 28, 2026
