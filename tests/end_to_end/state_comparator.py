"""
State Comparator component for end-to-end AWS testing system.

This module compares resource snapshots and verifies expected changes.
"""

from typing import Dict, List, Set

from .logging_config import get_logger
from .models import (
    IsolationResult,
    ResourceInfo,
    ResourceSnapshot,
    StateDiff,
)

logger = get_logger("state_comparator")


class StateComparator:
    """
    Compares resource snapshots and verifies isolation.
    
    Identifies created, deleted, and modified resources between snapshots.
    Verifies lab isolation and detects orphaned resources.
    """
    
    def __init__(self):
        """Initialize State Comparator."""
        logger.info("StateComparator initialized")
    
    def compare_snapshots(
        self,
        before: ResourceSnapshot,
        after: ResourceSnapshot
    ) -> StateDiff:
        """
        Compare two resource snapshots.
        
        Args:
            before: Snapshot before operation
            after: Snapshot after operation
        
        Returns:
            StateDiff containing resource changes
        """
        logger.info(
            f"Comparing snapshots: {before.snapshot_name} -> {after.snapshot_name}"
        )
        
        # Compare each resource type
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        # Compare stacks
        stack_changes = self._compare_stacks(before.stacks, after.stacks)
        created.extend(stack_changes['created'])
        deleted.extend(stack_changes['deleted'])
        modified.extend(stack_changes['modified'])
        unchanged.extend(stack_changes['unchanged'])
        
        # Compare S3 buckets
        bucket_changes = self._compare_buckets(before.s3_buckets, after.s3_buckets)
        created.extend(bucket_changes['created'])
        deleted.extend(bucket_changes['deleted'])
        modified.extend(bucket_changes['modified'])
        unchanged.extend(bucket_changes['unchanged'])
        
        # Compare log groups
        log_changes = self._compare_log_groups(before.log_groups, after.log_groups)
        created.extend(log_changes['created'])
        deleted.extend(log_changes['deleted'])
        modified.extend(log_changes['modified'])
        unchanged.extend(log_changes['unchanged'])
        
        # Compare user pools
        pool_changes = self._compare_user_pools(before.user_pools, after.user_pools)
        created.extend(pool_changes['created'])
        deleted.extend(pool_changes['deleted'])
        modified.extend(pool_changes['modified'])
        unchanged.extend(pool_changes['unchanged'])
        
        # Compare DynamoDB tables
        table_changes = self._compare_tables(before.dynamodb_tables, after.dynamodb_tables)
        created.extend(table_changes['created'])
        deleted.extend(table_changes['deleted'])
        modified.extend(table_changes['modified'])
        unchanged.extend(table_changes['unchanged'])
        
        # Compare IAM roles
        role_changes = self._compare_roles(before.iam_roles, after.iam_roles)
        created.extend(role_changes['created'])
        deleted.extend(role_changes['deleted'])
        modified.extend(role_changes['modified'])
        unchanged.extend(role_changes['unchanged'])
        
        diff = StateDiff(
            before_snapshot=before,
            after_snapshot=after,
            created_resources=created,
            deleted_resources=deleted,
            modified_resources=modified,
            unchanged_resources=unchanged
        )
        
        logger.info(
            f"Comparison complete: {len(created)} created, {len(deleted)} deleted, "
            f"{len(modified)} modified, {len(unchanged)} unchanged"
        )
        
        return diff
    
    def _compare_stacks(self, before_stacks, after_stacks) -> Dict[str, List[ResourceInfo]]:
        """Compare CloudFormation stacks."""
        before_names = {s.stack_name: s for s in before_stacks}
        after_names = {s.stack_name: s for s in after_stacks}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        # Find created stacks
        for name in after_names:
            if name not in before_names:
                created.append(ResourceInfo(
                    resource_type="CloudFormation::Stack",
                    resource_id=after_names[name].stack_id,
                    resource_name=name,
                    metadata={'status': after_names[name].stack_status}
                ))
        
        # Find deleted stacks
        for name in before_names:
            if name not in after_names:
                deleted.append(ResourceInfo(
                    resource_type="CloudFormation::Stack",
                    resource_id=before_names[name].stack_id,
                    resource_name=name,
                    metadata={'status': before_names[name].stack_status}
                ))
        
        # Find modified/unchanged stacks
        for name in before_names:
            if name in after_names:
                before_stack = before_names[name]
                after_stack = after_names[name]
                
                if before_stack.stack_status != after_stack.stack_status:
                    modified.append(ResourceInfo(
                        resource_type="CloudFormation::Stack",
                        resource_id=after_stack.stack_id,
                        resource_name=name,
                        metadata={
                            'before_status': before_stack.stack_status,
                            'after_status': after_stack.stack_status
                        }
                    ))
                else:
                    unchanged.append(ResourceInfo(
                        resource_type="CloudFormation::Stack",
                        resource_id=after_stack.stack_id,
                        resource_name=name,
                        metadata={'status': after_stack.stack_status}
                    ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def _compare_buckets(self, before_buckets, after_buckets) -> Dict[str, List[ResourceInfo]]:
        """Compare S3 buckets."""
        before_names = {b.bucket_name: b for b in before_buckets}
        after_names = {b.bucket_name: b for b in after_buckets}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        for name in after_names:
            if name not in before_names:
                created.append(ResourceInfo(
                    resource_type="S3::Bucket",
                    resource_id=name,
                    resource_name=name,
                    metadata={'region': after_names[name].region}
                ))
        
        for name in before_names:
            if name not in after_names:
                deleted.append(ResourceInfo(
                    resource_type="S3::Bucket",
                    resource_id=name,
                    resource_name=name,
                    metadata={'region': before_names[name].region}
                ))
        
        for name in before_names:
            if name in after_names:
                before_bucket = before_names[name]
                after_bucket = after_names[name]
                
                if before_bucket.versioning_enabled != after_bucket.versioning_enabled:
                    modified.append(ResourceInfo(
                        resource_type="S3::Bucket",
                        resource_id=name,
                        resource_name=name,
                        metadata={
                            'before_versioning': before_bucket.versioning_enabled,
                            'after_versioning': after_bucket.versioning_enabled
                        }
                    ))
                else:
                    unchanged.append(ResourceInfo(
                        resource_type="S3::Bucket",
                        resource_id=name,
                        resource_name=name,
                        metadata={'region': after_bucket.region}
                    ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def _compare_log_groups(self, before_groups, after_groups) -> Dict[str, List[ResourceInfo]]:
        """Compare CloudWatch log groups."""
        before_names = {lg.log_group_name: lg for lg in before_groups}
        after_names = {lg.log_group_name: lg for lg in after_groups}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        for name in after_names:
            if name not in before_names:
                created.append(ResourceInfo(
                    resource_type="Logs::LogGroup",
                    resource_id=name,
                    resource_name=name,
                    metadata={'retention_days': after_names[name].retention_days}
                ))
        
        for name in before_names:
            if name not in after_names:
                deleted.append(ResourceInfo(
                    resource_type="Logs::LogGroup",
                    resource_id=name,
                    resource_name=name,
                    metadata={'retention_days': before_names[name].retention_days}
                ))
        
        for name in before_names:
            if name in after_names:
                before_lg = before_names[name]
                after_lg = after_names[name]
                
                if before_lg.retention_days != after_lg.retention_days:
                    modified.append(ResourceInfo(
                        resource_type="Logs::LogGroup",
                        resource_id=name,
                        resource_name=name,
                        metadata={
                            'before_retention': before_lg.retention_days,
                            'after_retention': after_lg.retention_days
                        }
                    ))
                else:
                    unchanged.append(ResourceInfo(
                        resource_type="Logs::LogGroup",
                        resource_id=name,
                        resource_name=name,
                        metadata={'retention_days': after_lg.retention_days}
                    ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def _compare_user_pools(self, before_pools, after_pools) -> Dict[str, List[ResourceInfo]]:
        """Compare Cognito user pools."""
        before_ids = {p.user_pool_id: p for p in before_pools}
        after_ids = {p.user_pool_id: p for p in after_pools}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        for pool_id in after_ids:
            if pool_id not in before_ids:
                created.append(ResourceInfo(
                    resource_type="Cognito::UserPool",
                    resource_id=pool_id,
                    resource_name=after_ids[pool_id].user_pool_name,
                    metadata={'status': after_ids[pool_id].status}
                ))
        
        for pool_id in before_ids:
            if pool_id not in after_ids:
                deleted.append(ResourceInfo(
                    resource_type="Cognito::UserPool",
                    resource_id=pool_id,
                    resource_name=before_ids[pool_id].user_pool_name,
                    metadata={'status': before_ids[pool_id].status}
                ))
        
        for pool_id in before_ids:
            if pool_id in after_ids:
                unchanged.append(ResourceInfo(
                    resource_type="Cognito::UserPool",
                    resource_id=pool_id,
                    resource_name=after_ids[pool_id].user_pool_name,
                    metadata={'status': after_ids[pool_id].status}
                ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def _compare_tables(self, before_tables, after_tables) -> Dict[str, List[ResourceInfo]]:
        """Compare DynamoDB tables."""
        before_names = {t.table_name: t for t in before_tables}
        after_names = {t.table_name: t for t in after_tables}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        for name in after_names:
            if name not in before_names:
                created.append(ResourceInfo(
                    resource_type="DynamoDB::Table",
                    resource_id=after_names[name].table_arn,
                    resource_name=name,
                    metadata={'status': after_names[name].table_status}
                ))
        
        for name in before_names:
            if name not in after_names:
                deleted.append(ResourceInfo(
                    resource_type="DynamoDB::Table",
                    resource_id=before_names[name].table_arn,
                    resource_name=name,
                    metadata={'status': before_names[name].table_status}
                ))
        
        for name in before_names:
            if name in after_names:
                before_table = before_names[name]
                after_table = after_names[name]
                
                if before_table.table_status != after_table.table_status:
                    modified.append(ResourceInfo(
                        resource_type="DynamoDB::Table",
                        resource_id=after_table.table_arn,
                        resource_name=name,
                        metadata={
                            'before_status': before_table.table_status,
                            'after_status': after_table.table_status
                        }
                    ))
                else:
                    unchanged.append(ResourceInfo(
                        resource_type="DynamoDB::Table",
                        resource_id=after_table.table_arn,
                        resource_name=name,
                        metadata={'status': after_table.table_status}
                    ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def _compare_roles(self, before_roles, after_roles) -> Dict[str, List[ResourceInfo]]:
        """Compare IAM roles."""
        before_names = {r.role_name: r for r in before_roles}
        after_names = {r.role_name: r for r in after_roles}
        
        created = []
        deleted = []
        modified = []
        unchanged = []
        
        for name in after_names:
            if name not in before_names:
                created.append(ResourceInfo(
                    resource_type="IAM::Role",
                    resource_id=after_names[name].role_arn,
                    resource_name=name,
                    metadata={}
                ))
        
        for name in before_names:
            if name not in after_names:
                deleted.append(ResourceInfo(
                    resource_type="IAM::Role",
                    resource_id=before_names[name].role_arn,
                    resource_name=name,
                    metadata={}
                ))
        
        for name in before_names:
            if name in after_names:
                unchanged.append(ResourceInfo(
                    resource_type="IAM::Role",
                    resource_id=after_names[name].role_arn,
                    resource_name=name,
                    metadata={}
                ))
        
        return {
            'created': created,
            'deleted': deleted,
            'modified': modified,
            'unchanged': unchanged
        }
    
    def identify_created_resources(self, diff: StateDiff) -> List[ResourceInfo]:
        """
        Identify resources created between snapshots.
        
        Args:
            diff: State difference
        
        Returns:
            List of created resources
        """
        return diff.created_resources
    
    def identify_deleted_resources(self, diff: StateDiff) -> List[ResourceInfo]:
        """
        Identify resources deleted between snapshots.
        
        Args:
            diff: State difference
        
        Returns:
            List of deleted resources
        """
        return diff.deleted_resources
    
    def identify_modified_resources(self, diff: StateDiff) -> List[ResourceInfo]:
        """
        Identify resources modified between snapshots.
        
        Args:
            diff: State difference
        
        Returns:
            List of modified resources
        """
        return diff.modified_resources
    
    def verify_isolation(
        self,
        deleted_lab: str,
        diff: StateDiff
    ) -> IsolationResult:
        """
        Verify that deleting one lab did not affect other labs.
        
        Args:
            deleted_lab: Lab that was deleted (e.g., "Lab1", "Lab5")
            diff: State difference from before/after deletion
        
        Returns:
            IsolationResult with verification details
        """
        logger.info(f"Verifying isolation for deleted {deleted_lab}")
        
        # Define expected stacks for each lab
        # Note: Lab6 and Lab7 have additional tenant stacks created dynamically
        lab_stacks = {
            "Lab1": ["serverless-saas-lab1"],
            "Lab2": ["serverless-saas-lab2"],
            "Lab3": ["serverless-saas-shared-lab3", "serverless-saas-tenant-lab3"],
            "Lab4": ["serverless-saas-shared-lab4", "serverless-saas-tenant-lab4"],
            "Lab5": ["serverless-saas-shared-lab5", "serverless-saas-pipeline-lab5"],
            "Lab6": ["serverless-saas-shared-lab6", "serverless-saas-pipeline-lab6"],
            "Lab7": ["serverless-saas-lab7"]
        }
        
        # Lab6 and Lab7 also create tenant stacks with specific patterns
        lab_tenant_patterns = {
            "Lab6": "stack-.*-lab6",  # Matches stack-lab6-pooled, stack-basic-lab6, etc.
            "Lab7": "stack-pooled-lab7"
        }
        
        expected_deleted_stacks = lab_stacks.get(deleted_lab, [])
        
        # Check if deleted lab's resources were removed
        deleted_stack_names = {r.resource_name for r in diff.deleted_resources 
                              if r.resource_type == "CloudFormation::Stack"}
        
        # For Lab6 and Lab7, also check for tenant stacks
        deleted_lab_resources_removed = all(
            stack in deleted_stack_names for stack in expected_deleted_stacks
        )
        
        # Check tenant stacks for Lab6 and Lab7
        if deleted_lab in lab_tenant_patterns:
            import re
            pattern = lab_tenant_patterns[deleted_lab]
            tenant_stacks_found = False
            
            # Check if any tenant stacks matching the pattern were deleted
            for stack_name in deleted_stack_names:
                if re.match(pattern, stack_name):
                    tenant_stacks_found = True
                    logger.info(f"Found deleted tenant stack: {stack_name}")
            
            # For Lab6/Lab7, we expect tenant stacks to be deleted too
            # But we don't fail if none exist (they might not have been created)
            if tenant_stacks_found:
                logger.info(f"Tenant stacks for {deleted_lab} were properly deleted")
        
        # Check if other labs' stacks remain intact
        other_labs_unaffected = True
        affected_labs = []
        
        for lab, stacks in lab_stacks.items():
            if lab == deleted_lab:
                continue
            
            # Check if any of this lab's stacks were deleted
            for stack in stacks:
                if stack in deleted_stack_names:
                    other_labs_unaffected = False
                    affected_labs.append(f"{lab} (stack: {stack})")
                    logger.error(f"Isolation violation: {lab} stack {stack} was deleted")
            
            # Check tenant stack patterns for other labs
            if lab in lab_tenant_patterns:
                import re
                pattern = lab_tenant_patterns[lab]
                for stack_name in deleted_stack_names:
                    if re.match(pattern, stack_name):
                        other_labs_unaffected = False
                        affected_labs.append(f"{lab} (tenant stack: {stack_name})")
                        logger.error(f"Isolation violation: {lab} tenant stack {stack_name} was deleted")
        
        # Detect orphaned resources
        orphaned = self.detect_orphaned_resources(diff.after_snapshot)
        
        verification_details = {
            "expected_deleted_stacks": expected_deleted_stacks,
            "actually_deleted_stacks": list(deleted_stack_names),
            "affected_labs": affected_labs,
            "orphaned_resource_count": len(orphaned)
        }
        
        result = IsolationResult(
            deleted_lab=deleted_lab,
            deleted_lab_resources_removed=deleted_lab_resources_removed,
            other_labs_unaffected=other_labs_unaffected,
            orphaned_resources=orphaned,
            verification_details=verification_details
        )
        
        if result.deleted_lab_resources_removed and result.other_labs_unaffected:
            logger.info(f"Isolation verification PASSED for {deleted_lab}")
        else:
            logger.error(f"Isolation verification FAILED for {deleted_lab}")
        
        return result
    
    def detect_orphaned_resources(
        self,
        snapshot: ResourceSnapshot
    ) -> List[ResourceInfo]:
        """
        Detect resources not associated with any lab.
        
        Args:
            snapshot: Resource snapshot to check
        
        Returns:
            List of orphaned resources
        """
        logger.info("Detecting orphaned resources")
        
        orphaned = []
        
        # Define workshop resource patterns
        # CRITICAL: Must include "stack-" to recognize tenant stacks from Lab5/Lab6/Lab7
        # CRITICAL: Must include both "serverless-saas" and "serverlesssaas" (no hyphen) variations
        workshop_patterns = [
            "serverless-saas-lab",      # Stack names: serverless-saas-lab1, etc.
            "serverless-saas-shared",   # Stack names: serverless-saas-shared-lab3, etc.
            "serverless-saas-tenant",   # Stack names: serverless-saas-tenant-lab3, etc.
            "serverless-saas-pipeline", # Stack names: serverless-saas-pipeline-lab5, etc.
            "serverlesssaas",           # Resources: ServerlessSaaS-Settings-lab5, PooledTenant-ServerlessSaaS-lab6, etc.
            "serverlessaas",            # Resources: OperationUsers-ServerlessSaas-lab4, etc.
            "stack-",                   # Tenant stacks: stack-lab6-pooled, stack-pooled-lab7, etc.
            "-lab1", "-lab2", "-lab3", "-lab4", "-lab5", "-lab6", "-lab7"  # Catch any resource with lab suffix
        ]
        
        # Check all resource types for orphaned resources
        all_resources = []
        
        # Add stacks
        for stack in snapshot.stacks:
            all_resources.append(ResourceInfo(
                resource_type="CloudFormation::Stack",
                resource_id=stack.stack_id,
                resource_name=stack.stack_name,
                metadata={'status': stack.stack_status}
            ))
        
        # Add S3 buckets
        for bucket in snapshot.s3_buckets:
            all_resources.append(ResourceInfo(
                resource_type="S3::Bucket",
                resource_id=bucket.bucket_name,
                resource_name=bucket.bucket_name,
                metadata={'region': bucket.region}
            ))
        
        # Add log groups
        for lg in snapshot.log_groups:
            all_resources.append(ResourceInfo(
                resource_type="Logs::LogGroup",
                resource_id=lg.log_group_name,
                resource_name=lg.log_group_name,
                metadata={'retention_days': lg.retention_days}
            ))
        
        # Add user pools
        for pool in snapshot.user_pools:
            all_resources.append(ResourceInfo(
                resource_type="Cognito::UserPool",
                resource_id=pool.user_pool_id,
                resource_name=pool.user_pool_name,
                metadata={'status': pool.status}
            ))
        
        # Add DynamoDB tables
        for table in snapshot.dynamodb_tables:
            all_resources.append(ResourceInfo(
                resource_type="DynamoDB::Table",
                resource_id=table.table_arn,
                resource_name=table.table_name,
                metadata={'status': table.table_status}
            ))
        
        # Add IAM roles
        for role in snapshot.iam_roles:
            all_resources.append(ResourceInfo(
                resource_type="IAM::Role",
                resource_id=role.role_arn,
                resource_name=role.role_name,
                metadata={}
            ))
        
        # Check each resource against workshop patterns
        for resource in all_resources:
            is_workshop_resource = any(
                pattern in resource.resource_name.lower()
                for pattern in workshop_patterns
            )
            
            if not is_workshop_resource:
                # This resource doesn't match any workshop pattern
                orphaned.append(resource)
                logger.warning(
                    f"Orphaned resource detected: {resource.resource_type} - "
                    f"{resource.resource_name}"
                )
        
        logger.info(f"Found {len(orphaned)} orphaned resources")
        return orphaned
    
    def generate_diff_report(self, diff: StateDiff) -> str:
        """
        Generate human-readable diff report.
        
        Args:
            diff: State difference
        
        Returns:
            Formatted diff report
        """
        lines = []
        lines.append("=" * 80)
        lines.append("RESOURCE STATE COMPARISON")
        lines.append("=" * 80)
        lines.append(f"Before: {diff.before_snapshot.snapshot_name} ({diff.before_snapshot.timestamp})")
        lines.append(f"After:  {diff.after_snapshot.snapshot_name} ({diff.after_snapshot.timestamp})")
        lines.append("")
        
        # Created resources
        if diff.created_resources:
            lines.append(f"CREATED RESOURCES ({len(diff.created_resources)}):")
            lines.append("-" * 80)
            for resource in diff.created_resources:
                lines.append(f"  + {resource.resource_type}: {resource.resource_name}")
                if resource.metadata:
                    for key, value in resource.metadata.items():
                        lines.append(f"      {key}: {value}")
            lines.append("")
        
        # Deleted resources
        if diff.deleted_resources:
            lines.append(f"DELETED RESOURCES ({len(diff.deleted_resources)}):")
            lines.append("-" * 80)
            for resource in diff.deleted_resources:
                lines.append(f"  - {resource.resource_type}: {resource.resource_name}")
                if resource.metadata:
                    for key, value in resource.metadata.items():
                        lines.append(f"      {key}: {value}")
            lines.append("")
        
        # Modified resources
        if diff.modified_resources:
            lines.append(f"MODIFIED RESOURCES ({len(diff.modified_resources)}):")
            lines.append("-" * 80)
            for resource in diff.modified_resources:
                lines.append(f"  ~ {resource.resource_type}: {resource.resource_name}")
                if resource.metadata:
                    for key, value in resource.metadata.items():
                        lines.append(f"      {key}: {value}")
            lines.append("")
        
        # Summary
        lines.append("SUMMARY:")
        lines.append("-" * 80)
        lines.append(f"  Created:   {len(diff.created_resources)}")
        lines.append(f"  Deleted:   {len(diff.deleted_resources)}")
        lines.append(f"  Modified:  {len(diff.modified_resources)}")
        lines.append(f"  Unchanged: {len(diff.unchanged_resources)}")
        lines.append("=" * 80)
        
        return "\n".join(lines)
