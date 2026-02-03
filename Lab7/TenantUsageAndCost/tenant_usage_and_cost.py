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

#This function needs to be scheduled on daily basis
def calculate_daily_dynamodb_attribution_by_tenant(event, context):
    start_date_time = __get_start_date_time() #current day epoch
    end_date_time =  __get_end_date_time() #next day epoch
    print("Processing attribution for current day")
    
    #TODO: Get total cost of DynamoDB for the current date
    total_dynamodb_cost = __get_total_service_cost('AmazonDynamoDB', start_date_time, end_date_time)

    log_group_names = __get_list_of_log_group_names()
    print(log_group_names)
    
    # Check if log groups exist before querying
    if not log_group_names or len(log_group_names) == 0:
        print("No log groups found. Skipping DynamoDB cost attribution.")
        return
    
    # Use filter_log_events API instead of Logs Insights for accurate counting
    # Logs Insights has an indexing limitation where cold start logs may not be indexed
    tenant_usage, total_RCU, total_WCU = __get_dynamodb_usage_by_tenant(
        logs, log_group_names, start_date_time, end_date_time
    )
    
    print(f"Total RCU: {total_RCU}, Total WCU: {total_WCU}")
    print(f"Usage by tenant: {tenant_usage}")
    
    # Check if we have any usage data
    if total_RCU + total_WCU == 0:
        print("No DynamoDB usage data found in CloudWatch Logs. Skipping DynamoDB cost attribution.")
        return
    
    # Process each tenant's usage
    for tenant_id, usage in tenant_usage.items():
        total_RCU_By_Tenant = usage['rcu']
        total_WCU_By_Tenant = usage['wcu']
        
        #RCU is about 5 times cheaper
        tenant_attribution_percentage_numerator = Decimal(str(total_RCU_By_Tenant * Decimal('5.0'))) + Decimal(str(total_WCU_By_Tenant))
        tenant_attribution_percentage_denominator = Decimal(str(total_RCU * Decimal('5.0'))) + Decimal(str(total_WCU))
        tenant_attribution_percentage = tenant_attribution_percentage_numerator / tenant_attribution_percentage_denominator
        tenant_dynamodb_cost = tenant_attribution_percentage * total_dynamodb_cost
        
        #TODO: Save the tenant attribution data inside a dynamodb table
        try:
            response = attribution_table.put_item(
                Item=
                    {
                        "Date": start_date_time,
                        "TenantId#ServiceName": tenant_id+"#"+"DynamoDB",
                        "TenantId": tenant_id,
                        "TotalRCU": Decimal(str(total_RCU)),
                        "TenantTotalRCU": Decimal(str(total_RCU_By_Tenant)),
                        "TotalWCU": Decimal(str(total_WCU)),
                        "TenantTotalWCU": Decimal(str(total_WCU_By_Tenant)),
                        "TenantAttributionPercentage": Decimal(str(tenant_attribution_percentage)),
                        "TenantServiceCost": Decimal(str(tenant_dynamodb_cost)),
                        "TotalServiceCost": Decimal(str(total_dynamodb_cost))
                    }
            )
        except ClientError as e:
            print(e.response['Error']['Message'])
            raise Exception('Error adding a product', e)
        else:
            print("PutItem succeeded:")
        
    
    
