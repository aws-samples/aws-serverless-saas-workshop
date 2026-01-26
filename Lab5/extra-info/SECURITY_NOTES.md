# Lab5 Security Configuration

## Cognito User Pool Security

### Current Configuration ✅

Both Cognito User Pools in this lab are configured with **admin-only user creation**:

1. **Tenant User Pool** (`PooledTenant-ServerlessSaaS-lab5-UserPool`)
   - Self-registration: **DISABLED** (default)
   - User creation: Admin-only via API
   - Authentication: OAuth 2.0 with Cognito

2. **Operations User Pool** (`OperationUsers-ServerlessSaas-lab5-UserPool`)
   - Self-registration: **DISABLED** (default)
   - User creation: Admin-only
   - Initial admin: Created during stack deployment

### How Users Are Created

**Tenant Registration Flow:**
```
1. System Admin → Registers tenant via Admin UI
2. Tenant Registration API → Creates tenant admin in Cognito
3. Tenant Admin → Receives email with temporary password
4. Tenant Admin → Can create additional users for their tenant
```

**System Admin Creation:**
```
1. CloudFormation → Creates initial admin during deployment
2. Admin → Receives email with temporary password
3. Admin → Can create additional system admins
```

### Making Security Explicit (Optional)

If you want to make the security configuration more explicit in the CloudFormation template, you can add:

```yaml
AdminCreateUserConfig:
  AllowAdminCreateUserOnly: true  # Explicitly disable self-registration
  InviteMessageTemplate:
    EmailMessage: "..."
    EmailSubject: "..."
```

**Note:** This is already the default behavior when `AllowAdminCreateUserOnly` is not specified, but adding it makes the intent clearer.

## Additional Security Recommendations

### 1. Enable MFA (Multi-Factor Authentication)

Add to User Pool configuration:

```yaml
MfaConfiguration: OPTIONAL  # or REQUIRED
EnabledMfas:
  - SOFTWARE_TOKEN_MFA
  - SMS_MFA
```

### 2. Password Policy

Add stronger password requirements:

```yaml
Policies:
  PasswordPolicy:
    MinimumLength: 12
    RequireUppercase: true
    RequireLowercase: true
    RequireNumbers: true
    RequireSymbols: true
    TemporaryPasswordValidityDays: 3
```

### 3. Advanced Security Features

Enable advanced security for threat detection:

```yaml
UserPoolAddOns:
  AdvancedSecurityMode: ENFORCED  # or AUDIT
```

This enables:
- Compromised credentials detection
- Adaptive authentication
- Risk-based authentication

### 4. Account Takeover Protection

```yaml
AccountTakeoverRiskConfiguration:
  Actions:
    HighAction:
      EventAction: MFA_REQUIRED
      Notify: true
    MediumAction:
      EventAction: MFA_IF_CONFIGURED
      Notify: true
    LowAction:
      EventAction: NO_ACTION
      Notify: false
```

## Current Security Controls

### Authentication
- ✅ OAuth 2.0 / OpenID Connect
- ✅ JWT tokens with expiration
- ✅ Email verification required
- ✅ Temporary passwords expire

### Authorization
- ✅ Custom attributes for tenant isolation (`tenantId`)
- ✅ Role-based access control (`userRole`)
- ✅ Lambda authorizers validate tokens
- ✅ Tenant context in all API calls

### Tenant Isolation
- ✅ Tenant ID in user attributes
- ✅ Tenant ID validated in authorizers
- ✅ Separate stacks per tenant (silo model)
- ✅ DynamoDB tables scoped by tenant

## Monitoring & Compliance

### CloudWatch Logs
All authentication events are logged to CloudWatch:
- Login attempts
- Failed authentications
- Password changes
- User creation events

### Audit Trail
Track user activities:
```bash
# View Cognito events
aws logs tail /aws/cognito/userpools/POOL_ID --follow

# View API Gateway access logs
aws logs tail /aws/apigateway/ACCESS_LOG_GROUP --follow
```

## Security Checklist for Production

- [ ] Enable MFA for all admin users
- [ ] Implement password rotation policy
- [ ] Enable advanced security features
- [ ] Set up CloudWatch alarms for failed login attempts
- [ ] Implement account lockout after N failed attempts
- [ ] Enable CloudTrail for API audit logging
- [ ] Regular security reviews of IAM policies
- [ ] Implement least privilege access
- [ ] Enable encryption at rest for all data stores
- [ ] Use AWS Secrets Manager for sensitive configuration
- [ ] Implement rate limiting on APIs
- [ ] Regular penetration testing
- [ ] Security training for development team

## References

- [Cognito Security Best Practices](https://docs.aws.amazon.com/cognito/latest/developerguide/security-best-practices.html)
- [SaaS Identity and Isolation](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/identity-and-isolation.html)
- [AWS SaaS Factory](https://aws.amazon.com/partners/programs/saas-factory/)
