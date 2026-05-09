# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import time
import os
from datetime import datetime, timedelta
from botocore.exceptions import ClientError
from decimal import *

cloudformation = boto3.client('cloudformation')
logs = boto3.client('logs')
athena = boto3.client('athena')
dynamodb = boto3.resource('dynamodb')
attribution_table = dynamodb.Table("TenantCostAndUsageAttribution-lab7")

ATHENA_S3_OUTPUT = os.getenv("ATHENA_S3_OUTPUT")
RETRY_COUNT = 100


# This function needs to be scheduled on daily basis
def calculate_daily_dynamodb_attribution_by_tenant(event, context):
    start_date_time = __get_start_date_time()  # current day epoch
    end_date_time = __get_end_date_time()  # next day epoch
    print("Processing attribution for current day")

    # TODO: Get total cost of DynamoDB for the current date
    total_dynamodb_cost = Decimal('0.0')

    log_group_names = __get_list_of_log_group_names()
    print(log_group_names)

    # Check if log groups exist before querying
    if not log_group_names or len(log_group_names) == 0:
        print("No log groups found. Skipping DynamoDB cost attribution.")
        return

    # Use filter_log_events API instead of Logs Insights for accurate counting.
    # Logs Insights has an indexing limitation where cold start logs may not be indexed.
    # TODO: Get DynamoDB usage by tenant using filter_log_events API
    tenant_usage, total_RCU, total_WCU = None, Decimal('0.0'), Decimal('0.0')

    # TODO: Save the tenant attribution data inside a dynamodb table
    pass


# Below function considers number of invocation as the metrics to calculate usage and cost.
# You can go granluar by recording duration of each metrics and use that to get more granular.
# Since our functions are basic CRUD this might work as a ball park cost estimate.
def calculate_daily_lambda_attribution_by_tenant(event, context):
    start_date_time = __get_start_date_time()  # current day epoch
    end_date_time = __get_end_date_time()  # next day epoch
    print("Processing attribution for current day")

    # Get total Lambda cost for the given duration
    total_lambda_cost = __get_total_service_cost('AWSLambda', start_date_time, end_date_time)

    log_group_names = __get_list_of_log_group_names()

    # Check if log groups exist before querying
    if not log_group_names or len(log_group_names) == 0:
        print("No log groups found. Skipping Lambda cost attribution.")
        return

    # Use filter_log_events API instead of Logs Insights for accurate counting.
    # Logs Insights has an indexing limitation where cold start logs may not be indexed.
    # TODO: Get Lambda invocations by tenant using filter_log_events API
    tenant_invocations, total_invocations = None, 0
    pass


def __get_total_service_cost(servicename, start_date_time, end_date_time):

    # We need to add more filters for day, month, year, resource ids etc. Below query is because we are just using a sample cur file
    # Ignoring startTime and endTime filter for now since we have a static/sample cur file

    query = "SELECT sum(line_item_blended_cost) AS cost FROM curoutput WHERE line_item_product_code='{0}'".format(servicename)

    # Execution
    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={
            'Database': 'costexplorerdb-lab7'
        },
        ResultConfiguration={
            'OutputLocation': "s3://" + ATHENA_S3_OUTPUT,
        }
    )

    # get query execution id
    query_execution_id = response['QueryExecutionId']
    print(query_execution_id)

    # get execution status
    for i in range(1, 1 + RETRY_COUNT):

        # get query execution
        query_status = athena.get_query_execution(QueryExecutionId=query_execution_id)
        print(query_status)
        query_execution_status = query_status['QueryExecution']['Status']['State']

        if query_execution_status == 'SUCCEEDED':
            print("STATUS:" + query_execution_status)
            break

        if query_execution_status == 'FAILED':
            raise Exception("STATUS:" + query_execution_status)

        else:
            print("STATUS:" + query_execution_status)
            time.sleep(i)
    else:
        athena.stop_query_execution(QueryExecutionId=query_execution_id)
        raise Exception('TIME OVER')

    # get query results
    result = athena.get_query_results(QueryExecutionId=query_execution_id)

    print(result)

    total_dynamo_db_cost = result['ResultSet']['Rows'][1]['Data'][0]['VarCharValue']
    print(total_dynamo_db_cost)

    return Decimal(total_dynamo_db_cost)


