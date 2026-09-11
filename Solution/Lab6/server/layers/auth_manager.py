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

def getPolicyForUser(user_role, service_identifier, tenant_id, region, aws_account_id):
    """ This method is being used by Authorizer to get appropriate policy by user role

    Args:
        user_role (string): UserRoles enum
        tenant_id (string): 
        region (string): 
        aws_account_id (string):  

    Returns:
        string: policy that tenant needs to assume
    """
    if (isSystemAdmin(user_role)):
        iam_policy = __getPolicyForSystemAdmin(region, aws_account_id)
    elif (isTenantAdmin(user_role)):
        iam_policy = __getPolicyForTenantAdmin(tenant_id, service_identifier, region, aws_account_id)
    elif (isTenantUser(user_role)):
        iam_policy = __getPolicyForTenantUser(tenant_id, region, aws_account_id)
    else:
        # Fail closed. Returning an empty policy here would leave the
        # caller's access to whatever the assumed role already permits.
        raise PermissionError(
            "Unauthorized: no policy is defined for role '{0}'".format(user_role))
    
    return iam_policy

def __getPolicyForSystemAdmin(region, aws_account_id):
    policy = {	
        "Version": "2012-10-17",
          "Statement": [
              {
                  "Effect": "Allow",
                  "Action": [
                    "dynamodb:UpdateItem",
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",          
                    "dynamodb:Scan"
                  ],
                  "Resource": [
                       "arn:aws:dynamodb:{0}:{1}:table/*".format(region, aws_account_id),
                  ]
              }
          ]
        }
    
    return json.dumps(policy)
    
def __getPolicyForTenantAdmin(tenant_id, sevice_identifier, region, aws_account_id):
    if (sevice_identifier == utils.Service_Identifier.SHARED_SERVICES.value):
        policy = {	
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:UpdateItem",
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:Query"                   
                    ],
                    "Resource": [
                        "arn:aws:dynamodb:{0}:{1}:table/ServerlessSaaS-TenantUserMapping".format(region, aws_account_id),
                        "arn:aws:dynamodb:{0}:{1}:table/ServerlessSaaS-TenantDetails".format(region, aws_account_id)
                    ],
                    "Condition": {
                        "ForAllValues:StringEquals": {
                            "dynamodb:LeadingKeys": [
                                "{0}".format(tenant_id)
                            ]
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:UpdateItem",
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query"               
                    ],
                    "Resource": [
                        "arn:aws:dynamodb:{0}:{1}:table/ServerlessSaaS-TenantStackMapping".format(region, aws_account_id),
                        "arn:aws:dynamodb:{0}:{1}:table/ServerlessSaaS-Settings".format(region, aws_account_id)
                    ]
                }
            ]
        }
    else:
        policy = {	
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:UpdateItem",
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query"    
                    ],
                    "Resource": [
                        "arn:aws:dynamodb:{0}:{1}:table/Product-*".format(region, aws_account_id),                      
                    ],
                    "Condition": {
                        "ForAllValues:StringLike": {
                            "dynamodb:LeadingKeys": [
                                "{0}-*".format(tenant_id)
                            ]
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:UpdateItem",
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query"       
                    ],
                    "Resource": [
                        "arn:aws:dynamodb:{0}:{1}:table/Order-*".format(region, aws_account_id),                      
                    ],
                    "Condition": {
                        "ForAllValues:StringLike": {
                            "dynamodb:LeadingKeys": [
                                "{0}-*".format(tenant_id)
                            ]
                        }
                    }
                }
            ]
        }
    return json.dumps(policy)

def __getPolicyForTenantUser(tenant_id, region, aws_account_id):
    
    policy = {	
        "Version": "2012-10-17",
          "Statement": [
              {
                  "Effect": "Allow",
                  "Action": [
                      "dynamodb:UpdateItem",
                      "dynamodb:GetItem",
                      "dynamodb:PutItem",
                      "dynamodb:DeleteItem",
                      "dynamodb:Query"      
                  ],
                  "Resource": [
                      "arn:aws:dynamodb:{0}:{1}:table/Product-*".format(region, aws_account_id),                      
                  ],
                  "Condition": {
                      "ForAllValues:StringLike": {
                          "dynamodb:LeadingKeys": [
                              "{0}-*".format(tenant_id)
                          ]
                      }
                  }
              },
              {
                  "Effect": "Allow",
                  "Action": [
                      "dynamodb:UpdateItem",
                      "dynamodb:GetItem",
                      "dynamodb:PutItem",
                      "dynamodb:DeleteItem",
                      "dynamodb:Query"               
                  ],
                  "Resource": [
                      "arn:aws:dynamodb:{0}:{1}:table/Order-*".format(region, aws_account_id),                      
                  ],
                  "Condition": {
                      "ForAllValues:StringLike": {
                          "dynamodb:LeadingKeys": [
                              "{0}-*".format(tenant_id)
                          ]
                      }
                  }
              }
          ]
        }
    
    return json.dumps(policy)

