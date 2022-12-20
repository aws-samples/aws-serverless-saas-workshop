# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import boto3
import os
import sys
import logger 
import utils
from boto3.dynamodb.conditions import Key

client = boto3.client('cognito-idp')
dynamodb = boto3.resource('dynamodb')
table_tenant_user_map = dynamodb.Table('ServerlessSaaS-TenantUserMapping')
table_tenant_details = dynamodb.Table('ServerlessSaaS-TenantDetails')

user_pool_id = os.environ['TENANT_USER_POOL_ID']

def create_tenant_admin_user(event, context):
    logger.info(event)
    app_client_id = os.environ['TENANT_APP_CLIENT_ID']
    tenant_details = json.loads(event['body'])
    tenant_id = tenant_details['tenantId']
    logger.info(tenant_details)

    user_mgmt = UserManagement()

    #Add tenant admin now based upon user pool
    tenant_user_group_response = user_mgmt.create_user_group(user_pool_id,tenant_id,"User group for tenant {0}".format(tenant_id))

    tenant_admin_user_name = 'tenant-admin-{0}'.format(tenant_details['tenantId'])

    create_tenant_admin_response = user_mgmt.create_tenant_admin(user_pool_id, tenant_admin_user_name, tenant_details)
    
    add_tenant_admin_to_group_response = user_mgmt.add_user_to_group(user_pool_id, tenant_admin_user_name, tenant_user_group_response['Group']['GroupName'])
    
    tenant_user_mapping_response = user_mgmt.create_user_tenant_mapping(tenant_admin_user_name,tenant_id)
    
    response = {"userPoolId": user_pool_id, "appClientId": app_client_id, "tenantAdminUserName": tenant_admin_user_name}
    return utils.create_success_response(response)

#only tenant admin can create users
def create_user(event, context):
    
    user_details = json.loads(event['body'])

    logger.info("Request received to create new user")
    logger.info(event)    
    
    tenant_id = user_details['tenantId']
    
    response = client.admin_create_user(
        Username=user_details['userName'],
        UserPoolId=user_pool_id,
        ForceAliasCreation=True,
        UserAttributes=[
            {
                'Name': 'email',
                'Value': user_details['userEmail']
            },
            {
                'Name': 'email_verified',
                'Value': 'true'
            },
            {
                'Name': 'custom:userRole',
                'Value': user_details['userRole'] 
            },            
            {
                'Name': 'custom:tenantId',
                'Value': tenant_id
            }
        ]
    )
    
    logger.info(response)
    user_mgmt = UserManagement()
    user_mgmt.add_user_to_group(user_pool_id, user_details['userName'], tenant_id)
    response_mapping = user_mgmt.create_user_tenant_mapping(user_details['userName'], tenant_id)

    logger.info("Request completed to create new user ")
    return utils.create_success_response("New user created")
    
def get_users(event, context):
    users = []  
    logger.info("Request received to get users")
    logger.info(event) 
    
    response = client.list_users(
        UserPoolId=user_pool_id
    )
    logger.info(response) 
    num_of_users = len(response['Users'])
    if (num_of_users > 0):
        for user in response['Users']:
            user_info = UserInfo()
            for attr in user["Attributes"]:
                if(attr["Name"] == "custom:tenantId"):
                    user_info.tenant_id = attr["Value"]

                if(attr["Name"] == "custom:userRole"):
                    user_info.user_role = attr["Value"]

                if(attr["Name"] == "email"):
                    user_info.email = attr["Value"] 
            user_info.enabled = user["Enabled"]
            user_info.created = user["UserCreateDate"]
            user_info.modified = user["UserLastModifiedDate"]
            user_info.status = user["UserStatus"] 
            user_info.user_name = user["Username"]
            users.append(user_info)                    
    # return an empty list when there are no users otherwise will result in API Gateway error
    return utils.generate_response(users)
    
   

def get_user(event, context):
    user_name = event['pathParameters']['username']  

    logger.info("Request received to get user")
    
    user_info = get_user_info(user_pool_id, user_name)
    logger.info("Request completed to get new user ")
    return utils.create_success_response(user_info.__dict__)

