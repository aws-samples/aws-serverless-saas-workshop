from replace_function import replace_in_file

lab6_tenant_reg_original_str = """        #TODO: Pass relevant apikey to tenant_details object based upon tenant tier
        if (tenant_details['tenantTier'].upper() == utils.TenantTier.PLATINUM.value.upper()):
            tenant_details['dedicatedTenancy'] = 'true'
"""

lab6_tenant_reg_update_str = """        if (tenant_details['tenantTier'].upper() == utils.TenantTier.PLATINUM.value.upper()):
            tenant_details['dedicatedTenancy'] = 'true'
            api_key = platinum_tier_api_key
        elif (tenant_details['tenantTier'].upper() == utils.TenantTier.PREMIUM.value.upper()):
            api_key = premium_tier_api_key
        elif (tenant_details['tenantTier'].upper() == utils.TenantTier.STANDARD.value.upper()):
            api_key = standard_tier_api_key
        elif (tenant_details['tenantTier'].upper() == utils.TenantTier.BASIC.value.upper()):
            api_key = basic_tier_api_key

        tenant_details['apiKey'] = api_key
"""

replace_in_file(lab6_tenant_reg_original_str, lab6_tenant_reg_update_str, "../Lab6/server/TenantManagementService/tenant-registration.py")

lab6_tenant_mgmt_original_str = """#'apiKey': tenant_details['apiKey'],"""
lab6_tenant_mgmt_update_str   = """'apiKey': tenant_details['apiKey'],"""

replace_in_file(lab6_tenant_mgmt_original_str, lab6_tenant_mgmt_update_str, "../Lab6/server/TenantManagementService/tenant-management.py")

lab6_tenant_auth_original_str = """        #TODO: Get API Key from tenant management table
        #api_key = tenant_details['Item']['apiKey']
"""
lab6_tenant_auth_update_str = """        api_key = tenant_details['Item']['apiKey']"""

replace_in_file(lab6_tenant_auth_original_str, lab6_tenant_auth_update_str, "../Lab6/server/Resources/tenant_authorizer.py")

lab6_tenant_auth_original_str_2 = """        #TODO: Assign API Key to authorizer response
        #'apiKey': api_key,
"""
lab6_tenant_auth_update_str_2 = """        'apiKey': api_key,"""

replace_in_file(lab6_tenant_auth_original_str_2, lab6_tenant_auth_update_str_2, "../Lab6/server/Resources/tenant_authorizer.py")