#Below function considers number of invocation as the metrics to calculate usage and cost. 
#You can go granluar by recording duration of each metrics and use that to get more granular
#Since our functions are basic CRUD this might work as a ball park cost estimate
def calculate_daily_lambda_attribution_by_tenant(event, context):
    start_date_time = __get_start_date_time() #current day epoch
    end_date_time =  __get_end_date_time() #next day epoch
    print("Processing attribution for current day")

    #Get total Lambda cost for the given duration
    total_lambda_cost = __get_total_service_cost('AWSLambda', start_date_time, end_date_time)

    log_group_names = __get_list_of_log_group_names()
    
    # Check if log groups exist before querying
    if not log_group_names or len(log_group_names) == 0:
        print("No log groups found. Skipping Lambda cost attribution.")
        return
    
    # Use filter_log_events API instead of Logs Insights for accurate counting
    # Logs Insights has an indexing limitation where cold start logs may not be indexed
    tenant_invocations, total_invocations = __get_lambda_invocations_by_tenant(
        logs, log_group_names, start_date_time, end_date_time
    )
    
    print(f"Total Lambda invocations: {total_invocations}")
    print(f"Invocations by tenant: {tenant_invocations}")
    
    # Check if we have any invocations
    if total_invocations == 0:
        print("No Lambda invocation data found in CloudWatch Logs. Skipping Lambda cost attribution.")
        return
    
    # Process each tenant's invocations
    for tenant_id, invocation_count in tenant_invocations.items():
        total_invocations_by_tenant = Decimal(str(invocation_count))
        
        tenant_attribution_percentage = total_invocations_by_tenant / Decimal(str(total_invocations))
        tenant_lambda_cost = tenant_attribution_percentage * total_lambda_cost
        
        try:
            response = attribution_table.put_item(
                Item=
                    {
                        "Date": start_date_time,
                        "TenantId#ServiceName": tenant_id+"#"+"AWSLambda",
                        "TenantId": tenant_id,
                        "TotalInvocations": Decimal(str(total_invocations)),
                        "TenantTotalInvocations": total_invocations_by_tenant,
                        "TenantAttributionPercentage": tenant_attribution_percentage,
                        "TenantServiceCost": tenant_lambda_cost,
                        "TotalServiceCost": total_lambda_cost
                    }
            )
        except ClientError as e:
            print(e.response['Error']['Message'])
            raise Exception('Error adding a product', e)
        else:
            print("PutItem succeeded:")
            

def __get_total_service_cost(servicename, start_date_time, end_date_time):

    # We need to add more filters for day, month, year, resource ids etc. Below query is because we are just using a sample cur file
    #Ignoting startTime and endTime filter for now since we have a static/sample cur file
    
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
        print (query_status)
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
    
    print (result)
    
    
    total_dynamo_db_cost = result['ResultSet']['Rows'][1]['Data'][0]['VarCharValue']
    print(total_dynamo_db_cost)
    
    return Decimal(total_dynamo_db_cost)
    
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


def __filter_log_events_with_pattern(logs_client, log_group_name, filter_pattern, start_time, end_time):
    """
    Use filter_log_events API instead of Logs Insights for accurate log counting.
    Logs Insights has an indexing limitation where the first batch of log events
    in a new log stream (cold start logs) may not be indexed.
    filter_log_events returns ALL matching log events reliably.
    """
    events = []
    paginator = logs_client.get_paginator('filter_log_events')
    
    # Convert epoch seconds to milliseconds for filter_log_events
    start_time_ms = start_time * 1000
    end_time_ms = end_time * 1000
    
    try:
        response_iterator = paginator.paginate(
            logGroupName=log_group_name,
            filterPattern=filter_pattern,
            startTime=start_time_ms,
            endTime=end_time_ms
        )
        
        for page in response_iterator:
            events.extend(page.get('events', []))
    except ClientError as e:
        print(f"Error filtering log events from {log_group_name}: {e}")
        
    return events


