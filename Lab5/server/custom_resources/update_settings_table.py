# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import boto3
import logger

from crhelper import CfnResource
helper = CfnResource()

try:
    dynamodb = boto3.resource('dynamodb')
except Exception as e:
    helper.init_failure(e)
    
    
@helper.create
@helper.update
def do_action(event, _):
    """ Called as part of bootstrap template. 
        Inserts/Updates Settings table based upon the resources deployed inside bootstrap template
        We use these settings inside tenant template

    Args:
            event ([type]): [description]
            _ ([type]): [description]
    """
    logger.info("Updating settings")

    settings_table_name = event['ResourceProperties']['SettingsTableName']
    cognitoUserPoolId = event['ResourceProperties']['cognitoUserPoolId']
    cognitoUserPoolClientId = event['ResourceProperties']['cognitoUserPoolClientId']

    table_system_settings = dynamodb.Table(settings_table_name)

    response = table_system_settings.put_item(
            Item={
                    'settingName': 'userPoolId-pooled',
                    'settingValue' : cognitoUserPoolId
                }
            )

    response = table_system_settings.put_item(
            Item={
                    'settingName': 'appClientId-pooled',
                    'settingValue' : cognitoUserPoolClientId
                }
            )

@helper.delete
def do_nothing(_, __):
    pass

def generate_manual_success_command(event):
    """Generate curl command for manual SUCCESS signal if needed for recovery"""
    response_url = event.get('ResponseURL', '')
    request_id = event.get('RequestId', '')
    stack_id = event.get('StackId', '')
    logical_resource_id = event.get('LogicalResourceId', '')
    physical_resource_id = event.get('PhysicalResourceId', 'CustomResource')
    
    curl_command = (
        f'curl -H "Content-Type: \'\'" -X PUT -d '
        f'"{{\\\"Status\\\": \\\"SUCCESS\\\",'
        f'\\\"PhysicalResourceId\\\": \\\"{physical_resource_id}\\\",'
        f'\\\"StackId\\\": \\\"{stack_id}\\\",'
        f'\\\"RequestId\\\": \\\"{request_id}\\\",'
        f'\\\"LogicalResourceId\\\": \\\"{logical_resource_id}\\\"}}" '
        f'"{response_url}"'
    )
    return curl_command

def handler(event, context):
    # Log the full event for troubleshooting stuck custom resources
    # This enables manual recovery via ResponseURL if needed
    logger.info("Received event: " + json.dumps(event, indent=2))
    
    # Log manual recovery command for all request types (Create, Update, Delete)
    # Custom resources can get stuck in any of these states
    recovery_command = generate_manual_success_command(event)
    logger.info("Manual recovery command (if needed):")
    logger.info(recovery_command)
    
    helper(event, context)
        
    