def __filter_log_events_with_pattern(logs_client, log_group_name, filter_pattern, start_time, end_time):
    """
    Use filter_log_events API instead of Logs Insights for accurate log counting.
    Logs Insights has an indexing limitation where the first batch of log events
    in a new log stream (cold start logs) may not be indexed.
    filter_log_events returns ALL matching log events reliably.
    """
    # TODO: Implement filter_log_events with pagination to retrieve all matching log events
    events = []
    return events


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

    # Known function names for Lab7 pooled tenant stack
    known_function_names = [
        'create-product-pooled-lab7',
        'update-product-pooled-lab7',
        'get-products-pooled-lab7'
    ]

    # Two deployment modes:
    #   1. Individual lab deployment: stack is named 'stack-pooled-lab7'
    #   2. Orchestration deployment: stack is a nested stack named 'serverless-saas-lab-Lab7PooledStack-XXXXX'
    # We try to discover the orchestration nested stack first, then fall back to the individual name,
    # and finally use known function names as a last resort.
    stack_names_to_try = []

    # Discover orchestration nested stack
    print("Discovering Lab7 pooled tenant stack...")
    try:
        cfn_paginator = cloudformation.get_paginator('list_stacks')
        for page in cfn_paginator.paginate(StackStatusFilter=['CREATE_COMPLETE', 'UPDATE_COMPLETE']):
            for stack in page['StackSummaries']:
                if 'Lab7PooledStack' in stack['StackName'] or 'lab7-pooled' in stack['StackName'].lower():
                    print(f"  Found orchestration nested stack: {stack['StackName']}")
                    stack_names_to_try.append(stack['StackName'])
    except ClientError:
        pass  # Non-critical - we'll try other options

    # Also try the individual lab deployment stack name
    stack_names_to_try.append('stack-pooled-lab7')

    cloudformation_paginator = cloudformation.get_paginator('list_stack_resources')

    for stack_name in stack_names_to_try:
        try:
            response_iterator = cloudformation_paginator.paginate(StackName=stack_name)
            for stack_resources in response_iterator:
                for resource in stack_resources['StackResourceSummaries']:
                    if resource["LogicalResourceId"] in ("CreateProductFunction", "UpdateProductFunction", "GetProductsFunction"):
                        __add_log_group_name(logs, ''.join([log_group_prefix, resource["PhysicalResourceId"]]),
                         log_group_names)

            if log_group_names:
                print(f"  Resolved log groups via stack '{stack_name}': {log_group_names}")
                return log_group_names

        except ClientError as e:
            if e.response['Error']['Code'] == 'ValidationException':
                # Stack doesn't exist — expected when running in the other deployment mode
                print(f"  Stack '{stack_name}' not found, skipping.")
                continue
            else:
                print(f"  Unexpected error querying stack '{stack_name}': {e}")
                continue

    # Fallback: use known function names directly
    print("  No stack found. Using known function names as fallback.")
    for fn_name in known_function_names:
        __add_log_group_name(logs, log_group_prefix + fn_name, log_group_names)

    if log_group_names:
        print(f"  Resolved log groups via fallback: {log_group_names}")
    else:
        print("  No log groups found. Lambda functions may not have been invoked yet.")

    return log_group_names


def __get_start_date_time():
    time_zone = datetime.now().astimezone().tzinfo
    start_date_time = int(datetime.now(tz=time_zone).date().strftime('%s'))  # current day epoch
    return start_date_time


def __get_end_date_time():
    time_zone = datetime.now().astimezone().tzinfo
    end_date_time = int((datetime.now(tz=time_zone) + timedelta(days=1)).date().strftime('%s'))  # next day epoch
    return end_date_time
