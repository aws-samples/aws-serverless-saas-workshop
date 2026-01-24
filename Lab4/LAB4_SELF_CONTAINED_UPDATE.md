# Lab 4 Self-Contained Client Deployment Update

## Summary

Updated Lab 4 deployment script to be **self-contained** by deploying all three client applications (Admin, Landing, and Application) instead of depending on Lab 2's clients.

## Changes Made

### Before
- Lab 4 only deployed the **Application client**
- Admin and Landing clients were expected to be deployed from Lab 2
- This created a dependency: Lab 2 had to be deployed before Lab 4 could work properly
- Comment in script: "Admin UI and Landing UI are configured in Lab2. Only App UI will be configured in this Lab4."

### After
- Lab 4 now deploys **all three clients**: Admin, Landing, and Application
- Lab 4 is completely independent and self-contained
- No dependency on Lab 2 for client applications
- Each lab can now be deployed and tested independently

## Technical Details

### Client Deployment Order
1. **Admin Client**
   - Configures environment with Admin API Gateway URL
   - Sets up Cognito user pool configuration
   - Creates admin user if email provided
   - Deploys to `AdminAppBucket` S3 bucket

2. **Landing Client**
   - Configures environment with Admin API Gateway URL
   - Deploys to `LandingAppBucket` S3 bucket

3. **Application Client**
   - Configures environment with both Admin and Tenant API Gateway URLs
   - Sets up Cognito tenant user pool configuration
   - Deploys to `ApplicationSiteBucket` S3 bucket

### Stack Outputs Used
From `serverless-saas-shared-lab4`:
- `AdminAppBucket` - S3 bucket for Admin client
- `LandingAppBucket` - S3 bucket for Landing client
- `ApplicationSiteBucket` - S3 bucket for Application client
- `AdminApi` - Admin API Gateway URL
- `CognitoOperationUsersUserPoolId` - Admin user pool
- `CognitoOperationUsersUserPoolClientId` - Admin app client
- `CognitoTenantUserPoolId` - Tenant user pool
- `CognitoTenantAppClientId` - Tenant app client
- `CognitoAdminUserGroupName` - Admin user group

From `serverless-saas-tenant-lab4`:
- `TenantAPI` - Tenant API Gateway URL

## Benefits

1. **Independence**: Each lab can be deployed without dependencies on other labs
2. **Simplicity**: Users don't need to understand cross-lab dependencies
3. **Testing**: Easier to test individual labs in isolation
4. **Maintenance**: Changes to one lab don't affect others
5. **Workshop Flow**: More flexible workshop execution order

## Deployment Command

```bash
cd workshop/Lab4/scripts
./deployment.sh -s -c --email lancdieg@amazon.com --tenant-email lancdieg@amazon.com --profile serverless-saas-demo
```

This single command now deploys:
- Shared stack (bootstrap services)
- Tenant stack (microservices)
- Admin client
- Landing client
- Application client
- Sample tenants (if tenant email provided)

## Verification

After deployment, all three CloudFront URLs should return 200 OK:
- Admin Site: `https://<cloudfront-domain>.cloudfront.net` (200 OK)
- Landing Site: `https://<cloudfront-domain>.cloudfront.net` (200 OK)
- App Site: `https://<cloudfront-domain>.cloudfront.net` (200 OK)

All three S3 buckets should contain client files:
- `serverless-saas-workshop-lab4-adminappbucket-*` (Admin client files)
- `serverless-saas-workshop-lab4-landingappbucket-*` (Landing client files)
- `serverless-saas-workshop-lab4-appbucket-*` (Application client files)

## Related Files

- `workshop/Lab4/scripts/deployment.sh` - Updated deployment script
- `workshop/Lab4/client/Admin/` - Admin client source
- `workshop/Lab4/client/Landing/` - Landing client source
- `workshop/Lab4/client/Application/` - Application client source

## Date

January 23, 2026
