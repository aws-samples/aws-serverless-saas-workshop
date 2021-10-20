# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import os
import json
import boto3
from boto3.dynamodb.conditions import Key
import urllib.parse
import utils
from botocore.exceptions import ClientError
import logger
import requests

region = os.environ['AWS_REGION']

dynamodb = boto3.resource('dynamodb')
table_tenant_details = dynamodb.Table('ServerlessSaaS-TenantDetails')

#This method has been locked down to be only called from tenant registration service
def create_tenant(event, context):
    tenant_details = json.loads(event['body'])

    try:          
        response = table_tenant_details.put_item(
            Item={
                    'tenantId': tenant_details['tenantId'],
                    'tenantName' : tenant_details['tenantName'],
                    'tenantAddress': tenant_details['tenantAddress'],
                    'tenantEmail': tenant_details['tenantEmail'],
                    'tenantPhone': tenant_details['tenantPhone'],
                    'tenantTier': tenant_details['tenantTier'],                    
                    'isActive': True                    
                }
            )                    

    except Exception as e:
        raise Exception('Error creating a new tenant', e)
    else:
        return utils.create_success_response("Tenant Created")

def get_tenants(event, context):
    
    try:
        response = table_tenant_details.scan()
    except Exception as e:
        raise Exception('Error getting all tenants', e)
    else:
        return utils.generate_response(response['Items'])    

def update_tenant(event, context):
    
    tenant_details = json.loads(event['body'])
    tenant_id = event['pathParameters']['tenantid']
    
    
    logger.info("Request received to update tenant")
    
    response_update = table_tenant_details.update_item(
        Key={
            'tenantId': tenant_id,
        },
        UpdateExpression="set tenantName = :tenantName, tenantAddress = :tenantAddress, tenantEmail = :tenantEmail, tenantPhone = :tenantPhone, tenantTier=:tenantTier",
        ExpressionAttributeValues={
                ':tenantName' : tenant_details['tenantName'],
                ':tenantAddress': tenant_details['tenantAddress'],
                ':tenantEmail': tenant_details['tenantEmail'],
                ':tenantPhone': tenant_details['tenantPhone'],
                ':tenantTier': tenant_details['tenantTier']                
            },
        ReturnValues="UPDATED_NEW"
        )             
                
    logger.info(response_update)     

    logger.info("Request completed to update tenant")
    return utils.create_success_response("Tenant Updated")    

def get_tenant(event, context):
    tenant_id = event['pathParameters']['tenantid']    
    logger.info("Request received to get tenant details")
    
    tenant_details = table_tenant_details.get_item(
        Key={
            'tenantId': tenant_id,
        },
        AttributesToGet=[
            'tenantName',
            'tenantAddress',
            'tenantEmail',
            'tenantPhone'
        ]    
    )             
    item = tenant_details['Item']
    tenant_info = TenantInfo(item['tenantName'], item['tenantAddress'],item['tenantEmail'], item['tenantPhone'])
    logger.info(tenant_info)
    
    logger.info("Request completed to get tenant details")
    return utils.create_success_response(tenant_info.__dict__)

def deactivate_tenant(event, context):
    
    url_disable_users = os.environ['DISABLE_USERS_BY_TENANT']
    stage_name = event['requestContext']['stage']
    host = event['headers']['Host']
    auth = utils.get_auth(host, region)
    headers = utils.get_headers(event)

    tenant_id = event['pathParameters']['tenantid']
    
    logger.info("Request received to deactivate tenant")

    response = table_tenant_details.update_item(
        Key={
            'tenantId': tenant_id,
        },
        UpdateExpression="set isActive = :isActive",
        ExpressionAttributeValues={
                ':isActive': False
            },
        ReturnValues="ALL_NEW"
    )             
    
    logger.info(response)

    update_user_response = __invoke_disable_users(headers, auth, host, stage_name, url_disable_users, tenant_id)
    logger.info(update_user_response)

    logger.info("Request completed to deactivate tenant")
    return utils.create_success_response("Tenant Deactivated")

def activate_tenant(event, context):
    
    url_enable_users = os.environ['ENABLE_USERS_BY_TENANT']
    stage_name = event['requestContext']['stage']
    host = event['headers']['Host']
    auth = utils.get_auth(host, region)
    headers = utils.get_headers(event)

    tenant_id = event['pathParameters']['tenantid']
    
    logger.info("Request received to activate tenant")

    response = table_tenant_details.update_item(
        Key={
            'tenantId': tenant_id,
        },
        UpdateExpression="set isActive = :isActive",
        ExpressionAttributeValues={
                ':isActive': True
            },
        ReturnValues="ALL_NEW"
    )             
    
    logger.info(response)

    update_user_response = __invoke_enable_users(headers, auth, host, stage_name, url_enable_users, tenant_id)
    logger.info(update_user_response)

    logger.info("Request completed to activate tenant")
    return utils.create_success_response("Tenant activated")
    
def __invoke_disable_users(headers, auth, host, stage_name, invoke_url, tenant_id):
    try:
        url = ''.join(['https://', host, '/', stage_name, invoke_url, '/', tenant_id])
        response = requests.put(url, auth=auth, headers=headers) 
        
        logger.info(response.status_code)
        if (int(response.status_code) != int(utils.StatusCodes.SUCCESS.value)):
            raise Exception('Error occured while disabling users for the tenant')     
        
    except Exception as e:
        logger.error('Error occured while disabling users for the tenant')
        raise Exception('Error occured while disabling users for the tenant', e) 
    else:
        return "Success invoking disable users"

def __invoke_enable_users(headers, auth, host, stage_name, invoke_url, tenant_id):
    try:
        url = ''.join(['https://', host, '/', stage_name, invoke_url, '/', tenant_id])
        response = requests.put(url, auth=auth, headers=headers) 
        
        logger.info(response.status_code)
        if (int(response.status_code) != int(utils.StatusCodes.SUCCESS.value)):
            raise Exception('Error occured while enabling users for the tenant')     
        
    except Exception as e:
        logger.error('Error occured while enabling users for the tenant')
        raise Exception('Error occured while enabling users for the tenant', e) 
    else:
        return "Success invoking enable users"

class TenantInfo:
    def __init__(self, tenant_name, tenant_address, tenant_email, tenant_phone):
        self.tenant_name = tenant_name
        self.tenant_address = tenant_address
        self.tenant_email = tenant_email
        self.tenant_phone = tenant_phone

   