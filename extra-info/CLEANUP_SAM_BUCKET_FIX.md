# Cleanup Script SAM Bootstrap Bucket Fix

## Problem

Lab cleanup scripts were deleting entire SAM bootstrap buckets, which caused issues when multiple labs shared the same bucket. For example, Lab1 cleanup would delete Lab2's deployment artifacts from the shared SAM bootstrap bucket.

## Solution Evolution

### Previous Approach (ABANDONED)
Initially, we updated cleanup scripts to only remove lab-specific artifacts (e.g., `serverless-saas-lab1/` folder) instead of deleting the entire bucket. However, this approach was not ideal because:
- Labs were still sharing SAM buckets
- Cleanup logic was complex (searching for buckets, checking for artifacts)
- Labs were not truly independent

### Current Approach (IMPLEMENTED)
Each lab is now self-contained with its own SAM bootstrap bucket:
- **Deploy**: Creates/uses the bucket specified in its own `samconfig.toml` (simple logic - no searching for existing buckets)
- **Cleanup**: Deletes the entire bucket specified in its own `samconfig.toml`
- This makes each lab independent and manages its own SAM bucket

## Implementation Pattern

### For Labs with Single samconfig.toml (Lab1, Lab2, Lab7)

```
# Clean up SAM bootstrap bucket from samconfig.toml
print_message "$YELLOW" "Cleaning up SAM bootstrap bucket from samconfig.toml..."

# Get the bucket name from samconfig.toml
SAM_BUCKET=$(grep s3_bucket ../server/samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found SAM bucket in samconfig.toml: $SAM_BUCKET"
    if aws s3 ls "s3://$SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $SAM_BUCKET"
        aws s3 rm "s3://$SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $SAM_BUCKET"
        aws s3api delete-bucket --bucket $SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No SAM bucket found in samconfig.toml"
fi
```

### For Labs with Multiple samconfig.toml Files (Lab3, Lab4)

These labs have both `shared-samconfig.toml` and `tenant-samconfig.toml`, so they clean up both buckets:

```
# Step 5.5: Clean up SAM bootstrap buckets from samconfig.toml files
print_message "$YELLOW" "Step 5.5: Cleaning up SAM bootstrap buckets from samconfig.toml files..."

PROFILE_ARG=$(get_profile_arg)

# Clean up shared stack SAM bucket
SHARED_SAM_BUCKET=$(grep s3_bucket ../server/shared-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$SHARED_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found shared SAM bucket in shared-samconfig.toml: $SHARED_SAM_BUCKET"
    if aws s3 ls "s3://$SHARED_SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $SHARED_SAM_BUCKET"
        aws s3 rm "s3://$SHARED_SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $SHARED_SAM_BUCKET"
        aws s3api delete-bucket --bucket $SHARED_SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  Shared SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  Shared SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No shared SAM bucket found in shared-samconfig.toml"
fi

# Clean up tenant stack SAM bucket
TENANT_SAM_BUCKET=$(grep s3_bucket ../server/tenant-samconfig.toml 2>/dev/null | cut -d'=' -f2 | cut -d \" -f2 || echo "")

if [ -n "$TENANT_SAM_BUCKET" ]; then
    print_message "$YELLOW" "  Found tenant SAM bucket in tenant-samconfig.toml: $TENANT_SAM_BUCKET"
    if aws s3 ls "s3://$TENANT_SAM_BUCKET" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Emptying bucket: $TENANT_SAM_BUCKET"
        aws s3 rm "s3://$TENANT_SAM_BUCKET" --recursive $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$YELLOW" "  Deleting bucket: $TENANT_SAM_BUCKET"
        aws s3api delete-bucket --bucket $TENANT_SAM_BUCKET $PROFILE_ARG --region "$AWS_REGION" 2>/dev/null || true
        print_message "$GREEN" "  Tenant SAM bootstrap bucket deleted"
    else
        print_message "$YELLOW" "  Tenant SAM bucket not found or already deleted"
    fi
else
    print_message "$YELLOW" "  No tenant SAM bucket found in tenant-samconfig.toml"
fi

print_message "$GREEN" "SAM bootstrap bucket cleanup complete"
```

## Deployment Pattern

Deployment scripts also follow the simple pattern of creating the bucket from samconfig.toml if it doesn't exist:

