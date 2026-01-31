"""
Resource Tracker component for end-to-end AWS testing system.

This module tracks AWS resources throughout the test lifecycle.
"""

import boto3
from datetime import datetime
from typing import Dict, List, Optional

from .logging_config import get_logger
from .models import (
    BucketInfo,
    LogGroupInfo,
    ResourceSnapshot,
    RoleInfo,
    StackInfo,
    TableInfo,
    UserPoolInfo,
)

logger = get_logger("resource_tracker")


class ResourceTracker:
    """
    Tracks AWS resources for end-to-end testing.
    
    Captures snapshots of CloudFormation stacks, S3 buckets, CloudWatch log groups,
    Cognito user pools, DynamoDB tables, and IAM roles.
    """
    
    # Lab-to-stack mapping
    # CRITICAL: Lab5 and Lab6 have DISTINCT pipeline stacks
    # Lab5, Lab6, and Lab7 also create tenant stacks dynamically
    LAB_STACK_MAPPING = {
        "lab1": ["serverless-saas-lab1"],
        "lab2": ["serverless-saas-lab2"],
        "lab3": ["serverless-saas-shared-lab3", "serverless-saas-tenant-lab3"],
        "lab4": ["serverless-saas-shared-lab4", "serverless-saas-tenant-lab4"],
        "lab5": ["serverless-saas-shared-lab5", "serverless-saas-pipeline-lab5"],  # Lab5 pipeline (creates tenant stacks)
        "lab6": ["serverless-saas-shared-lab6", "serverless-saas-pipeline-lab6"],  # Lab6 pipeline (DISTINCT from Lab5)
        "lab7": ["serverless-saas-lab7", "stack-pooled-lab7"],  # Lab7 base + pooled tenant stack
    }
    
    # Lab5, Lab6, and Lab7 create additional tenant stacks with these patterns
    # Lab5: stack-<tenantId>-lab5 (created by pipeline Lambda function)
    # Lab6: stack-.*-lab6 (e.g., stack-lab6-pooled, stack-basic-lab6)
    # Lab7: stack-pooled-lab7 (single tenant stack)
    LAB_TENANT_STACK_PATTERNS = {
        "lab5": r"stack-.*-lab5",  # Matches stack-<tenantId>-lab5 (created by pipeline)
        "lab6": r"stack-.*-lab6",  # Matches stack-lab6-pooled, stack-basic-lab6, etc.
        "lab7": r"stack-pooled-lab7"
    }
    
    # Workshop resource naming patterns
    WORKSHOP_PATTERNS = [
        "serverless-saas-",
        "ServerlessSaaS",
        "serverless-saas",
    ]
    
    def __init__(self, aws_profile: str, aws_region: str = "us-east-1"):
        """
        Initialize Resource Tracker with AWS clients.
        
        Args:
            aws_profile: AWS CLI profile name
            aws_region: AWS region (default: us-east-1)
        """
        self.aws_profile = aws_profile
        self.aws_region = aws_region
        
        # Create boto3 session with profile
        self.session = boto3.Session(
            profile_name=aws_profile,
            region_name=aws_region
        )
        
        # Initialize AWS clients
        self.cfn_client = self.session.client('cloudformation')
        self.s3_client = self.session.client('s3')
        self.logs_client = self.session.client('logs')
        self.cognito_client = self.session.client('cognito-idp')
        self.dynamodb_client = self.session.client('dynamodb')
        self.iam_client = self.session.client('iam')
        
        logger.info(f"ResourceTracker initialized with profile={aws_profile}, region={aws_region}")
    
    def capture_snapshot(self, snapshot_name: str) -> ResourceSnapshot:
        """
        Capture current AWS resource state.
        
        Args:
            snapshot_name: Name for this snapshot
        
        Returns:
            ResourceSnapshot containing all tracked resources
        """
        logger.info(f"Capturing resource snapshot: {snapshot_name}")
        timestamp = datetime.now()
        
        snapshot = ResourceSnapshot(
            timestamp=timestamp,
            snapshot_name=snapshot_name,
            stacks=self.get_cloudformation_stacks(),
            s3_buckets=self.get_s3_buckets(),
            log_groups=self.get_cloudwatch_log_groups(),
            user_pools=self.get_cognito_user_pools(),
            dynamodb_tables=self.get_dynamodb_tables(),
            iam_roles=self.get_iam_roles(),
        )
        
        logger.info(
            f"Snapshot captured: {len(snapshot.stacks)} stacks, "
            f"{len(snapshot.s3_buckets)} buckets, {len(snapshot.log_groups)} log groups, "
            f"{len(snapshot.user_pools)} user pools, {len(snapshot.dynamodb_tables)} tables, "
            f"{len(snapshot.iam_roles)} roles"
        )
        
        return snapshot
    
    def get_cloudformation_stacks(self) -> List[StackInfo]:
        """
        Get all CloudFormation stacks.
        
        Returns:
            List of StackInfo objects
        """
        stacks = []
        
        try:
            paginator = self.cfn_client.get_paginator('describe_stacks')
            for page in paginator.paginate():
                for stack in page['Stacks']:
                    # Filter workshop-related stacks
                    if self._is_workshop_resource(stack['StackName']):
                        stack_info = StackInfo(
                            stack_name=stack['StackName'],
                            stack_id=stack['StackId'],
                            stack_status=stack['StackStatus'],
                            creation_time=stack['CreationTime'],
                            outputs={
                                output['OutputKey']: output.get('OutputValue', '')
                                for output in stack.get('Outputs', [])
                            },
                            tags={
                                tag['Key']: tag['Value']
                                for tag in stack.get('Tags', [])
                            }
                        )
                        stacks.append(stack_info)
        
        except Exception as e:
            logger.error(f"Error getting CloudFormation stacks: {e}")
        
        return stacks
    
    def get_s3_buckets(self) -> List[BucketInfo]:
        """
        Get all S3 buckets.
        
        Returns:
            List of BucketInfo objects
        """
        buckets = []
        
        try:
            response = self.s3_client.list_buckets()
            for bucket in response.get('Buckets', []):
                bucket_name = bucket['Name']
                
                # Filter workshop-related buckets
                if self._is_workshop_resource(bucket_name):
                    # Get bucket location
                    try:
                        location_response = self.s3_client.get_bucket_location(
                            Bucket=bucket_name
                        )
                        region = location_response.get('LocationConstraint') or 'us-east-1'
                    except Exception:
                        region = 'unknown'
                    
                    # Get versioning status
                    versioning_enabled = False
                    try:
                        versioning_response = self.s3_client.get_bucket_versioning(
                            Bucket=bucket_name
                        )
                        versioning_enabled = versioning_response.get('Status') == 'Enabled'
                    except Exception:
                        pass
                    
                    bucket_info = BucketInfo(
                        bucket_name=bucket_name,
                        creation_date=bucket['CreationDate'],
                        region=region,
                        versioning_enabled=versioning_enabled
                    )
                    buckets.append(bucket_info)
        
        except Exception as e:
            logger.error(f"Error getting S3 buckets: {e}")
        
        return buckets
    
    def get_cloudwatch_log_groups(self) -> List[LogGroupInfo]:
        """
        Get all CloudWatch log groups.
        
        Returns:
            List of LogGroupInfo objects
        """
        log_groups = []
        
        try:
            paginator = self.logs_client.get_paginator('describe_log_groups')
            for page in paginator.paginate():
                for log_group in page.get('logGroups', []):
                    log_group_name = log_group['logGroupName']
                    
                    # Filter workshop-related log groups
                    if self._is_workshop_resource(log_group_name):
                        log_group_info = LogGroupInfo(
                            log_group_name=log_group_name,
                            creation_time=datetime.fromtimestamp(
                                log_group['creationTime'] / 1000
                            ),
                            retention_days=log_group.get('retentionInDays'),
                            stored_bytes=log_group.get('storedBytes', 0)
                        )
                        log_groups.append(log_group_info)
        
        except Exception as e:
            logger.error(f"Error getting CloudWatch log groups: {e}")
        
        return log_groups
    
    def get_cognito_user_pools(self) -> List[UserPoolInfo]:
        """
        Get all Cognito user pools.
        
        Returns:
            List of UserPoolInfo objects
        """
        user_pools = []
        
        try:
            paginator = self.cognito_client.get_paginator('list_user_pools')
            for page in paginator.paginate(MaxResults=60):
                for pool in page.get('UserPools', []):
                    pool_name = pool['Name']
                    
                    # Filter workshop-related user pools
                    if self._is_workshop_resource(pool_name):
                        user_pool_info = UserPoolInfo(
                            user_pool_id=pool['Id'],
                            user_pool_name=pool_name,
                            creation_date=pool['CreationDate'],
                            status=pool.get('Status', 'Unknown')
                        )
                        user_pools.append(user_pool_info)
        
        except Exception as e:
            logger.error(f"Error getting Cognito user pools: {e}")
        
        return user_pools
    
    def get_dynamodb_tables(self) -> List[TableInfo]:
        """
        Get all DynamoDB tables.
        
        Returns:
            List of TableInfo objects
        """
        tables = []
        
        try:
            paginator = self.dynamodb_client.get_paginator('list_tables')
            for page in paginator.paginate():
                for table_name in page.get('TableNames', []):
                    # Filter workshop-related tables
                    if self._is_workshop_resource(table_name):
                        try:
                            response = self.dynamodb_client.describe_table(
                                TableName=table_name
                            )
                            table = response['Table']
                            
                            table_info = TableInfo(
                                table_name=table_name,
                                table_arn=table['TableArn'],
                                creation_date=table['CreationDateTime'],
                                table_status=table['TableStatus'],
                                item_count=table.get('ItemCount', 0)
                            )
                            tables.append(table_info)
                        except Exception as e:
                            logger.warning(f"Error describing table {table_name}: {e}")
        
        except Exception as e:
            logger.error(f"Error getting DynamoDB tables: {e}")
        
        return tables
    
    def get_iam_roles(self) -> List[RoleInfo]:
        """
        Get all IAM roles.
        
        Returns:
            List of RoleInfo objects
        """
        roles = []
        
        try:
            paginator = self.iam_client.get_paginator('list_roles')
            for page in paginator.paginate():
                for role in page.get('Roles', []):
                    role_name = role['RoleName']
                    
                    # Filter workshop-related roles
                    if self._is_workshop_resource(role_name):
                        role_info = RoleInfo(
                            role_name=role_name,
                            role_arn=role['Arn'],
                            creation_date=role['CreateDate'],
                            assume_role_policy=role.get('AssumeRolePolicyDocument', {})
                        )
                        roles.append(role_info)
        
        except Exception as e:
            logger.error(f"Error getting IAM roles: {e}")
        
        return roles
    
    def _is_workshop_resource(self, resource_name: str) -> bool:
        """
        Check if resource name matches workshop patterns.
        
        Args:
            resource_name: Resource name to check
        
        Returns:
            True if resource is workshop-related
        """
        resource_lower = resource_name.lower()
        return any(pattern.lower() in resource_lower for pattern in self.WORKSHOP_PATTERNS)
    
    def get_lab_stacks(self, lab_name: str) -> List[str]:
        """
        Get stack names for a specific lab.
        
        CRITICAL: This method correctly distinguishes between Lab5 and Lab6 pipeline stacks.
        
        Args:
            lab_name: Lab name (e.g., "lab1", "lab5", "lab6")
        
        Returns:
            List of stack names for the lab
        """
        lab_key = lab_name.lower()
        return self.LAB_STACK_MAPPING.get(lab_key, [])
    
    def filter_resources_by_lab(self, snapshot: ResourceSnapshot, lab_name: str) -> ResourceSnapshot:
        """
        Filter snapshot to include only resources for a specific lab.
        
        Args:
            snapshot: Resource snapshot to filter
            lab_name: Lab name (e.g., "lab1", "lab5", "lab6")
        
        Returns:
            Filtered ResourceSnapshot
        """
        lab_stacks = self.get_lab_stacks(lab_name)
        
        # Filter stacks
        filtered_stacks = [
            stack for stack in snapshot.stacks
            if stack.stack_name in lab_stacks
        ]
        
        # For other resources, filter by lab-specific naming patterns
        lab_pattern = f"-{lab_name.lower()}"
        
        filtered_snapshot = ResourceSnapshot(
            timestamp=snapshot.timestamp,
            snapshot_name=f"{snapshot.snapshot_name}_{lab_name}",
            stacks=filtered_stacks,
            s3_buckets=[
                bucket for bucket in snapshot.s3_buckets
                if lab_pattern in bucket.bucket_name.lower()
            ],
            log_groups=[
                lg for lg in snapshot.log_groups
                if lab_pattern in lg.log_group_name.lower()
            ],
            user_pools=[
                pool for pool in snapshot.user_pools
                if lab_pattern in pool.user_pool_name.lower()
            ],
            dynamodb_tables=[
                table for table in snapshot.dynamodb_tables
                if lab_pattern in table.table_name.lower()
            ],
            iam_roles=[
                role for role in snapshot.iam_roles
                if lab_pattern in role.role_name.lower()
            ]
        )
        
        return filtered_snapshot
