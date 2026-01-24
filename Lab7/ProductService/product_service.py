# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import os
import boto3
from decimal import Decimal
from aws_lambda_powertools import Logger, Tracer
from botocore.exceptions import ClientError

# Initialize PowerTools
logger = Logger()
tracer = Tracer()
tracer.patch(['boto3'])

# DynamoDB setup
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Product-pooled-lab7')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

@tracer.capture_lambda_handler
def create_product(event, context):
    """Create a new product with consumed capacity tracking"""
    tenant_id = 'pooled'
    tracer.put_annotation(key="TenantId", value=tenant_id)
    
    logger.info("Request received to create a product", extra={"tenant_id": tenant_id})
    
    # Extract product details from event
    product_id = event.get('productId', 'prod-123')
    product_name = event.get('productName', 'Sample Product')
    price = Decimal(str(event.get('price', 99.99)))
    
    try:
        # Put item with consumed capacity tracking
        response = table.put_item(
            Item={
                'productId': product_id,
                'productName': product_name,
                'price': price,
                'tenantId': tenant_id
            },
            ReturnConsumedCapacity='TOTAL'
        )
        
        # Extract consumed capacity
        consumed_capacity = response.get('ConsumedCapacity', {})
        consumed_wcu = consumed_capacity.get('CapacityUnits', 0)
        
        # Log completion with structured data for cost attribution
        logger.info(
            "Request completed",
            extra={
                "tenant_id": tenant_id,
                "consumed_rcu": 0,  # Write operation
                "consumed_wcu": consumed_wcu,
                "operation": "create_product"
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product created',
                'productId': product_id
            })
        }
        
    except ClientError as e:
        logger.error("Error creating product", extra={
            "tenant_id": tenant_id,
            "error": str(e)
        })
        raise

@tracer.capture_lambda_handler
def update_product(event, context):
    """Update an existing product with consumed capacity tracking"""
    tenant_id = 'pooled'
    tracer.put_annotation(key="TenantId", value=tenant_id)
    
    logger.info("Request received to update a product", extra={"tenant_id": tenant_id})
    
    # Extract product details from event
    product_id = event.get('productId', 'prod-123')
    product_name = event.get('productName', 'Updated Product')
    price = Decimal(str(event.get('price', 149.99)))
    
    try:
        # Update item with consumed capacity tracking
        response = table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET productName = :name, price = :price',
            ExpressionAttributeValues={
                ':name': product_name,
                ':price': price
            },
            ReturnConsumedCapacity='TOTAL'
        )
        
        # Extract consumed capacity
        consumed_capacity = response.get('ConsumedCapacity', {})
        consumed_wcu = consumed_capacity.get('CapacityUnits', 0)
        
        # Log completion with structured data for cost attribution
        logger.info(
            "Request completed",
            extra={
                "tenant_id": tenant_id,
                "consumed_rcu": 0,  # Write operation
                "consumed_wcu": consumed_wcu,
                "operation": "update_product"
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product updated',
                'productId': product_id
            })
        }
        
    except ClientError as e:
        logger.error("Error updating product", extra={
            "tenant_id": tenant_id,
            "error": str(e)
        })
        raise

@tracer.capture_lambda_handler
def get_products(event, context):
    """Get all products with consumed capacity tracking"""
    tenant_id = 'pooled'
    tracer.put_annotation(key="TenantId", value=tenant_id)
    
    logger.info("Request received to get all products", extra={"tenant_id": tenant_id})
    
    try:
        # Scan for products with consumed capacity tracking
        response = table.scan(
            ReturnConsumedCapacity='TOTAL'
        )
        
        # Extract consumed capacity
        consumed_capacity = response.get('ConsumedCapacity', {})
        consumed_rcu = consumed_capacity.get('CapacityUnits', 0)
        
        # Log completion with structured data for cost attribution
        logger.info(
            "Request completed",
            extra={
                "tenant_id": tenant_id,
                "consumed_rcu": consumed_rcu,
                "consumed_wcu": 0,  # Read operation
                "operation": "get_products"
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'products': response.get('Items', [])
            }, cls=DecimalEncoder)
        }
        
    except ClientError as e:
        logger.error("Error getting products", extra={
            "tenant_id": tenant_id,
            "error": str(e)
        })
        raise
