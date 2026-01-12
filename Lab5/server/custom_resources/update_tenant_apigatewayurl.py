import json
import boto3
import logger
from boto3.dynamodb.conditions import Key
from crhelper import CfnResource
helper = CfnResource()

try:
    client = boto3.client('dynamodb')
    dynamodb = boto3.resource('dynamodb')
except Exception as e:
    helper.init_failure(e)
    
@helper.create
@helper.update
def do_action(event, _):
    """ The URL for Tenant APIs(Product/Order) can differ by tenant.
        For Pooled tenants it is shared and for Silo (Platinum tier tenants) it is unique to them.
        This method keeps the URL for Pooled tenants inside Settings Table, since it is shared across multiple tenants,
        And for Silo tenants inside the tenant management table along with other tenant settings, for that tenant

    Args:
        event ([type]): [description]
        _ ([type]): [description]
    """
    logger.info("Updating Tenant Details table")

    tenant_details_table_name = event['ResourceProperties']['TenantDetailsTableName']
    settings_table_name = event['ResourceProperties']['SettingsTableName']
    tenant_id = event['ResourceProperties']['TenantId']
    tenant_api_gateway_url = event['ResourceProperties']['TenantApiGatewayUrl']


    if(tenant_id.lower() =='pooled'):
        # Note: Tenant management service will use below setting to update apiGatewayUrl for pooled tenants in TenantDetails table
        settings_table = dynamodb.Table(settings_table_name)
        settings_table.put_item(Item={
                    'settingName': 'apiGatewayUrl-Pooled',
                    'settingValue' : tenant_api_gateway_url                    
                })
        
    else:
        tenant_details = dynamodb.Table(tenant_details_table_name)
        response = tenant_details.update_item(
            Key={'tenantId': tenant_id},
            UpdateExpression="set apiGatewayUrl=:apiGatewayUrl",
            ExpressionAttributeValues={
            ':apiGatewayUrl': tenant_api_gateway_url
            },
            ReturnValues="NONE") 
                   
    
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
        
    