# CloudFront Origin Hijacking Security Fix

## Critical Security Vulnerability

### The Problem: CloudFront Origin Hijacking

If S3 buckets are deleted **before** CloudFront distributions are deleted, a serious security vulnerability occurs:

1. **S3 bucket is deleted** (e.g., `my-app-bucket-abc123`)
2. **CloudFront distribution still exists** and points to `my-app-bucket-abc123.s3.amazonaws.com`
3. **Attacker creates a bucket** with the same name `my-app-bucket-abc123` in their AWS account
4. **CloudFront now serves attacker's content** to your users visiting your CloudFront URL

### Security Impact

This vulnerability can lead to:
- **Phishing attacks**: Attacker serves fake login pages
- **Malware distribution**: Attacker serves malicious files
- **Brand reputation damage**: Your domain serves attacker's content
- **Data theft**: Attacker can steal user credentials or sensitive data
- **Compliance violations**: Serving unauthorized content through your infrastructure

### Real-World Example

```
Original Setup:
CloudFront URL: https://d1234567890abc.cloudfront.net
Origin: my-workshop-app-abc123.s3.amazonaws.com

Insecure Cleanup (VULNERABLE):
1. Delete S3 bucket "my-workshop-app-abc123" ❌
2. CloudFront still points to "my-workshop-app-abc123.s3.amazonaws.com"
3. Attacker creates "my-workshop-app-abc123" in their account
4. Users visiting https://d1234567890abc.cloudfront.net see attacker's content ⚠️

Secure Cleanup (FIXED):
1. Delete CloudFormation stack (deletes CloudFront) ✅
2. Wait for CloudFront to be fully deleted (15-30 min)
3. Delete S3 bucket "my-workshop-app-abc123" ✅
4. No vulnerability window exists ✅
```

## The Fix

### Secure Deletion Order

All cleanup scripts now follow this order:

```
# Step 1: Identify S3 buckets (but don't delete yet)
APP_SITE_BUCKET=$(aws cloudformation describe-stacks ...)

# Step 2: Delete CloudFormation stack (deletes CloudFront)
aws cloudformation delete-stack --stack-name "$STACK_NAME"

# Wait for stack deletion to complete (includes CloudFront deletion)
while [ "$STATUS" != "DELETE_COMPLETE" ]; do
    sleep 10
done

# Step 3: NOW safely delete S3 buckets (CloudFront is gone)
aws s3 rm "s3://$APP_SITE_BUCKET" --recursive
aws s3api delete-bucket --bucket $APP_SITE_BUCKET

# Step 4: Delete CloudWatch logs
# Step 5: Delete remaining resources
# Step 6: Delete SAM bootstrap bucket
```

### Why This Works

1. **CloudFormation manages CloudFront deletion**: When you delete the stack, CloudFormation:
   - Disables the CloudFront distribution
   - Waits for it to propagate to all edge locations (15-30 minutes)
   - Deletes the distribution
   - Only then marks the stack as `DELETE_COMPLETE`

2. **No vulnerability window**: By waiting for `DELETE_COMPLETE`, we ensure CloudFront is fully deleted before touching S3 buckets

3. **Atomic operation**: The stack deletion is atomic - either everything deletes or nothing does

## Implementation Details

### Changes Made to All Labs

#### Lab 1
- ✅ Reordered cleanup steps
- ✅ Added security note in script header
- ✅ S3 buckets deleted after CloudFormation stack deletion completes

#### Labs 2-7
- ✅ Same security fix applied
- ✅ Multiple S3 buckets (admin, landing, application) all deleted after CloudFront
- ✅ Nested stacks (shared, tenant) properly handled

### Code Changes

**Before (INSECURE):**
```
# Step 1: Empty S3 buckets ❌ DANGEROUS
aws s3 rm "s3://$APP_SITE_BUCKET" --recursive

# Step 2: Delete CloudFormation stack
aws cloudformation delete-stack --stack-name "$STACK_NAME"
```

**After (SECURE):**
```
# Step 1: Identify S3 buckets (don't delete)
APP_SITE_BUCKET=$(aws cloudformation describe-stacks ...)

# Step 2: Delete CloudFormation stack (deletes CloudFront)
aws cloudformation delete-stack --stack-name "$STACK_NAME"
# Wait for DELETE_COMPLETE...

# Step 3: Now safely delete S3 buckets ✅ SAFE
aws s3 rm "s3://$APP_SITE_BUCKET" --recursive
```

## Testing the Fix

### Verification Steps

1. **Run cleanup script**:
   ```
   cd workshop/Lab1/scripts
   ./cleanup.sh --stack-name serverless-saas-lab1 --profile serverless-saas-demo
   ```

2. **Observe the order**:
   - Step 1: Identifies S3 buckets (doesn't delete)
   - Step 2: Deletes CloudFormation stack (waits for completion)
   - Step 3: Deletes S3 buckets (after CloudFront is gone)

3. **Verify no vulnerability window**:
   - Check CloudFront console - distributions should be deleted
   - Check S3 console - buckets should be deleted
   - No time window where CloudFront exists without S3

### Manual Verification

```
# Check CloudFront distributions
aws cloudfront list-distributions --profile serverless-saas-demo

# Check S3 buckets
aws s3 ls --profile serverless-saas-demo | grep serverless-saas-lab1

# Both should return empty/no results after cleanup
```

## Best Practices

### For Workshop Maintainers

1. **Never change the deletion order** without security review
2. **Always delete CloudFront before S3** in any cleanup script
3. **Wait for CloudFormation DELETE_COMPLETE** before deleting S3
4. **Document the security rationale** in script comments

### For Workshop Users

1. **Use the provided cleanup scripts** - don't manually delete resources
2. **Don't interrupt cleanup scripts** - let them complete fully
3. **Verify cleanup completion** - check that all resources are deleted
4. **Report any issues** - if cleanup fails, investigate before retrying

## Additional Security Considerations

### CloudFront Deletion Time

- CloudFront distributions take **15-30 minutes** to delete
- This is because CloudFront must:
  - Disable the distribution
  - Propagate the disabled state to all edge locations worldwide
  - Wait for all edge caches to clear
  - Then delete the distribution

### S3 Bucket Name Reuse

- S3 bucket names are **globally unique**
- After deletion, the name becomes available **immediately**
- An attacker can claim the name **within seconds**
- This is why the deletion order is critical

### Defense in Depth

Even with this fix, consider:
- Using **Origin Access Identity (OAI)** for CloudFront → S3 (already implemented)
- Enabling **S3 Block Public Access** (already implemented)
- Using **CloudFront signed URLs** for sensitive content
- Monitoring **CloudFront access logs** for suspicious activity

## References

- [AWS CloudFront Security Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/security-best-practices.html)
- [S3 Bucket Naming and Availability](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)
- [CloudFront Origin Hijacking Prevention](https://aws.amazon.com/blogs/security/)

## Summary

**The Fix**: Delete CloudFormation stack (which deletes CloudFront) BEFORE deleting S3 buckets.

**Why**: Prevents attackers from hijacking your CloudFront distribution by claiming your deleted S3 bucket name.

**Impact**: All labs (Lab1-Lab7) now follow secure deletion order.

**Status**: ✅ Fixed in all cleanup scripts
