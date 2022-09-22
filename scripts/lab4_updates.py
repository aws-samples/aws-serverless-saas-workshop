from replace_function import replace_in_file

lab4_tenant_auth_original_str = """    #TODO : Add code for Fine-Grained-Access-Control"""

lab4_tenant_auth_update_str = """    iam_policy = auth_manager.getPolicyForUser(user_role, utils.Service_Identifier.BUSINESS_SERVICES.value, tenant_id, region, aws_account_id)
    logger.info(iam_policy)

    role_arn = "arn:aws:iam::{}:role/authorizer-access-role".format(aws_account_id)

    assumed_role = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName="tenant-aware-session",
        Policy=iam_policy,
    )
    credentials = assumed_role["Credentials"]
    #pass sts credentials to lambda
    context = {
        'accesskey': credentials['AccessKeyId'], # $context.authorizer.key -> value
        'secretkey' : credentials['SecretAccessKey'],
        'sessiontoken' : credentials["SessionToken"],
        'userName': user_name,
        'tenantId': tenant_id,
        'userPoolId': userpool_id,
        'userRole': user_role
    }

    authResponse['context'] = context
"""

replace_in_file(lab4_tenant_auth_original_str, lab4_tenant_auth_update_str, "../Lab4/server/Resources/tenant_authorizer.py")

lab4_product_original_str = """    #TODO: Implement this method"""

lab4_product_update_str = """    accesskey = event['requestContext']['authorizer']['accesskey']
    secretkey = event['requestContext']['authorizer']['secretkey']
    sessiontoken = event['requestContext']['authorizer']['sessiontoken']
    dynamodb = boto3.resource('dynamodb',
                aws_access_key_id=accesskey,
                aws_secret_access_key=secretkey,
                aws_session_token=sessiontoken
                )

    return dynamodb.Table(table_name)
"""

replace_in_file(lab4_product_original_str, lab4_product_update_str, "../Lab4/server/ProductService/product_service_dal.py")
replace_in_file(lab4_product_original_str, lab4_product_update_str, "../Lab4/server/OrderService/order_service_dal.py")
