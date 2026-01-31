"""
Snapshot storage module for end-to-end AWS testing system.

This module handles serialization and storage of resource snapshots.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

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

logger = get_logger("snapshot_storage")


class SnapshotStorage:
    """Handles storage and retrieval of resource snapshots."""
    
    def __init__(self, storage_directory: Path):
        """
        Initialize snapshot storage.
        
        Args:
            storage_directory: Directory for storing snapshots
        """
        self.storage_directory = storage_directory
        self.storage_directory.mkdir(parents=True, exist_ok=True)
        logger.info(f"SnapshotStorage initialized: {storage_directory}")
    
    def save_snapshot(self, snapshot: ResourceSnapshot, filename: Optional[str] = None) -> Path:
        """
        Save snapshot to JSON file.
        
        Args:
            snapshot: ResourceSnapshot to save
            filename: Optional filename (default: snapshot_name.json)
        
        Returns:
            Path to saved file
        """
        if filename is None:
            filename = f"{snapshot.snapshot_name}.json"
        
        filepath = self.storage_directory / filename
        
        # Convert snapshot to dictionary
        snapshot_dict = self._snapshot_to_dict(snapshot)
        
        # Save to JSON file
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(snapshot_dict, f, indent=2, default=str)
        
        logger.info(f"Snapshot saved: {filepath}")
        return filepath
    
    def load_snapshot(self, filename: str) -> ResourceSnapshot:
        """
        Load snapshot from JSON file.
        
        Args:
            filename: Filename to load
        
        Returns:
            ResourceSnapshot object
        """
        filepath = self.storage_directory / filename
        
        with open(filepath, 'r', encoding='utf-8') as f:
            snapshot_dict = json.load(f)
        
        snapshot = self._dict_to_snapshot(snapshot_dict)
        logger.info(f"Snapshot loaded: {filepath}")
        return snapshot
    
    def _snapshot_to_dict(self, snapshot: ResourceSnapshot) -> Dict[str, Any]:
        """Convert ResourceSnapshot to dictionary."""
        return {
            'timestamp': snapshot.timestamp.isoformat(),
            'snapshot_name': snapshot.snapshot_name,
            'stacks': [self._stack_to_dict(s) for s in snapshot.stacks],
            's3_buckets': [self._bucket_to_dict(b) for b in snapshot.s3_buckets],
            'log_groups': [self._log_group_to_dict(lg) for lg in snapshot.log_groups],
            'user_pools': [self._user_pool_to_dict(up) for up in snapshot.user_pools],
            'dynamodb_tables': [self._table_to_dict(t) for t in snapshot.dynamodb_tables],
            'iam_roles': [self._role_to_dict(r) for r in snapshot.iam_roles],
        }
    
    def _dict_to_snapshot(self, data: Dict[str, Any]) -> ResourceSnapshot:
        """Convert dictionary to ResourceSnapshot."""
        return ResourceSnapshot(
            timestamp=datetime.fromisoformat(data['timestamp']),
            snapshot_name=data['snapshot_name'],
            stacks=[self._dict_to_stack(s) for s in data.get('stacks', [])],
            s3_buckets=[self._dict_to_bucket(b) for b in data.get('s3_buckets', [])],
            log_groups=[self._dict_to_log_group(lg) for lg in data.get('log_groups', [])],
            user_pools=[self._dict_to_user_pool(up) for up in data.get('user_pools', [])],
            dynamodb_tables=[self._dict_to_table(t) for t in data.get('dynamodb_tables', [])],
            iam_roles=[self._dict_to_role(r) for r in data.get('iam_roles', [])],
        )
    
    def _stack_to_dict(self, stack: StackInfo) -> Dict[str, Any]:
        """Convert StackInfo to dictionary."""
        return {
            'stack_name': stack.stack_name,
            'stack_id': stack.stack_id,
            'stack_status': stack.stack_status,
            'creation_time': stack.creation_time.isoformat(),
            'outputs': stack.outputs,
            'tags': stack.tags,
        }
    
    def _dict_to_stack(self, data: Dict[str, Any]) -> StackInfo:
        """Convert dictionary to StackInfo."""
        return StackInfo(
            stack_name=data['stack_name'],
            stack_id=data['stack_id'],
            stack_status=data['stack_status'],
            creation_time=datetime.fromisoformat(data['creation_time']),
            outputs=data.get('outputs', {}),
            tags=data.get('tags', {}),
        )
    
    def _bucket_to_dict(self, bucket: BucketInfo) -> Dict[str, Any]:
        """Convert BucketInfo to dictionary."""
        return {
            'bucket_name': bucket.bucket_name,
            'creation_date': bucket.creation_date.isoformat(),
            'region': bucket.region,
            'versioning_enabled': bucket.versioning_enabled,
        }
    
    def _dict_to_bucket(self, data: Dict[str, Any]) -> BucketInfo:
        """Convert dictionary to BucketInfo."""
        return BucketInfo(
            bucket_name=data['bucket_name'],
            creation_date=datetime.fromisoformat(data['creation_date']),
            region=data['region'],
            versioning_enabled=data.get('versioning_enabled', False),
        )
    
    def _log_group_to_dict(self, log_group: LogGroupInfo) -> Dict[str, Any]:
        """Convert LogGroupInfo to dictionary."""
        return {
            'log_group_name': log_group.log_group_name,
            'creation_time': log_group.creation_time.isoformat(),
            'retention_days': log_group.retention_days,
            'stored_bytes': log_group.stored_bytes,
        }
    
    def _dict_to_log_group(self, data: Dict[str, Any]) -> LogGroupInfo:
        """Convert dictionary to LogGroupInfo."""
        return LogGroupInfo(
            log_group_name=data['log_group_name'],
            creation_time=datetime.fromisoformat(data['creation_time']),
            retention_days=data.get('retention_days'),
            stored_bytes=data.get('stored_bytes', 0),
        )
    
    def _user_pool_to_dict(self, user_pool: UserPoolInfo) -> Dict[str, Any]:
        """Convert UserPoolInfo to dictionary."""
        return {
            'user_pool_id': user_pool.user_pool_id,
            'user_pool_name': user_pool.user_pool_name,
            'creation_date': user_pool.creation_date.isoformat(),
            'status': user_pool.status,
        }
    
    def _dict_to_user_pool(self, data: Dict[str, Any]) -> UserPoolInfo:
        """Convert dictionary to UserPoolInfo."""
        return UserPoolInfo(
            user_pool_id=data['user_pool_id'],
            user_pool_name=data['user_pool_name'],
            creation_date=datetime.fromisoformat(data['creation_date']),
            status=data['status'],
        )
    
    def _table_to_dict(self, table: TableInfo) -> Dict[str, Any]:
        """Convert TableInfo to dictionary."""
        return {
            'table_name': table.table_name,
            'table_arn': table.table_arn,
            'creation_date': table.creation_date.isoformat(),
            'table_status': table.table_status,
            'item_count': table.item_count,
        }
    
    def _dict_to_table(self, data: Dict[str, Any]) -> TableInfo:
        """Convert dictionary to TableInfo."""
        return TableInfo(
            table_name=data['table_name'],
            table_arn=data['table_arn'],
            creation_date=datetime.fromisoformat(data['creation_date']),
            table_status=data['table_status'],
            item_count=data.get('item_count', 0),
        )
    
    def _role_to_dict(self, role: RoleInfo) -> Dict[str, Any]:
        """Convert RoleInfo to dictionary."""
        return {
            'role_name': role.role_name,
            'role_arn': role.role_arn,
            'creation_date': role.creation_date.isoformat(),
            'assume_role_policy': role.assume_role_policy,
        }
    
    def _dict_to_role(self, data: Dict[str, Any]) -> RoleInfo:
        """Convert dictionary to RoleInfo."""
        return RoleInfo(
            role_name=data['role_name'],
            role_arn=data['role_arn'],
            creation_date=datetime.fromisoformat(data['creation_date']),
            assume_role_policy=data.get('assume_role_policy', {}),
        )
