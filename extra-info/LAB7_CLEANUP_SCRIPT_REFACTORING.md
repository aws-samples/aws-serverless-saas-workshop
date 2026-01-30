# Lab7 Cleanup Script Refactoring

## Overview

This document describes the refactoring of Lab7's cleanup script to accept the `--stack-name` parameter, making it consistent with all other lab cleanup scripts (Lab1-Lab6).

## Problem Statement

Lab7's cleanup script was the only lab that didn't accept the `--stack-name` parameter. Instead, it only accepted:
- `--main-stack` (default: `serverless-saas-lab7`)
- `--tenant-stack` (default: `stack-pooled-lab7`)
- `--profile`, `--region`, `-y/--yes`

This inconsistency created two issues:

1. **Inconsistent API**: All other labs (Lab1-Lab6) use `--stack-name` as the primary parameter, but Lab7 required different parameters
2. **Test Complexity**: The end-to-end cleanup isolation test had to special-case Lab7, making the test code more complex and harder to maintain

## Solution

### 1. Add `--stack-name` Parameter Support

Lab7's cleanup script now accepts `--stack-name` parameter that automatically sets both main and tenant stack names:

```bash
# New recommended usage (consistent with Lab1-Lab6)
./cleanup.sh --stack-name serverless-saas-lab7 --profile <profile-name>

# Derives:
# - MAIN_STACK="serverless-saas-lab7"
# - TENANT_STACK="stack-pooled-lab7"
```

### 2. Maintain Backward Compatibility

The script still accepts `--main-stack` and `--tenant-stack` parameters for advanced users who need to override the default naming:

```bash
# Advanced usage (overrides --stack-name)
./cleanup.sh --main-stack custom-main --tenant-stack custom-tenant --profile <profile-name>
```

### 3. Parameter Precedence

The parameter precedence is:
1. `--main-stack` and `--tenant-stack` (highest priority - explicit overrides)
2. `--stack-name` (derives both stack names automatically)
3. Default values (lowest priority)

## Implementation Details

### Stack Name Derivation Logic

When `--stack-name` is provided:

```bash
--stack-name)
    # Set both main and tenant stack names based on the provided stack name
    MAIN_STACK=$2
    # Derive tenant stack name: if stack ends with -lab7, tenant is stack-pooled-lab7
    if [[ "$MAIN_STACK" == *"-lab7" ]]; then
        TENANT_STACK="stack-pooled-lab7"
    else
        # For custom stack names, append -tenant suffix
        TENANT_STACK="${MAIN_STACK}-tenant"
    fi
    shift 2
    ;;
```

**Logic**:
- If stack name ends with `-lab7` (e.g., `serverless-saas-lab7`), tenant stack is `stack-pooled-lab7`
- For custom stack names, tenant stack is `<stack-name>-tenant`

### Updated Usage Examples

```bash
# Standard usage (recommended)
./cleanup.sh --stack-name serverless-saas-lab7 --profile serverless-saas-demo

# With non-interactive mode
echo "yes" | ./cleanup.sh --stack-name serverless-saas-lab7 --profile serverless-saas-demo

# Custom stack name
./cleanup.sh --stack-name my-custom-lab7 --profile serverless-saas-demo
# Derives: MAIN_STACK="my-custom-lab7", TENANT_STACK="my-custom-lab7-tenant"

# Advanced: explicit override
./cleanup.sh --main-stack my-main --tenant-stack my-tenant --profile serverless-saas-demo
```

## Test Code Simplification

### Before Refactoring

The test code had a special case for Lab7:

```python
# Lab7 doesn't use --stack-name parameter (uses defaults)
if lab_num == 7:
    args = ["-y"]  # Add non-interactive flag for Lab7
    args.extend(self.profile_args)  # Add profile args
else:
    args = ["--stack-name", f"serverless-saas-lab{lab_num}"]
    args.extend(self.profile_args)  # Add profile args as separate items
```

### After Refactoring

The test code now uses the same pattern for all labs:

