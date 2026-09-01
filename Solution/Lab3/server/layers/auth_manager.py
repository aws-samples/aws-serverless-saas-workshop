# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import utils

# These are the roles being supported in this reference architecture
class UserRoles:
    SYSTEM_ADMIN    = "SystemAdmin"
    CUSTOMER_SUPPORT  = "CustomerSupport"
    TENANT_ADMIN    = "TenantAdmin"    
    TENANT_USER     = "TenantUser"
    
def isTenantAdmin(user_role):
    if (user_role == UserRoles.TENANT_ADMIN):
        return True
    else:
        return False

def isSystemAdmin(user_role):
    if (user_role == UserRoles.SYSTEM_ADMIN):
        return True
    else:
        return False


def isSaaSProvider(user_role):
    if (user_role == UserRoles.SYSTEM_ADMIN or user_role == UserRoles.CUSTOMER_SUPPORT):
        return True
    else:
        return False
def isTenantUser(user_role):
    if (user_role == UserRoles.TENANT_USER):
        return True
    else:
        return False


# Which roles a caller is allowed to assign to a user. A caller may never grant a
# role more privileged than their own, so a tenant admin cannot mint a
# provider-level SystemAdmin and hand it cross-tenant access. CustomerSupport is
# absent deliberately: getPolicyForUser has no policy for it, so such an account
# could not authenticate.
ASSIGNABLE_ROLES = {
    UserRoles.SYSTEM_ADMIN: [UserRoles.SYSTEM_ADMIN, UserRoles.TENANT_ADMIN, UserRoles.TENANT_USER],
    UserRoles.TENANT_ADMIN: [UserRoles.TENANT_ADMIN, UserRoles.TENANT_USER],
}


def canAssignRole(actor_role, role_to_assign):
    """ Whether actor_role may assign role_to_assign to a user.

    actor_role must come from the authorizer context, never the request body.
    """
    return role_to_assign in ASSIGNABLE_ROLES.get(actor_role, [])