def __get_lambda_invocations_by_tenant(logs_client, log_group_names, start_time, end_time):
    """
    Get Lambda invocation counts by tenant using filter_log_events API.
    This is more accurate than Logs Insights which may miss cold start logs.
    """
    import json
    
    tenant_invocations = {}
    total_invocations = 0
    
    for log_group_name in log_group_names:
        events = __filter_log_events_with_pattern(
            logs_client, 
            log_group_name, 
            '"Request completed"',  # Filter pattern for completed requests
            start_time, 
            end_time
        )
        
        for event in events:
            try:
                # Parse the JSON log message
                message = event.get('message', '{}')
                log_data = json.loads(message)
                
                # Extract tenant_id from the log
                tenant_id = log_data.get('tenant_id', 'unknown')
                
                # Count invocations by tenant
                if tenant_id not in tenant_invocations:
                    tenant_invocations[tenant_id] = 0
                tenant_invocations[tenant_id] += 1
                total_invocations += 1
                
            except json.JSONDecodeError:
                # Skip non-JSON log entries
                continue
    
    return tenant_invocations, total_invocations


def __get_dynamodb_usage_by_tenant(logs_client, log_group_names, start_time, end_time):
    """
    Get DynamoDB RCU/WCU usage by tenant using filter_log_events API.
    This is more accurate than Logs Insights which may miss cold start logs.
    """
    import json
    
    tenant_usage = {}
    total_rcu = Decimal('0.0')
    total_wcu = Decimal('0.0')
    
    for log_group_name in log_group_names:
        events = __filter_log_events_with_pattern(
            logs_client, 
            log_group_name, 
            '"Request completed"',  # Filter pattern for completed requests
            start_time, 
            end_time
        )
        
        for event in events:
            try:
                # Parse the JSON log message
                message = event.get('message', '{}')
                log_data = json.loads(message)
                
                # Extract tenant_id and capacity units from the log
                tenant_id = log_data.get('tenant_id', 'unknown')
                consumed_rcu = Decimal(str(log_data.get('consumed_rcu', 0)))
                consumed_wcu = Decimal(str(log_data.get('consumed_wcu', 0)))
                
                # Aggregate usage by tenant
                if tenant_id not in tenant_usage:
                    tenant_usage[tenant_id] = {'rcu': Decimal('0.0'), 'wcu': Decimal('0.0')}
                tenant_usage[tenant_id]['rcu'] += consumed_rcu
                tenant_usage[tenant_id]['wcu'] += consumed_wcu
                
                # Track totals
                total_rcu += consumed_rcu
                total_wcu += consumed_wcu
                
            except json.JSONDecodeError:
                # Skip non-JSON log entries
                continue
    
    return tenant_usage, total_rcu, total_wcu

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
    
    # Implement exponential backoff retry logic for race condition
    # where tenant stack might not exist yet when Lambda first executes
    max_retries = 3  # Total wait time: 9 minutes (1min + 3min + 5min)
    wait_times = [60, 180, 300]  # 1 minute, 3 minutes, 5 minutes
    retry_count = 0
    
    while retry_count <= max_retries:
        try:
            response_iterator = cloudformation_paginator.paginate(StackName='stack-pooled-lab7')
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
            
            # Success - break out of retry loop
            break
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ValidationException':
                # Stack doesn't exist yet - this is expected during initial deployment
                if retry_count < max_retries:
                    wait_time = wait_times[retry_count]
                    wait_minutes = wait_time / 60
                    print(f"Stack 'stack-pooled-lab7' not found. Retry {retry_count + 1}/{max_retries} after {wait_minutes:.0f} minute(s)...")
                    time.sleep(wait_time)
                    retry_count += 1
                else:
                    # All retries exhausted - return empty list for graceful degradation
                    print(f"Stack 'stack-pooled-lab7' still not found after {max_retries} retries. Returning empty log group list.")
                    return []
            else:
                # Different error - re-raise it
                raise

    return log_group_names          

                  
def __get_start_date_time():
    time_zone = datetime.now().astimezone().tzinfo
    start_date_time = int(datetime.now(tz=time_zone).date().strftime('%s')) #current day epoch
    return start_date_time

def __get_end_date_time():
    time_zone = datetime.now().astimezone().tzinfo    
    end_date_time =  int((datetime.now(tz=time_zone) + timedelta(days=1)).date().strftime('%s')) #next day epoch
    return end_date_time


