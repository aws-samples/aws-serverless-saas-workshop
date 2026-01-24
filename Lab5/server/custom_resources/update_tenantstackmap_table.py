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
    """ One time entry for pooled tenants inside tenant stack mapping table.
        This ensures that when code pipeline for tenant template is kicked off, it always create a default stack for pooled tenants.
    Args:
        event ([type]): [description]
        _ ([type]): [description]
    """
    logger.info("Updating Tenant Stack Map")

    tenantstackmap_table_name = event['ResourceProperties']['TenantStackMappingTableName']
    
    table_stack_mapping = dynamodb.Table(tenantstackmap_table_name)
    
    response = table_stack_mapping.put_item(
            Item={
                    'tenantId': 'pooled',
                    'stackName' : 'stack-lab5-pooled',
                    'applyLatestRelease': True,
                    'codeCommitId': ''
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
        
    