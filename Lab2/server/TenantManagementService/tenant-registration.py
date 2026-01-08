# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import boto3
import os
import utils
import uuid
import logger
import requests
import re

region = os.environ['AWS_REGION']
create_tenant_admin_user_resource_path = os.environ['CREATE_TENANT_ADMIN_USER_RESOURCE_PATH']
create_tenant_resource_path = os.environ['CREATE_TENANT_RESOURCE_PATH']

lambda_client = boto3.client('lambda')

#TODO: Implement this method
def register_tenant(event, context):
    try:
        tenant_id = uuid.uuid1().hex
        tenant_details = json.loads(event['body'])

        tenant_details['tenantId'] = tenant_id

        logger.info(tenant_details)

        stage_name = event['requestContext']['stage']
        host = event['headers']['Host']
        auth = utils.get_auth(host, region)
        headers = utils.get_headers(event)
        create_user_response = __create_tenant_admin_user(tenant_details, headers, auth, host, stage_name)
        
        logger.info(f"create_user_response type: {type(create_user_response)}, value: {create_user_response}")
        
        # Parse the response - it comes back as {"message": {...}}
        if create_user_response is None:
            raise Exception('Failed to create tenant admin user - received None response')
        
        if 'message' in create_user_response:
            tenant_details['tenantAdminUserName'] = create_user_response['message']['tenantAdminUserName']
        else:
            tenant_details['tenantAdminUserName'] = create_user_response['tenantAdminUserName']

        create_tenant_response = __create_tenant(tenant_details, headers, auth, host, stage_name)
        logger.info (create_tenant_response)

    except Exception as e:
        logger.error('Error registering a new tenant')
        raise Exception('Error registering a new tenant', e)
    else:
        return utils.create_success_response("You have been registered in our system")

def __create_tenant_admin_user(tenant_details, headers, auth, host, stage_name):
    try:
        url = ''.join(['https://', host, '/', stage_name, create_tenant_admin_user_resource_path])
        logger.info(f"Calling create tenant admin user at: {url}")
        response = requests.post(url, data=json.dumps(tenant_details), auth=auth, headers=headers) 
        logger.info(f"Response status code: {response.status_code}")
        logger.info(f"Response text: {response.text}")
        response_json = response.json()
        logger.info(f"Response JSON: {response_json}")
    except Exception as e:
        logger.error(f'Error occured while calling the create tenant admin user service: {str(e)}')
        raise Exception('Error occured while calling the create tenant admin user service', e)
    else:
        return response_json

def __create_tenant(tenant_details, headers, auth, host, stage_name):
    try:
        url = ''.join(['https://', host, '/', stage_name, create_tenant_resource_path])
        response = requests.post(url, data=json.dumps(tenant_details), auth=auth, headers=headers) 
        response_json = response.json()
    except Exception as e:
        logger.error('Error occured while creating the tenant record in table')
        raise Exception('Error occured while creating the tenant record in table', e) 
    else:
        return response_json

              
