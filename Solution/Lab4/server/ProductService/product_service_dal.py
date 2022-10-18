# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from pprint import pprint
import os
import boto3
from botocore.exceptions import ClientError
import uuid
import json
import logger
import random
import threading
import metrics_manager

from product_models import Product
from types import SimpleNamespace
from boto3.dynamodb.conditions import Key

table_name = os.environ['PRODUCT_TABLE_NAME']

dynamodb = None

suffix_start = 1 
suffix_end = 10

def get_product(event, key):  
    table = __get_dynamodb_table(event, dynamodb)  
    try:
        shardId = key.split(":")[0]
        productId = key.split(":")[1] 
        logger.log_with_tenant_context(event, shardId)
        logger.log_with_tenant_context(event, productId)
        response = table.get_item(Key={'shardId': shardId, 'productId': productId}, ReturnConsumedCapacity='TOTAL')
        item = response['Item']
        product = Product(item['shardId'], item['productId'], item['sku'], item['name'], item['price'], item['category'])

        metrics_manager.record_metric(event, "ReadCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error getting a product', e)
    else:
        logger.info("GetItem succeeded:"+ str(product))
        return product

def delete_product(event, key):    
    table = __get_dynamodb_table(event, dynamodb)
    try:
        shardId = key.split(":")[0]
        productId = key.split(":")[1] 
        response = table.delete_item(Key={'shardId':shardId, 'productId': productId}, ReturnConsumedCapacity='TOTAL')

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error deleting a product', e)
    else:
        logger.info("DeleteItem succeeded:")
        return response


def create_product(event, payload):
    tenantId = event['requestContext']['authorizer']['tenantId']  
    table = __get_dynamodb_table(event, dynamodb)  
    
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
                }, ReturnConsumedCapacity='TOTAL'
        )

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error adding a product', e)
    else:
        logger.info("PutItem succeeded:")
        return product

def update_product(event, payload, key):    
    table = __get_dynamodb_table(event, dynamodb)
    try:
        shardId = key.split(":")[0]
        productId = key.split(":")[1] 
        logger.log_with_tenant_context(event, shardId)
        logger.log_with_tenant_context(event, productId)

        product = Product(shardId,productId,payload.sku, payload.name, payload.price, payload.category)

        response = table.update_item(Key={'shardId':product.shardId, 'productId': product.productId},
        UpdateExpression="set sku=:sku, #n=:productName, price=:price, category=:category",
        ExpressionAttributeNames= {'#n':'name'},
        ExpressionAttributeValues={
            ':sku': product.sku,
            ':productName': product.name,
            ':price': product.price,
            ':category': product.category
        },
        ReturnValues="UPDATED_NEW", ReturnConsumedCapacity='TOTAL')

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error updating a product', e)
    else:
        logger.info("UpdateItem succeeded:")
        return product        

def get_products(event, tenantId):
    table = __get_dynamodb_table(event, dynamodb)    
    get_all_products_response =[]
    try:
        __query_all_partitions(tenantId,get_all_products_response, table, event)
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error getting all products', e)
    else:
        logger.info("Get products succeeded")
        return get_all_products_response

def __query_all_partitions(tenantId,get_all_products_response, table, event):
    threads = []    
    
    for suffix in range(suffix_start, suffix_end):
        partition_id = tenantId+'-'+str(suffix)
        
        thread = threading.Thread(target=__get_tenant_data, args=[partition_id, get_all_products_response, table, event])
        threads.append(thread)
        
    # Start threads
    for thread in threads:
        thread.start()
    # Ensure all threads are finished
    for thread in threads:
        thread.join()
           
def __get_tenant_data(partition_id, get_all_products_response, table, event):    
    logger.info(partition_id)
    response = table.query(KeyConditionExpression=Key('shardId').eq(partition_id), ReturnConsumedCapacity='TOTAL')    
    if (len(response['Items']) > 0):
        for item in response['Items']:
            product = Product(item['shardId'], item['productId'], item['sku'], item['name'], item['price'], item['category'])
            get_all_products_response.append(product)

    metrics_manager.record_metric(event, "ReadCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])        

def __get_dynamodb_table(event, dynamodb):
    """ 

    Args:
        event ([type]): [description]

    Returns:
        [type]: [description]
    """
    accesskey = event['requestContext']['authorizer']['accesskey']
    secretkey = event['requestContext']['authorizer']['secretkey']
    sessiontoken = event['requestContext']['authorizer']['sessiontoken']    
    dynamodb = boto3.resource('dynamodb',
                aws_access_key_id=accesskey,
                aws_secret_access_key=secretkey,
                aws_session_token=sessiontoken
                )        
        
    return dynamodb.Table(table_name)