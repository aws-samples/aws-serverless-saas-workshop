# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from pprint import pprint
import os
import boto3
from botocore.exceptions import ClientError
import uuid
from order_models import Order
import json
import utils
from types import SimpleNamespace
import logger
import random
import threading
from boto3.dynamodb.conditions import Key
import metrics_manager

table_name = os.environ['ORDER_TABLE_NAME']

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(table_name)

suffix_start = 1 
suffix_end = 10
 
def get_order(event, key):
    
    try:
        shardId = key.split(":")[0]
        orderId = key.split(":")[1] 
        logger.log_with_tenant_context(event, shardId)
        logger.log_with_tenant_context(event, orderId)
        response = table.get_item(Key={'shardId': shardId, 'orderId': orderId}, ReturnConsumedCapacity='TOTAL')
        item = response['Item']
        order = Order(item['shardId'], item['orderId'], item['orderName'], item['orderProducts'])

        metrics_manager.record_metric(event, "ReadCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])

    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error getting a order', e)
    else:
        return order

def delete_order(event, key):
    
    try:
        shardId = key.split(":")[0]
        orderId = key.split(":")[1] 
        response = table.delete_item(Key={'shardId':shardId, 'orderId': orderId}, ReturnConsumedCapacity='TOTAL')

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error deleting a order', e)
    else:
        logger.info("DeleteItem succeeded:")
        return response


def create_order(event, payload):
    tenantId = event['requestContext']['authorizer']['tenantId']
    suffix = random.randrange(suffix_start, suffix_end)
    shardId = tenantId+"-"+str(suffix)
    
    order = Order(shardId, str(uuid.uuid4()), payload.orderName, payload.orderProducts)

    try:
        response = table.put_item(Item={
        'shardId':shardId,
        'orderId': order.orderId, 
        'orderName': order.orderName,
        'orderProducts': get_order_products_dict(order.orderProducts)
        }, ReturnConsumedCapacity='TOTAL')

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error adding a order', e)
    else:
        logger.info("PutItem succeeded:")
        return order

def update_order(event, payload, key):
    
    try:
        shardId = key.split(":")[0]
        orderId = key.split(":")[1] 
        logger.log_with_tenant_context(event, shardId)
        logger.log_with_tenant_context(event, orderId)
        order = Order(shardId, orderId,payload.orderName, payload.orderProducts)
        response = table.update_item(Key={'shardId':order.shardId, 'orderId': order.orderId},
        UpdateExpression="set orderName=:orderName, "
        +"orderProducts=:orderProducts",
        ExpressionAttributeValues={
            ':orderName': order.orderName,
            ':orderProducts': get_order_products_dict(order.orderProducts)
        },
        ReturnValues="UPDATED_NEW",
        ReturnConsumedCapacity='TOTAL')

        metrics_manager.record_metric(event, "WriteCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error updating a order', e)
    else:
        logger.info("UpdateItem succeeded:")
        return order

def get_orders(event, tenantId):
    get_all_products_response = []

    try:
        __query_all_partitions(tenantId,get_all_products_response, table, event)
    except ClientError as e:
        logger.error("Error getting all orders")
        raise Exception('Error getting all orders', e) 
    else:
        logger.info("Get orders succeeded")
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
            order = Order(item['shardId'], item['orderId'], item['orderName'], item['orderProducts'])
            get_all_products_response.append(order)

    metrics_manager.record_metric(event, "ReadCapacityUnits", "Count", response['ConsumedCapacity']['CapacityUnits'])        


def get_order_products_dict(orderProducts):
    orderProductList = []
    for i in range(len(orderProducts)):
        product = orderProducts[i]
        orderProductList.append(vars(product))
    return orderProductList    

  

