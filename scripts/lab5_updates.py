from replace_function import replace_in_file

lab5_user_mgmt_original_str = """        #TODO: add code to provision new user pool
        pass
"""

lab5_user_mgmt_update_str = """        user_pool_response = user_mgmt.create_user_pool(tenant_id)
        user_pool_id = user_pool_response['UserPool']['Id']
        logger.info (user_pool_id)

        app_client_response = user_mgmt.create_user_pool_client(user_pool_id)
        logger.info(app_client_response)
        app_client_id = app_client_response['UserPoolClient']['ClientId']
        user_pool_domain_response = user_mgmt.create_user_pool_domain(user_pool_id, tenant_id)

        logger.info ("New Tenant Created")
"""

replace_in_file(lab5_user_mgmt_original_str, lab5_user_mgmt_update_str, "../Lab5/server/TenantManagementService/user-management.py")

lab5_tenant_prov_original_str = """        #TODO: Add missing code to kick off the pipeline
        pass
"""

lab5_tenant_prov_update_str = """        response_ddb = table_tenant_stack_mapping.put_item(
            Item={
                    'tenantId': tenant_details['tenantId'],
                    'stackName': stack_name.format(tenant_details['tenantId']),
                    'applyLatestRelease': True,
                    'codeCommitId': ''
                }
            )

        logger.info(response_ddb)

        response_codepipeline = codepipeline.start_pipeline_execution(
            name='serverless-saas-pipeline'
        )

        logger.info(response_ddb)
"""
replace_in_file(lab5_tenant_prov_original_str, lab5_tenant_prov_update_str, "../Lab5/server/TenantManagementService/tenant-provisioning.py")
