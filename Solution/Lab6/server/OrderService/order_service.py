# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import utils
import logger
import metrics_manager
import order_service_dal
from decimal import Decimal
from types import SimpleNamespace
from aws_lambda_powertools import Tracer
tracer = Tracer()

@tracer.capture_lambda_handler
def get_order(event, context):
    tenantId = context.tenant_id
    tracer.put_annotation(key="TenantId", value=tenantId)

    logger.log_with_tenant_context(tenantId, "Request received to get a order")
    params = event['pathParameters']
    key = params['id']
    logger.log_with_tenant_context(tenantId, params)
    order = order_service_dal.get_order(event, key, tenantId)

    logger.log_with_tenant_context(tenantId, "Request completed to get a order")
    metrics_manager.record_metric(tenantId, "SingleOrderRequested", "Count", 1)
    return utils.generate_response(order)
    
@tracer.capture_lambda_handler
def create_order(event, context):  
    tenantId = context.tenant_id
    tracer.put_annotation(key="TenantId", value=tenantId)

    logger.log_with_tenant_context(tenantId, "Request received to create a order")
    payload = json.loads(event['body'], object_hook=lambda d: SimpleNamespace(**d), parse_float=Decimal)
    order = order_service_dal.create_order(event, payload, tenantId)
    logger.log_with_tenant_context(tenantId, "Request completed to create a order")
    metrics_manager.record_metric(tenantId, "OrderCreated", "Count", 1)
    return utils.generate_response(order)
    
@tracer.capture_lambda_handler
def update_order(event, context):
    tenantId = context.tenant_id
    tracer.put_annotation(key="TenantId", value=tenantId)
    
    logger.log_with_tenant_context(tenantId, "Request received to update a order")
    payload = json.loads(event['body'], object_hook=lambda d: SimpleNamespace(**d), parse_float=Decimal)
    params = event['pathParameters']
    key = params['id']
    order = order_service_dal.update_order(event, payload, key, tenantId)
    logger.log_with_tenant_context(tenantId, "Request completed to update a order") 
    metrics_manager.record_metric(tenantId, "OrderUpdated", "Count", 1)   
    return utils.generate_response(order)

@tracer.capture_lambda_handler
def delete_order(event, context):
    tenantId = context.tenant_id
    tracer.put_annotation(key="TenantId", value=tenantId)

    logger.log_with_tenant_context(tenantId, "Request received to delete a order")
    params = event['pathParameters']
    key = params['id']
    response = order_service_dal.delete_order(event, key, tenantId)
    logger.log_with_tenant_context(tenantId, "Request completed to delete a order")
    metrics_manager.record_metric(tenantId, "OrderDeleted", "Count", 1)
    return utils.create_success_response("Successfully deleted the order")

@tracer.capture_lambda_handler
def get_orders(event, context):
    tenantId = context.tenant_id
    tracer.put_annotation(key="TenantId", value=tenantId)
    
    logger.log_with_tenant_context(tenantId, "Request received to get all orders")
    response = order_service_dal.get_orders(event, tenantId)
    metrics_manager.record_metric(tenantId, "OrdersRetrieved", "Count", len(response))
    logger.log_with_tenant_context(tenantId, "Request completed to get all orders")
    return utils.generate_response(response)

  