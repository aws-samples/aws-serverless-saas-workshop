# Cognito Admin User Duplication Fix

## Issue Summary

**Problem**: Two admin users were being created in the Cognito OperationUsers pool:
1. User `admin` with email `test@test.com` (created by CloudFormation)
2. User `admin-user` with email `your-email@example.com` (created by deployment script)

**Impact**: 
- Confusion about which user to use for login
- Unexpected user with hardcoded test email
- Email notifications sent to wrong address

## Root Cause

### 1. CloudFormation Template Default Value
**File**: `workshop/Lab2/server/template.yaml`

```yaml
Parameters:
  AdminEmailParameter:
    Type: String
    Default: "test@test.com"  # ← HARDCODED DEFAULT
    Description: "Enter system admin email address"
```

### 2. CloudFormation Creates User Automatically
**File**: `workshop/Lab2/server/nested_templates/cognito.yaml`

```yaml
CognitoAdminUser:
  Type: AWS::Cognito::UserPoolUser
  Properties:
    Username: admin  # ← Creates "admin" user
    UserAttributes:
      - Name: email
        Value: !Ref AdminEmailParameter  # ← Uses default "test@test.com"
```

### 3. Deployment Script Creates Second User
**File**: `workshop/Lab2/scripts/deployment.sh`

```bash
# Creates "admin-user" with provided email
aws cognito-idp admin-create-user \
  --username admin-user \
  --user-attributes Name=email,Value="$ADMIN_EMAIL"  # ← Uses --email flag
```

### Why This Happened

1. **SAM deployment doesn't override parameter**: When running `sam deploy`, the `AdminEmailParameter` is not overridden, so it uses the default value `test@test.com`
2. **CloudFormation creates first user**: The `CognitoAdminUser` resource creates user `admin` with the default email
3. **Script creates second user**: The deployment script then creates `admin-user` with the email provided via `--email` flag
4. **Result**: Two users exist in the same Cognito pool

## Solution Implemented

### 1. Changed Default Parameter to Empty String
**File**: `workshop/Lab2/server/template.yaml`

```yaml
Parameters:
  AdminEmailParameter:
    Type: String
    Default: ""  # ← Empty default
    Description: "Enter system admin email address (leave empty to skip CloudFormation user creation)"
```

### 2. Added Condition to Skip CloudFormation User Creation
**File**: `workshop/Lab2/server/nested_templates/cognito.yaml`

```yaml
Conditions:
  CreateAdminUserInCloudFormation: !Not [!Equals [!Ref AdminEmailParameter, ""]]

Resources:
  CognitoAdminUser:
    Type: AWS::Cognito::UserPoolUser
    Condition: CreateAdminUserInCloudFormation  # ← Only create if email provided
    Properties:
      Username: admin
      # ... rest of properties

  CognitoAddUserToGroup:
    Type: AWS::Cognito::UserPoolUserToGroupAttachment
    Condition: CreateAdminUserInCloudFormation  # ← Only create if user exists
    Properties:
      # ... properties
```

### How It Works Now

1. **Default behavior** (no `AdminEmailParameter` override):
   - `AdminEmailParameter` = "" (empty)
   - Condition `CreateAdminUserInCloudFormation` = false
   - CloudFormation **SKIPS** creating `admin` user
   - Deployment script creates `admin-user` with provided email ✅

2. **If email is explicitly provided to CloudFormation**:
   - `AdminEmailParameter` = "someone@example.com"
   - Condition `CreateAdminUserInCloudFormation` = true
   - CloudFormation creates `admin` user with that email
   - Deployment script still creates `admin-user` (both users exist)

## Verification Steps

### Before Fix
```bash
# List users in Cognito pool
aws cognito-idp list-users \
  --user-pool-id <pool-id> \
  --profile <your-profile-name>

# Output shows TWO users:
# 1. Username: admin, Email: test@test.com
# 2. Username: admin-user, Email: your-email@example.com
```

### After Fix
```bash
# Deploy with fix
cd workshop/Lab2/scripts
./deployment.sh -s -c --email your-email@example.com --profile <your-profile-name>

# List users in Cognito pool
aws cognito-idp list-users \
  --user-pool-id <pool-id> \
  --profile <your-profile-name>

# Output shows ONE user:
# Username: admin-user, Email: your-email@example.com ✅
```

## Impact on Other Labs

This same pattern exists in other labs. The fix should be applied to:

- ✅ **Lab 2**: Fixed
- ⚠️ **Lab 3**: Needs same fix
- ⚠️ **Lab 4**: Needs same fix
- ⚠️ **Lab 5**: Needs same fix
- ⚠️ **Lab 6**: Needs same fix

## Files Modified

1. `workshop/Lab2/server/template.yaml`
   - Changed `AdminEmailParameter` default from `"test@test.com"` to `""`
   - Updated description to clarify behavior

2. `workshop/Lab2/server/nested_templates/cognito.yaml`
   - Added `Conditions` section with `CreateAdminUserInCloudFormation`
   - Added condition to `CognitoAdminUser` resource
   - Added condition to `CognitoAddUserToGroup` resource

## Testing Checklist

- [ ] Deploy Lab 2 with fix
- [ ] Verify only `admin-user` exists in Cognito
- [ ] Verify email is sent to correct address
- [ ] Verify login works with `admin-user` username
- [ ] Apply same fix to Labs 3-6
- [ ] Test each lab after applying fix

## Related Issues

- **API Gateway Logs Cleanup**: Fixed in `workshop/API_GATEWAY_LOGS_CLEANUP_UPDATE.md`
- **Admin Email Not Received**: Likely caused by duplicate user creation confusion

## References

- CloudFormation Conditions: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/conditions-section-structure.html
- Cognito User Pool User: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-cognito-userpooluser.html
