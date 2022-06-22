from replace_function import replace_in_file

lab3_tenant_auth_original_str = """    # TODO: Add tenant context to authResponse"""

lab3_tenant_auth_update_str = """    context = {
        'userName': user_name,
        'tenantId': tenant_id
    }

    authResponse['context'] = context
"""

replace_in_file(lab3_tenant_auth_original_str, lab3_tenant_auth_update_str, "../Lab3/server/Resources/tenant_authorizer.py")

lab3_shared_svc_original_str = """    #TODO: Add policy so that only tenant and SaaS admins can add/modify tenant information"""

lab3_shared_svc_update_str = """    if (auth_manager.isTenantAdmin(user_role) or auth_manager.isSystemAdmin(user_role)):
        policy.allowAllMethods()
        if (auth_manager.isTenantAdmin(user_role)):
            policy.denyMethod(HttpVerb.POST, "tenant-activation")
            policy.denyMethod(HttpVerb.GET, "tenants")
    else:
        #if not tenant admin or system admin then only allow to get info and update info
        policy.allowMethod(HttpVerb.GET, "user/*")
        policy.allowMethod(HttpVerb.PUT, "user/*")
"""

replace_in_file(lab3_shared_svc_original_str, lab3_shared_svc_update_str, "../Lab3/server/Resources/shared_service_authorizer.py")

lab3_layer_original_str = """#TODO: Implement the below method
def record_metric(event, metric_name, metric_unit, metric_value):
    pass
"""

lab3_layer_update_str = """def record_metric(event, metric_name, metric_unit, metric_value):
    \"\"\"Record the metric in Cloudwatch using EMF format

    Args:
        event ([type]): [description]
        metric_name ([type]): [description]
        metric_unit ([type]): [description]
        metric_value ([type]): [description]
    \"\"\"
    metrics.add_dimension(name="tenant_id", value=event['requestContext']['authorizer']['tenantId'])
    metrics.add_metric(name=metric_name, unit=metric_unit, value=metric_value)
    metrics_object = metrics.serialize_metric_set()
    metrics.clear_metrics()
    print(json.dumps(metrics_object))

"""

replace_in_file(lab3_layer_original_str, lab3_layer_update_str, "../Lab3/server/layers/metrics_manager.py")

lab3_product_original_str = """#TODO: Implement this method
def create_product(event, payload):
    pass
"""

lab3_product_update_str = """def create_product(event, payload):
    tenantId = event['requestContext']['authorizer']['tenantId']

    suffix = random.randrange(suffix_start, suffix_end)
    shardId = tenantId+"-"+str(suffix)

    product = Product(shardId, str(uuid.uuid4()), payload.sku,payload.name, payload.price, payload.category)

    try:
        response = table.put_item(
            Item=
                {
                    'shardId': shardId,
                    'productId': product.productId,
                    'sku': product.sku,
                    'name': product.name,
                    'price': product.price,
                    'category': product.category
                }
        )
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error adding a product', e)
    else:
        logger.info("PutItem succeeded:")
        return product
"""
replace_in_file(lab3_product_original_str, lab3_product_update_str, "../Lab3/server/ProductService/product_service_dal.py")