```
# Get or create SAM S3 bucket from samconfig.toml
DEFAULT_SAM_S3_BUCKET=$(grep s3_bucket samconfig.toml | cut -d'=' -f2 | cut -d \" -f2 2>/dev/null || echo "")

if [[ -n "$DEFAULT_SAM_S3_BUCKET" ]]; then
    print_message "$YELLOW" "  Checking SAM deployment bucket: $DEFAULT_SAM_S3_BUCKET"
    if ! aws s3 ls "s3://${DEFAULT_SAM_S3_BUCKET}" $PROFILE_ARG --region "$AWS_REGION" &> /dev/null; then
        print_message "$YELLOW" "  Bucket does not exist, creating: $DEFAULT_SAM_S3_BUCKET"
        aws s3 mb "s3://${DEFAULT_SAM_S3_BUCKET}" $PROFILE_ARG --region "$AWS_REGION"
        aws s3api put-bucket-encryption \
            $PROFILE_ARG \
            --bucket "$DEFAULT_SAM_S3_BUCKET" \
            --region "$AWS_REGION" \
            --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
        print_message "$GREEN" "  ✓ Created SAM deployment bucket: $DEFAULT_SAM_S3_BUCKET"
    else
        print_message "$GREEN" "  ✓ SAM deployment bucket exists: $DEFAULT_SAM_S3_BUCKET"
    fi
fi
```

## SAM Bootstrap Bucket Status by Lab

- ✅ **Lab 1**: Deployment and cleanup updated - generates bucket with "lab1" in name, deletes entire bucket from `samconfig.toml`
- ✅ **Lab 2**: Deployment and cleanup updated - generates bucket with "lab2" in name, deletes entire bucket from `samconfig.toml`
- ✅ **Lab 3**: Deployment and cleanup updated - generates buckets with "lab3-shared" and "lab3-tenant" in names, deletes both buckets from `shared-samconfig.toml` and `tenant-samconfig.toml`
- ✅ **Lab 4**: Deployment and cleanup updated - generates buckets with "lab4-shared" and "lab4-tenant" in names, deletes both buckets from `shared-samconfig.toml` and `tenant-samconfig.toml`
- ✅ **Lab 5**: Already lab-specific - only targets lab5 buckets
- ✅ **Lab 6**: Already lab-specific - only targets lab6 buckets
- ✅ **Lab 7**: Deployment and cleanup updated - generates buckets with "lab7" and "lab7-tenant" in names, deletes both buckets from `samconfig.toml` and `tenant-samconfig.toml`

## Benefits

1. **Complete lab independence**: Each lab manages its own SAM bucket(s)
2. **Simple logic**: No searching for buckets or checking for artifacts
3. **Predictable behavior**: Deploy creates bucket, cleanup deletes bucket
4. **No cross-lab interference**: Labs cannot affect each other's SAM buckets
5. **Easier to understand**: Clear ownership of resources per lab

## Testing

After this fix, you can:
1. Deploy Lab1 and Lab2 simultaneously - each uses its own SAM bucket
2. Clean up Lab1 completely - deletes Lab1's SAM bucket
3. Lab2 continues to work - has its own separate SAM bucket
4. Deploy Lab1 again - creates a fresh SAM bucket

## Related Files

### Cleanup Scripts (Updated)
- `workshop/Lab1/scripts/cleanup.sh` - Deletes bucket from `samconfig.toml`
- `workshop/Lab2/scripts/cleanup.sh` - Deletes bucket from `samconfig.toml`
- `workshop/Lab3/scripts/cleanup.sh` - Deletes buckets from `shared-samconfig.toml` and `tenant-samconfig.toml`
- `workshop/Lab4/scripts/cleanup.sh` - Deletes buckets from `shared-samconfig.toml` and `tenant-samconfig.toml`
- `workshop/Lab7/scripts/cleanup.sh` - Deletes bucket from `samconfig.toml`

### Deployment Scripts (Updated)
- `workshop/Lab1/scripts/deployment.sh` - Generates bucket with "lab1" in name if empty in `samconfig.toml`
- `workshop/Lab2/scripts/deployment.sh` - Generates bucket with "lab2" in name if empty in `samconfig.toml`
- `workshop/Lab3/scripts/deployment.sh` - Generates buckets with "lab3-shared" and "lab3-tenant" in names if empty in `shared-samconfig.toml` and `tenant-samconfig.toml`
- `workshop/Lab4/scripts/deployment.sh` - Generates buckets with "lab4-shared" and "lab4-tenant" in names if empty in `shared-samconfig.toml` and `tenant-samconfig.toml`
- `workshop/Lab7/scripts/deployment.sh` - Generates buckets with "lab7" and "lab7-tenant" in names if empty in `samconfig.toml` and `tenant-samconfig.toml`

### Documentation
- `workshop/PROFILE_ARG_BUG_FIX.md` - Related deployment script fix
- `.kiro/steering/deployment-cleanup-guide.md` - Updated cleanup commands

