"""
Data models for end-to-end AWS testing system.

This module defines all data structures used throughout the testing framework.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional


# Resource Information Models

@dataclass
class StackInfo:
    """CloudFormation stack information."""
    stack_name: str
    stack_id: str
    stack_status: str
    creation_time: datetime
    outputs: Dict[str, str] = field(default_factory=dict)
    tags: Dict[str, str] = field(default_factory=dict)


@dataclass
class BucketInfo:
    """S3 bucket information."""
    bucket_name: str
    creation_date: datetime
    region: str
    versioning_enabled: bool = False


@dataclass
class LogGroupInfo:
    """CloudWatch log group information."""
    log_group_name: str
    creation_time: datetime
    retention_days: Optional[int] = None
    stored_bytes: int = 0


@dataclass
class UserPoolInfo:
    """Cognito user pool information."""
    user_pool_id: str
    user_pool_name: str
    creation_date: datetime
    status: str


@dataclass
class TableInfo:
    """DynamoDB table information."""
    table_name: str
    table_arn: str
    creation_date: datetime
    table_status: str
    item_count: int = 0


@dataclass
class RoleInfo:
    """IAM role information."""
    role_name: str
    role_arn: str
    creation_date: datetime
    assume_role_policy: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ResourceInfo:
    """Generic resource information."""
    resource_type: str
    resource_id: str
    resource_name: str
    metadata: Dict[str, Any] = field(default_factory=dict)


# Snapshot and Comparison Models

@dataclass
class ResourceSnapshot:
    """Snapshot of AWS resources at a point in time."""
    timestamp: datetime
    snapshot_name: str
    stacks: List[StackInfo] = field(default_factory=list)
    s3_buckets: List[BucketInfo] = field(default_factory=list)
    log_groups: List[LogGroupInfo] = field(default_factory=list)
    user_pools: List[UserPoolInfo] = field(default_factory=list)
    dynamodb_tables: List[TableInfo] = field(default_factory=list)
    iam_roles: List[RoleInfo] = field(default_factory=list)


@dataclass
class StateDiff:
    """Difference between two resource snapshots."""
    before_snapshot: ResourceSnapshot
    after_snapshot: ResourceSnapshot
    created_resources: List[ResourceInfo] = field(default_factory=list)
    deleted_resources: List[ResourceInfo] = field(default_factory=list)
    modified_resources: List[ResourceInfo] = field(default_factory=list)
    unchanged_resources: List[ResourceInfo] = field(default_factory=list)


@dataclass
class IsolationResult:
    """Result of lab isolation verification."""
    deleted_lab: str
    deleted_lab_resources_removed: bool
    other_labs_unaffected: bool
    orphaned_resources: List[ResourceInfo] = field(default_factory=list)
    verification_details: Dict[str, Any] = field(default_factory=dict)


# Timing and Monitoring Models

@dataclass
class TimingMetric:
    """Timing metric for an operation."""
    operation_name: str
    start_time: datetime
    end_time: datetime
    duration: timedelta
    duration_seconds: float


@dataclass
class APICallInfo:
    """AWS API call information."""
    service: str
    operation: str
    request_id: str
    status_code: int
    timestamp: datetime
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    retry_count: int = 0


@dataclass
class APIStatistics:
    """Statistics for AWS API calls."""
    total_calls: int
    successful_calls: int
    failed_calls: int
    calls_by_service: Dict[str, int] = field(default_factory=dict)
    success_rate_by_service: Dict[str, float] = field(default_factory=dict)
    failed_calls_list: List[APICallInfo] = field(default_factory=list)


# Test Execution Models

@dataclass
class ScriptResult:
    """Result of script execution."""
    script_path: Path
    exit_code: int
    stdout: str
    stderr: str
    duration: timedelta
    success: bool


@dataclass
class StepResult:
    """Result of a test step."""
    step_number: int
    step_name: str
    success: bool
    start_time: datetime
    end_time: datetime
    duration: timedelta
    before_snapshot: ResourceSnapshot
    after_snapshot: ResourceSnapshot
    state_diff: StateDiff
    log_files: List[Path] = field(default_factory=list)
    error_message: Optional[str] = None


@dataclass
class TestReport:
    """Comprehensive test report."""
    test_start_time: datetime
    test_end_time: datetime
    total_duration: timedelta
    config: Dict[str, Any]
    step_results: List[StepResult] = field(default_factory=list)
    timing_metrics: List[TimingMetric] = field(default_factory=list)
    api_statistics: Optional[APIStatistics] = None
    isolation_results: List[IsolationResult] = field(default_factory=list)
    overall_success: bool = True
    summary: str = ""
