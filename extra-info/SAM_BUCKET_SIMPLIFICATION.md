# SAM Bootstrap Bucket Simplification

## Summary

Simplified the SAM bootstrap bucket management by using explicit bucket names in `samconfig.toml` files instead of generating them dynamically during deployment.

## Changes Made

### 1. Updated samconfig.toml Files

**Lab1** (`workshop/Lab1/server/samconfig.toml`):
- Changed `s3_bucket = ""` to `s3_bucket = "sam-bootstrap-bucket-lab1"`

**Lab2** (`workshop/Lab2/server/samconfig.toml`):
- Changed `s3_bucket = ""` to `s3_bucket = "sam-bootstrap-bucket-lab2"`

### 2. Simplified Deployment Scripts

**Lab1** (`workshop/Lab1/scripts/deployment.sh`):
- Removed dynamic bucket name generation logic
- Now simply reads bucket name from samconfig.toml
- Exits with error if bucket name is empty

**Lab2** (`workshop/Lab2/scripts/deployment.sh`):
- Removed dynamic bucket name generation logic
- Removed samconfig.toml update logic
- Now simply reads bucket name from samconfig.toml
- Exits with error if bucket name is empty

### 3. Cleanup Scripts (Already Working)

Both Lab1 and Lab2 cleanup scripts already had the correct logic to:
1. Read bucket name from samconfig.toml
2. Empty the bucket
3. Delete the bucket

## Benefits

1. **Predictability**: Bucket names are known in advance
2. **Simplicity**: No dynamic generation or file updates during deployment
3. **Reliability**: Cleanup scripts can always find the bucket name
4. **Maintainability**: Easier to understand and debug
5. **Consistency**: Same approach across all labs

## Bucket Naming Convention

- Lab1: `sam-bootstrap-bucket-lab1`
- Lab2: `sam-bootstrap-bucket-lab2`
- Lab3+: Follow same pattern (e.g., `sam-bootstrap-bucket-lab3`)

## Testing

- ✅ Lab2 cleanup successfully deleted old dynamically-named bucket
- ✅ samconfig.toml files updated with explicit names
- ✅ Deployment scripts simplified
- Ready for testing with new deployment

## Old Bucket Cleanup

Manually cleaned up the old dynamically-generated bucket:
- `sam-bootstrap-bucket-lab2-ce6714d4-6e83-43cd-ab2c-3e237126b974` (deleted)
