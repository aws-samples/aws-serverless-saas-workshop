# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

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

table_name = os.environ['ORDER_TABLE_NAME']
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(table_name)

def get_order(event, orderId):
    
    try:
        response = table.get_item(Key={'orderId': orderId})
        item = response['Item']
        order = Order(item['orderId'], item['orderName'], item['orderProducts'])

    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error getting a order', e)
    else:
        return order

def delete_order(event, orderId):
    
    try:
        response = table.delete_item(Key={'orderId': orderId})
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error deleting a order', e)
    else:
        logger.info("DeleteItem succeeded:")
        return response


def create_order(event, payload):
    
    order = Order(str(uuid.uuid4()), payload.orderName, payload.orderProducts)

    try:
        response = table.put_item(Item={
        'orderId': order.orderId, 
        'orderName': order.orderName,
        'orderProducts': get_order_products_dict(order.orderProducts)
        })
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error adding a order', e)
    else:
        logger.info("PutItem succeeded:")
        return order

def update_order(event, payload, orderId):
    
    try:
        order = Order(orderId,payload.orderName, payload.orderProducts)
        response = table.update_item(Key={'orderId': order.orderId},
        UpdateExpression="set orderName=:orderName, "
        +"orderProducts=:orderProducts",
        ExpressionAttributeValues={
            ':orderName': order.orderName,
            ':orderProducts': get_order_products_dict(order.orderProducts)
        },
        ReturnValues="UPDATED_NEW")
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        raise Exception('Error updating a order', e)
    else:
        logger.info("UpdateItem succeeded:")
        return order

def get_orders(event):
    orders = []

    try:
        response = table.scan()    
        if (len(response['Items']) > 0):
            for item in response['Items']:
                order = Order(item['orderId'], item['orderName'], item['orderProducts'])
                orders.append(order)
    except ClientError as e:
        logger.error("Error getting all orders")
        raise Exception('Error getting all orders', e) 
    else:
        logger.info("Get orders succeeded")
        return orders


def get_order_products_dict(orderProducts):
    orderProductList = []
    for i in range(len(orderProducts)):
        product = orderProducts[i]
        orderProductList.append(vars(product))
    return orderProductList    

  

