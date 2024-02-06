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
attribution_table = dynamodb.Table("TenantCostAndUsageAttribution")

ATHENA_S3_OUTPUT = os.getenv("ATHENA_S3_OUTPUT")
RETRY_COUNT = 100

#This function needs to be scheduled on daily basis
def calculate_daily_dynamodb_attribution_by_tenant(event, context):
    start_date_time = __get_start_date_time() #current day epoch
    end_date_time =  __get_end_date_time() #next day epoch
    
    #Get total dynamodb cost for the given duration
    #TODO: Get total cost of DynamoDB for the current date
    total_dynamodb_cost = 0

    log_group_names = __get_list_of_log_group_names()
    print( log_group_names)
        
    #TODO: Write the query to get the DynamoDB WCU and RCUs consumption grouped by TenantId
    usage_by_tenant_by_day_query = 'query placeholder'
    
    usage_by_tenant_by_day = __query_cloudwatch_logs(logs, log_group_names, usage_by_tenant_by_day_query, start_date_time, end_date_time)
    print(usage_by_tenant_by_day)        
    
    #TODO: Write the query to get the Total DynamoDB WCU and RCUs consumption across all tenants
    total_usage_by_day_query = 'query placeholder'
    
    total_usage_by_day = __query_cloudwatch_logs(logs, log_group_names, total_usage_by_day_query, start_date_time, end_date_time)
    print(total_usage_by_day)  
    
    total_RCU = Decimal('0.0') 
    total_WCU = Decimal('0.0') 
    for result in total_usage_by_day['results'][0]:
        if 'ReadCapacityUnits' in result['field']:
            total_RCU = Decimal(result['value'])
        if 'WriteCapacityUnits' in result['field']:
            total_WCU = Decimal(result['value'])
    
    print (total_RCU)
    print (total_WCU)
    
    if (total_RCU + total_WCU > 0):
        total_RCU_By_Tenant = Decimal('0.0')
        total_WCU_By_Tenant = Decimal('0.0')
        
        for result in usage_by_tenant_by_day['results']:
            for field in result:
                if 'TenantId' in field['field']:
                    tenant_id = field['value']
                if 'ReadCapacityUnits' in field['field']:
                    total_RCU_By_Tenant = Decimal(field['value'])
                if 'WriteCapacityUnits' in field['field']:
                    total_WCU_By_Tenant = Decimal(field['value'])
            
            #RCU is about 5 times cheaper
            tenant_attribution_percentage_numerator= Decimal(str(total_RCU_By_Tenant * Decimal('5.0'))) + Decimal(str(total_WCU_By_Tenant)) 
            tenant_attribution_percentage_denominator= Decimal(str(total_RCU *  Decimal('5.0')))  + Decimal(str(total_WCU))
            tenant_attribution_percentage = tenant_attribution_percentage_numerator/tenant_attribution_percentage_denominator        
            tenant_dynamodb_cost = tenant_attribution_percentage * total_dynamodb_cost
            
            try:
                #TODO: Save the tenant attribution data inside a dynamodb table
                pass
            except ClientError as e:
                print(e.response['Error']['Message'])
                raise Exception('Error adding a product', e)
            else:
                print("PutItem succeeded:")
                
            tenant_id = 'unknown'
            total_RCU_By_Tenant = 0.0
            total_WCU_By_Tenant = 0.0
        
    
    
#Below function considers number of invocation as the metrics to calculate usage and cost. 
#You can go granluar by recording duration of each metrics and use that to get more granular
#Since our functions are basic CRUD this might work as a ball park cost estimate
def calculate_daily_lambda_attribution_by_tenant(event, context):
    
    #Get total dynamodb cost for the given duration
    start_date_time = __get_start_date_time() #current day epoch
    end_date_time =  __get_end_date_time() #next day epoch

    #Get total dynamodb cost for the given duration
    total_lambda_cost = __get_total_service_cost('AWSLambda', start_date_time, end_date_time)

    log_group_names = __get_list_of_log_group_names()
    
    #TODO: Write the below query to get the total lambda invocations grouped by tenants
    usage_by_tenant_by_day_query='query placeholder'

    usage_by_tenant_by_day = __query_cloudwatch_logs(logs, log_group_names, usage_by_tenant_by_day_query, start_date_time, end_date_time)
    print(usage_by_tenant_by_day) 

    #TODO: Write the below query to get the total lambda invocations across all tenants
    total_usage_by_day_query = 'query placeholder'
    
    total_usage_by_day = __query_cloudwatch_logs(logs,  log_group_names, total_usage_by_day_query, start_date_time, end_date_time)
    print(total_usage_by_day) 
    
    total_invocations = 1 #to avoid divide by zero
    for result in total_usage_by_day['results'][0]:
        if 'LambdaInvocations' in result['field']:
            total_invocations = Decimal(result['value'])
        
    print (total_invocations)
    
    if (total_invocations>0):
        total_invocations_by_tenant = 0
        
        for result in usage_by_tenant_by_day['results']:
            for field in result:
                if 'TenantId' in field['field']:
                    tenant_id = field['value']
                if 'LambdaInvocations' in field['field']:
                    total_invocations_by_tenant = Decimal(field['value'])
                
            tenant_attribution_percentage= (total_invocations_by_tenant / total_invocations) 
            tenant_lambda_cost = tenant_attribution_percentage * total_lambda_cost
            
            try:
                response = attribution_table.put_item(
                    Item=
                        {
                            "Date": start_date_time,
                            "TenantId#ServiceName": tenant_id+"#"+"AWSLambda",
                            "TenantId": tenant_id, 
                            "TotalInvocations": total_invocations, 
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
            
            tenant_id = 'unknown'
            total_invocations_by_tenant = 0
            

def __get_total_service_cost(servicename, start_date_time, end_date_time):

    # We need to add more filters for day, month, year, resource ids etc. Below query is because we are just using a sample cur file
    #Ignoting startTime and endTime filter for now since we have a static/sample cur file
    
    query = "SELECT sum(line_item_blended_cost) AS cost FROM costexplorerdb.curoutput WHERE line_item_product_code='{0}'".format(servicename) 

    # Execution
    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={
            'Database': 'costexplorerdb'
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

                  
def __get_start_date_time():
    time_zone = datetime.now().astimezone().tzinfo
    start_date_time = int(datetime.now(tz=time_zone).date().strftime('%s')) #current day epoch
    return start_date_time

def __get_end_date_time():
    time_zone = datetime.now().astimezone().tzinfo    
    end_date_time =  int((datetime.now(tz=time_zone) + timedelta(days=1)).date().strftime('%s')) #next day epoch
    return end_date_time