```python
# All labs now use the same --stack-name parameter format
args = ["--stack-name", f"serverless-saas-lab{lab_num}"]
args.extend(self.profile_args)  # Add profile args as separate items
```

**Benefits**:
- ✅ Simpler test code (no special cases)
- ✅ Consistent API across all labs
- ✅ Easier to maintain and understand

## Updated Documentation

### Deployment Cleanup Guide

Updated `workshop/extra-info/DEPLOYMENT_CLEANUP_MANUAL.md` and `.kiro/steering/deployment-cleanup-guide.md`:

```bash
# Old command (still works but not recommended)
./cleanup.sh --profile <your-profile-name>

# New recommended command (consistent with other labs)
./cleanup.sh --stack-name serverless-saas-lab7 --profile <your-profile-name>
```

### Lab7 README

Updated `workshop/Lab7/README.md` to document the new `--stack-name` parameter as the recommended usage.

## Migration Guide

### For Users

**No action required!** The script is backward compatible:

- Old command: `./cleanup.sh --profile <profile>` → Still works (uses defaults)
- New command: `./cleanup.sh --stack-name serverless-saas-lab7 --profile <profile>` → Recommended

### For Developers

If you have scripts or automation that call Lab7's cleanup script:

1. **Recommended**: Update to use `--stack-name` parameter for consistency
2. **Optional**: Keep using `--main-stack` and `--tenant-stack` if you need explicit control

## Testing

### Manual Testing

```bash
# Test 1: Standard usage with --stack-name
cd workshop/Lab7/scripts
./cleanup.sh --stack-name serverless-saas-lab7 --profile serverless-saas-demo -y

# Test 2: Backward compatibility (no --stack-name)
./cleanup.sh --profile serverless-saas-demo -y

# Test 3: Advanced usage with explicit overrides
./cleanup.sh --main-stack custom-main --tenant-stack custom-tenant --profile serverless-saas-demo -y
```

### Automated Testing

The end-to-end cleanup isolation test (`workshop/tests/test_end_to_end_cleanup_isolation.py`) now tests Lab7 with the same pattern as other labs:

```bash
# Run the test
cd workshop/tests
pytest test_end_to_end_cleanup_isolation.py -v --real-aws --aws-profile=serverless-saas-demo
```

## Benefits

1. **Consistency**: All labs (Lab1-Lab7) now use the same `--stack-name` parameter
2. **Simplicity**: Test code is simpler without special cases
3. **Maintainability**: Easier to understand and maintain
4. **Backward Compatibility**: Old commands still work
5. **Flexibility**: Advanced users can still use explicit overrides

## Related Files

### Modified Files

1. `workshop/Lab7/scripts/cleanup.sh` - Added `--stack-name` parameter support
2. `workshop/tests/test_end_to_end_cleanup_isolation.py` - Removed Lab7 special case
3. `.kiro/steering/deployment-cleanup-guide.md` - Updated Lab7 cleanup command
4. `workshop/extra-info/DEPLOYMENT_CLEANUP_MANUAL.md` - Updated Lab7 documentation

### New Files

1. `workshop/extra-info/LAB7_CLEANUP_SCRIPT_REFACTORING.md` - This document

## Conclusion

This refactoring makes Lab7's cleanup script consistent with all other labs, simplifies test code, and maintains backward compatibility. Users can now use the same `--stack-name` parameter pattern across all labs, making the workshop easier to use and maintain.

## Next Steps

1. ✅ Refactor Lab7 cleanup script to accept `--stack-name`
2. ✅ Simplify test code to remove Lab7 special case
3. ✅ Update documentation
4. ⏳ Run end-to-end test to validate the changes
5. ⏳ Update Task 13 status to reflect completion

## References

- Task 13 (Step 12): End-to-End Cleanup Isolation Test
- `.kiro/specs/lab-cleanup-isolation-all-labs/tasks.md`
- `workshop/tests/test_end_to_end_cleanup_isolation.py`
- `workshop/Lab7/scripts/cleanup.sh`