def update_user(event, context):
    user_details = json.loads(event['body'])
    user_name = event['pathParameters']['username']    

    logger.info("Request received to update user")

    response = client.admin_update_user_attributes(
        Username=user_name,
        UserPoolId=user_pool_id,
        UserAttributes=[
            {
                'Name': 'email',
                'Value': user_details['userEmail']
            },
            {
                'Name': 'custom:userRole',
                'Value': user_details['userRole'] 
            }
        ]
    )
    logger.info(response)

    logger.info("Request completed to update user")
        
    return utils.create_success_response("user updated")    

def disable_user(event, context):
    user_name = event['pathParameters']['username']

    logger.info("Request received to disable new user")
    
    response = client.admin_disable_user(
        Username=user_name,
        UserPoolId=user_pool_id
    )
        
    logger.info(response)
    logger.info("Request completed to disable new user")
    return utils.create_success_response("User disabled")
    
#This method uses IAM Authorization and protected using a resource policy. This method is also invoked async
def disable_users_by_tenant(event, context):
    logger.info("Request received to disable users by tenant")
    logger.info(event)    
    
    tenantid_to_update = event['tenantid']
    
    filtering_exp = Key('tenantId').eq(tenantid_to_update)
    response = table_tenant_user_map.query(KeyConditionExpression=filtering_exp)
    users = response.get('Items')
    
    for user in users:
        response = client.admin_disable_user(
            Username=user['userName'],
            UserPoolId=user_pool_id
        )
        
    logger.info(response)
    logger.info("Request completed to disable users")
    return utils.create_success_response("Users disabled")
    

#This method uses IAM Authorization and protected using a resource policy. This method is also invoked async
def enable_users_by_tenant(event, context):
    logger.info("Request received to enable users by tenant")
    logger.info(event)    
    
    tenantid_to_update = event['tenantid']
    
    filtering_exp = Key('tenantId').eq(tenantid_to_update)
    response = table_tenant_user_map.query(KeyConditionExpression=filtering_exp)
    users = response.get('Items')
    
    for user in users:
        response = client.admin_enable_user(
            Username=user['userName'],
            UserPoolId=user_pool_id
        )
        
    logger.info(response)
    logger.info("Request completed to enable users")
    return utils.create_success_response("Users enables")

def get_user_info(user_pool_id, user_name):
    response = client.admin_get_user(
            UserPoolId=user_pool_id,
            Username=user_name
    )
    logger.info(response)
    user_info =  UserInfo()
    user_info.user_name = response["Username"]
    for attr in response["UserAttributes"]:
        if(attr["Name"] == "custom:tenantId"):
            user_info.tenant_id = attr["Value"]
        if(attr["Name"] == "custom:userRole"):
            user_info.user_role = attr["Value"]    
        if(attr["Name"] == "email"):
            user_info.email = attr["Value"] 
    logger.info(user_info)        
    return user_info    

class UserManagement:
    def create_user_group(self, user_pool_id, group_name, group_description):
        response = client.create_group(
            GroupName=group_name,
            UserPoolId=user_pool_id,
            Description= group_description,
            Precedence=0
        )
        return response

    def create_tenant_admin(self, user_pool_id, tenant_admin_user_name, user_details):
        response = client.admin_create_user(
            Username=tenant_admin_user_name,
            UserPoolId=user_pool_id,
            ForceAliasCreation=True,
            UserAttributes=[
                {
                    'Name': 'email',
                    'Value': user_details['tenantEmail']
                },
                {
                    'Name': 'email_verified',
                    'Value': 'true'
                },
                {
                    'Name': 'custom:userRole',
                    'Value': 'TenantAdmin' 
                },            
                {
                    'Name': 'custom:tenantId',
                    'Value': user_details['tenantId']
                }
            ]
        )
        return response

    def add_user_to_group(self, user_pool_id, user_name, group_name):
        response = client.admin_add_user_to_group(
            UserPoolId=user_pool_id,
            Username=user_name,
            GroupName=group_name
        )
        return response

    def create_user_tenant_mapping(self, user_name, tenant_id):
        response = table_tenant_user_map.put_item(
                Item={
                        'tenantId': tenant_id,
                        'userName': user_name
                    }
                )                    

        return response


class UserInfo:
    def __init__(self, user_name=None, tenant_id=None, user_role=None, 
    email=None, status=None, enabled=None, created=None, modified=None):
        self.user_name = user_name
        self.tenant_id = tenant_id
        self.user_role = user_role
        self.email = email
        self.status = status
        self.enabled = enabled
        self.created = created
        self.modified = modified
  