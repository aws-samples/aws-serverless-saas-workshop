# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import time
import os
from datetime import datetime, timedelta
import logger

number_of_hours = int(os.environ['NUMBER_OF_HOURS'])

cloudformation = boto3.client('cloudformation')
logs = boto3.client('logs')

def aggregate_dynamodb_capacity_units_by_tenant(event, context):
    
    log_group_names = __get_list_of_log_group_names()
    
    time_zone = datetime.now().astimezone().tzinfo
    start_time = int((datetime.now(tz=time_zone) - timedelta(hours=number_of_hours)).timestamp())
    end_time = int(time.time())

    capacity_units_query = 'fields @timestamp, @message \
    | filter @message like /ReadCapacityUnits|WriteCapacityUnits/ \
    | fields tenant_id as TenantId, service as Service, \
     ReadCapacityUnits.0 as RCapacityUnits, WriteCapacityUnits.0 as WCapacityUnits \
    | stats sum(RCapacityUnits) as ReadCapacityUnits, sum(WCapacityUnits) as WriteCapacityUnits by TenantId, dateceil(@timestamp, 1h) as timestamp'

    logger.info( log_group_names)
    
    capacity_units = __query_cloudwatch_logs(logs,  log_group_names, 
    capacity_units_query, start_time, end_time)

    logger.info(capacity_units)

    

def aggregate_lambda_invocations_by_tenant(event, context):
    log_group_names = __get_list_of_log_group_names()
    
    time_zone = datetime.now().astimezone().tzinfo
    start_time = int((datetime.now(tz=time_zone) - timedelta(hours=number_of_hours)).timestamp())
    end_time = int(time.time())

    logger.info(log_group_names)
    
    query_string='fields @timestamp, @message \
        | filter @message like /Request completed/ \
        | fields tenant_id as TenantId, service as Service \
        | stats count (TenantId) as LambdaInvocation by TenantId, Service, dateceil(@timestamp, 1h) as timestamp'
    query_results = __query_cloudwatch_logs(logs, log_group_names, query_string, start_time, end_time)

    logger.info(query_results) 


def __query_cloudwatch_logs(logs, log_group_names, query_string, start_time, end_time):
    query = logs.start_query(logGroupNames=log_group_names,
    startTime=start_time,
    endTime=end_time,
    queryString=query_string)

    query_results = logs.get_query_results(queryId=query["queryId"])

    while query_results['status']=='Running' or query_results['status']=='Scheduled':
        time.sleep(5)
        query_results = logs.get_query_results(queryId=query["queryId"])

    return query_results

def __is_log_group_exists(logs_client, log_group_name):
    
    logs_paginator = logs_client.get_paginator('describe_log_groups')
    response_iterator = logs_paginator.paginate(logGroupNamePrefix=log_group_name)
    for log_groups_list in response_iterator:
        if not log_groups_list["logGroups"]:
            return False
        else:
            return True       

def __add_log_group_name(logs_client, log_group_name, log_group_names_list):

    if __is_log_group_exists(logs_client, log_group_name):
        log_group_names_list.append(log_group_name)


def __get_list_of_log_group_names():
    log_group_names = []
    log_group_prefix = '/aws/lambda/'
    cloudformation_paginator = cloudformation.get_paginator('list_stack_resources')
    response_iterator = cloudformation_paginator.paginate(StackName='stack-pooled')
    for stack_resources in response_iterator:
        for resource in stack_resources['StackResourceSummaries']:
            if (resource["LogicalResourceId"] == "CreateProductFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names)
                continue    
            if (resource["LogicalResourceId"] == "UpdateProductFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue
            if (resource["LogicalResourceId"] == "GetProductsFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names)
                continue
            if (resource["LogicalResourceId"] == "DeleteProductFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue         
            if (resource["LogicalResourceId"] == "CreateOrderFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue
            if (resource["LogicalResourceId"] == "UpdateOrderFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue
            if (resource["LogicalResourceId"] == "GetOrdersFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue
            if (resource["LogicalResourceId"] == "DeleteOrderFunction"):
                __add_log_group_name(logs, ''.join([log_group_prefix,resource["PhysicalResourceId"]]), 
                 log_group_names) 
                continue 

    return log_group_names                     

