from replace_function import replace_in_file

lab2_tenant_mgmt_original_str = """#TODO: Implement the below method
def get_tenant(event, context):
    pass
"""

lab2_tenant_mgmt_update_str = """def get_tenant(event, context):
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
"""

replace_in_file(lab2_tenant_mgmt_original_str, lab2_tenant_mgmt_update_str, "../Lab2/server/TenantManagementService/tenant-management.py")

lab2_user_mgmt_original_str = """#TODO: Implement the below method
def create_user(event, context):
    pass
"""

lab2_user_mgmt_update_str = """def create_user(event, context):
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
"""

replace_in_file(lab2_user_mgmt_original_str, lab2_user_mgmt_update_str, "../Lab2/server/TenantManagementService/user-management.py")

lab2_registration_svc_original_str = """#TODO: Implement this method
def register_tenant(event, context):
    pass
"""

lab2_registration_svc_update_str = """def register_tenant(event, context):
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

        logger.info (create_user_response)
        tenant_details['tenantAdminUserName'] = create_user_response['message']['tenantAdminUserName']

        create_tenant_response = __create_tenant(tenant_details, headers, auth, host, stage_name)
        logger.info (create_tenant_response)

    except Exception as e:
        logger.error('Error registering a new tenant')
        raise Exception('Error registering a new tenant', e)
    else:
        return utils.create_success_response("You have been registered in our system")
"""

replace_in_file(lab2_registration_svc_original_str, lab2_registration_svc_update_str, "../Lab2/server/TenantManagementService/tenant-registration.py")
