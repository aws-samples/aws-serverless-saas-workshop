#!/usr/bin/env python3
"""
End-to-End Cleanup Isolation Test

Feature: lab-cleanup-isolation-all-labs, Task 6: End-to-End Cleanup Isolation Test
Validates: Requirements 8.1-8.15

This test implements a comprehensive end-to-end validation of the cleanup isolation
workflow across all labs (Lab1-Lab7). It follows the exact 11-step workflow:

1. Run cleanup-all-labs script to ensure clean state
2. Run deploy-all-labs script to deploy all labs
3-9. Run individual lab cleanup scripts and verify isolation
10. Redeploy all labs
11. Run cleanup-all-labs script and verify complete cleanup

The test can run in two modes:
- Dry-run mode: Simulates the workflow without actual AWS operations (fast)
- Real AWS mode: Executes actual deployment and cleanup operations (slow, ~60-90 min)

Usage:
    # Dry-run mode (default)
    pytest test_end_to_end_cleanup_isolation.py -v
    
    # Real AWS mode (requires AWS credentials and profile)
    pytest test_end_to_end_cleanup_isolation.py -v --real-aws --aws-profile=<profile>
    
    # Run specific steps only
    pytest test_end_to_end_cleanup_isolation.py -v -k "step_3"
"""

import pytest
import subprocess
import time
import json
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field
from datetime import datetime
import sys


# ANSI Color codes for output (matching bash scripts)
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


def print_colored(color: str, message: str, flush: bool = True):
    """Print colored message with automatic flushing for real-time output."""
    print(f"{color}{message}{Colors.NC}", flush=flush)


def print_separator(char: str = "=", length: int = 80, color: str = Colors.BLUE):
    """Print a separator line."""
    print_colored(color, char * length)


def print_timestamp():
    """Print current timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print_colored(Colors.YELLOW, f"[{timestamp}]", flush=True)


# Constants
WORKSHOP_ROOT = Path(__file__).parent.parent.resolve()  # Use resolve() to get absolute path
SCRIPTS_DIR = WORKSHOP_ROOT / "scripts"
LAB_DIRECTORIES = [f"Lab{i}" for i in range(1, 8)]
LAB_IDS = [f"lab{i}" for i in range(1, 8)]


@dataclass
class ResourceSnapshot:
    """Snapshot of AWS resources at a point in time."""
    timestamp: datetime
    stacks: Set[str] = field(default_factory=set)
    s3_buckets: Set[str] = field(default_factory=set)
    log_groups: Set[str] = field(default_factory=set)
    cognito_pools: Set[str] = field(default_factory=set)
    
    def __sub__(self, other: 'ResourceSnapshot') -> 'ResourceSnapshot':
        """Calculate the difference between two snapshots (resources deleted)."""
        return ResourceSnapshot(
            timestamp=self.timestamp,
            stacks=other.stacks - self.stacks,
            s3_buckets=other.s3_buckets - self.s3_buckets,
            log_groups=other.log_groups - self.log_groups,
            cognito_pools=other.cognito_pools - self.cognito_pools
        )

    def count(self) -> int:
        """Total number of resources in this snapshot."""
        return (len(self.stacks) + len(self.s3_buckets) + 
                len(self.log_groups) + len(self.cognito_pools))
    
    def is_empty(self) -> bool:
        """Check if snapshot contains no resources."""
        return self.count() == 0
    
    def to_dict(self) -> Dict:
        """Convert snapshot to dictionary for logging."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "stacks": sorted(list(self.stacks)),
            "s3_buckets": sorted(list(self.s3_buckets)),
            "log_groups": sorted(list(self.log_groups)),
            "cognito_pools": sorted(list(self.cognito_pools)),
            "total_count": self.count()
        }


@dataclass
class StepResult:
    """Result of a single test step."""
    step_number: int
    step_name: str
    success: bool
    duration_seconds: float
    resources_before: ResourceSnapshot
    resources_after: ResourceSnapshot
    resources_deleted: ResourceSnapshot
    error_message: Optional[str] = None
    warnings: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict:
        """Convert step result to dictionary for logging."""
        return {
            "step_number": self.step_number,
            "step_name": self.step_name,
            "success": self.success,
            "duration_seconds": round(self.duration_seconds, 2),
            "resources_before": self.resources_before.to_dict(),
            "resources_after": self.resources_after.to_dict(),
            "resources_deleted": self.resources_deleted.to_dict(),
            "error_message": self.error_message,
            "warnings": self.warnings
        }


class AWSResourceTracker:
    """Tracks AWS resources for cleanup isolation testing."""
    
    def __init__(self, aws_profile: Optional[str] = None, dry_run: bool = True):
        self.aws_profile = aws_profile
        self.dry_run = dry_run
        self.profile_arg = f"--profile {aws_profile}" if aws_profile else ""
    
    def take_snapshot(self) -> ResourceSnapshot:
        """Take a snapshot of current AWS resources."""
        if self.dry_run:
            return self._take_mock_snapshot()
        else:
            return self._take_real_snapshot()

    def _take_mock_snapshot(self) -> ResourceSnapshot:
        """Take a mock snapshot for dry-run mode."""
        # Return empty snapshot for dry-run mode
        # In real implementation, this would be populated based on test state
        return ResourceSnapshot(timestamp=datetime.now())
    
    def _take_real_snapshot(self) -> ResourceSnapshot:
        """Take a real snapshot by querying AWS APIs."""
        snapshot = ResourceSnapshot(timestamp=datetime.now())
        
        try:
            # Query CloudFormation stacks
            cmd = f"aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE {self.profile_arg} --output json"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for stack in data.get("StackSummaries", []):
                    stack_name = stack["StackName"]
                    # Filter for lab-related stacks
                    if any(f"lab{i}" in stack_name.lower() for i in range(1, 8)):
                        snapshot.stacks.add(stack_name)
            
            # Query S3 buckets
            cmd = f"aws s3api list-buckets {self.profile_arg} --output json"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for bucket in data.get("Buckets", []):
                    bucket_name = bucket["Name"]
                    # Filter for lab-related buckets
                    if any(f"lab{i}" in bucket_name.lower() for i in range(1, 8)):
                        snapshot.s3_buckets.add(bucket_name)
            
            # Query CloudWatch log groups
            cmd = f"aws logs describe-log-groups {self.profile_arg} --output json"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for log_group in data.get("logGroups", []):
                    log_name = log_group["logGroupName"]
                    # Filter for lab-related log groups
                    if any(f"lab{i}" in log_name.lower() for i in range(1, 8)):
                        snapshot.log_groups.add(log_name)
            
            # Query Cognito user pools
            cmd = f"aws cognito-idp list-user-pools --max-results 60 {self.profile_arg} --output json"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for pool in data.get("UserPools", []):
                    pool_name = pool["Name"]
                    # Filter for lab-related pools
                    if any(f"lab{i}" in pool_name.lower() for i in range(1, 8)):
                        snapshot.cognito_pools.add(pool_name)
        
        except Exception as e:
            print(f"Warning: Error taking snapshot: {e}")
        
        return snapshot

    def get_lab_resources(self, snapshot: ResourceSnapshot, lab_id: str) -> ResourceSnapshot:
        """Extract resources belonging to a specific lab from a snapshot."""
        lab_snapshot = ResourceSnapshot(timestamp=snapshot.timestamp)
        
        # Filter stacks
        lab_snapshot.stacks = {s for s in snapshot.stacks if lab_id in s.lower()}
        
        # Filter S3 buckets
        lab_snapshot.s3_buckets = {b for b in snapshot.s3_buckets if lab_id in b.lower()}
        
        # Filter log groups
        lab_snapshot.log_groups = {lg for lg in snapshot.log_groups if lab_id in lg.lower()}
        
        # Filter Cognito pools
        lab_snapshot.cognito_pools = {cp for cp in snapshot.cognito_pools if lab_id in cp.lower()}
        
        return lab_snapshot


class EndToEndTestRunner:
    """Orchestrates the end-to-end cleanup isolation test."""
    
    def __init__(self, aws_profile: Optional[str] = None, dry_run: bool = True, 
                 email: str = "test@example.com"):
        self.aws_profile = aws_profile
        self.dry_run = dry_run
        self.email = email
        self.tracker = AWSResourceTracker(aws_profile, dry_run)
        self.results: List[StepResult] = []
        # Store profile args as a list for proper argument passing
        self.profile_args = ["--profile", aws_profile] if aws_profile else []
    
    def run_script(self, script_path: Path, args: List[str] = None, 
                   timeout: int = 3600, stdin_input: str = None) -> Tuple[bool, str, float]:
        """
        Run a deployment or cleanup script with real-time output.
        
        Args:
            script_path: Path to the script to execute
            args: Command-line arguments for the script
            timeout: Maximum execution time in seconds
            stdin_input: Optional input to pipe to stdin (e.g., "yes" for cleanup confirmation)
        
        Returns:
            Tuple of (success, output, duration_seconds)
        """
        if self.dry_run:
            # Simulate script execution in dry-run mode
            print_colored(Colors.YELLOW, f"[DRY-RUN] Would execute: {script_path} {' '.join(args or [])}")
            if stdin_input:
                print_colored(Colors.YELLOW, f"[DRY-RUN] With stdin: {stdin_input}")
            return True, "Dry-run mode - script not executed", 0.1
        
        start_time = time.time()
        
        try:
            cmd = [str(script_path)] + (args or [])
            print_colored(Colors.YELLOW, f"Executing: {' '.join(cmd)}")
            print_colored(Colors.YELLOW, f"Working directory: {script_path.parent}")
            if stdin_input:
                print_colored(Colors.YELLOW, f"Piping stdin: {stdin_input}")
            print_timestamp()
            print()
            
            # Run with real-time output streaming
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE if stdin_input else None,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,  # Line buffered
                cwd=script_path.parent
            )
            
            output_lines = []
            
            # Send stdin input if provided
            if stdin_input:
                process.stdin.write(stdin_input + '\n')
                process.stdin.flush()
                process.stdin.close()
            
            # Stream output in real-time
            for line in process.stdout:
                print(line, end='', flush=True)  # Print immediately
                output_lines.append(line)
            
            # Wait for process to complete
            process.wait(timeout=timeout)
            
            duration = time.time() - start_time
            success = process.returncode == 0
            output = ''.join(output_lines)
            
            print()
            print_timestamp()
            if success:
                print_colored(Colors.GREEN, f"✓ Script completed successfully in {duration:.2f} seconds")
            else:
                print_colored(Colors.RED, f"✗ Script failed with exit code {process.returncode} after {duration:.2f} seconds")
            print()
            
            return success, output, duration
        
        except subprocess.TimeoutExpired:
            duration = time.time() - start_time
            print_colored(Colors.RED, f"✗ Script timed out after {timeout} seconds")
            return False, f"Script timed out after {timeout} seconds", duration
        
        except Exception as e:
            duration = time.time() - start_time
            print_colored(Colors.RED, f"✗ Script execution failed: {str(e)}")
            return False, f"Script execution failed: {str(e)}", duration

    def step_1_cleanup_all_labs(self) -> StepResult:
        """Step 1: Run cleanup-all-labs script to ensure clean state."""
        print()
        print_separator()
        print_colored(Colors.BLUE, "STEP 1: Cleanup All Labs (Ensure Clean State)")
        print_separator()
        print()
        
        start_time = time.time()
        resources_before = self.tracker.take_snapshot()
        
        print_colored(Colors.YELLOW, f"Resources before cleanup: {resources_before.count()}")
        print()
        
        # Run cleanup-all-labs script
        script_path = SCRIPTS_DIR / "cleanup-all-labs.sh"
        args = self.profile_args.copy()  # Use profile_args list
        
        success, output, script_duration = self.run_script(script_path, args, timeout=1800, stdin_input="yes")
        
        # Wait for resources to be deleted
        if not self.dry_run:
            print_colored(Colors.YELLOW, "Waiting 60 seconds for resources to be deleted...")
            for i in range(60, 0, -10):
                print_colored(Colors.YELLOW, f"  {i} seconds remaining...", flush=True)
                time.sleep(10)
            print()
        
        resources_after = self.tracker.take_snapshot()
        resources_deleted = resources_before - resources_after
        
        duration = time.time() - start_time
        
        # Verify clean state
        warnings = []
        if not resources_after.is_empty():
            warnings.append(f"Warning: {resources_after.count()} resources still exist after cleanup")
        
        result = StepResult(
            step_number=1,
            step_name="Cleanup All Labs (Ensure Clean State)",
            success=success,
            duration_seconds=duration,
            resources_before=resources_before,
            resources_after=resources_after,
            resources_deleted=resources_deleted,
            warnings=warnings
        )
        
        self.results.append(result)
        self._print_step_summary(result)
        return result
    
    def step_2_deploy_all_labs(self) -> StepResult:
        """Step 2: Run deploy-all-labs script to deploy all labs."""
        print()
        print_separator()
        print_colored(Colors.BLUE, "STEP 2: Deploy All Labs")
        print_separator()
        print()
        
        start_time = time.time()
        resources_before = self.tracker.take_snapshot()
        
        print_colored(Colors.YELLOW, f"Resources before deployment: {resources_before.count()}")
        print()
        
        # Run deploy-all-labs script
        script_path = SCRIPTS_DIR / "deploy-all-labs.sh"
        args = ["--all", "--email", self.email]
        args.extend(self.profile_args)  # Add profile args as separate items
        
        success, output, script_duration = self.run_script(script_path, args, timeout=5400)
        
        # Wait for resources to be created
        if not self.dry_run:
            print_colored(Colors.YELLOW, "Waiting 60 seconds for resources to be created...")
            for i in range(60, 0, -10):
                print_colored(Colors.YELLOW, f"  {i} seconds remaining...", flush=True)
                time.sleep(10)
            print()
        
        resources_after = self.tracker.take_snapshot()
        resources_deleted = resources_before - resources_after
        
        duration = time.time() - start_time
        
        # Verify all labs deployed
        warnings = []
        expected_labs = set(LAB_IDS)
        deployed_labs = set()
        
        for stack in resources_after.stacks:
            for lab_id in LAB_IDS:
                if lab_id in stack.lower():
                    deployed_labs.add(lab_id)
        
        missing_labs = expected_labs - deployed_labs
        if missing_labs:
            warnings.append(f"Warning: Labs not deployed: {', '.join(sorted(missing_labs))}")
        
        result = StepResult(
            step_number=2,
            step_name="Deploy All Labs",
            success=success and len(missing_labs) == 0,
            duration_seconds=duration,
            resources_before=resources_before,
            resources_after=resources_after,
            resources_deleted=resources_deleted,
            warnings=warnings
        )
        
        self.results.append(result)
        self._print_step_summary(result)
        return result

    def cleanup_single_lab(self, lab_num: int, remaining_labs: List[str]) -> StepResult:
        """
        Run cleanup for a single lab and verify isolation.
        
        Args:
            lab_num: Lab number (1-7)
            remaining_labs: List of lab IDs that should remain intact
        
        Returns:
            StepResult with verification details
        """
        lab_id = f"lab{lab_num}"
        step_num = lab_num + 2  # Steps 3-9 are lab cleanups
        
        print()
        print_separator()
        print_colored(Colors.BLUE, f"STEP {step_num}: Cleanup Lab{lab_num} (Verify Lab{lab_num+1}-Lab7 Intact)")
        print_separator()
        print()
        
        start_time = time.time()
        resources_before = self.tracker.take_snapshot()
        
        print_colored(Colors.YELLOW, f"Resources before Lab{lab_num} cleanup: {resources_before.count()}")
        print()
        
        # Get resources for target lab and remaining labs before cleanup
        target_lab_before = self.tracker.get_lab_resources(resources_before, lab_id)
        remaining_labs_before = {}
        for remaining_lab_id in remaining_labs:
            remaining_labs_before[remaining_lab_id] = self.tracker.get_lab_resources(
                resources_before, remaining_lab_id
            )
        
        # Run lab cleanup script
        lab_dir = WORKSHOP_ROOT / f"Lab{lab_num}"
        script_path = lab_dir / "scripts" / "cleanup.sh"
        
        # All labs now use the same --stack-name parameter format
        args = ["--stack-name", f"serverless-saas-lab{lab_num}"]
        args.extend(self.profile_args)  # Add profile args as separate items
        
        success, output, script_duration = self.run_script(script_path, args, timeout=1800, stdin_input="yes")
        
        # Wait for resources to be deleted
        if not self.dry_run:
            print_colored(Colors.YELLOW, f"Waiting 60 seconds for Lab{lab_num} resources to be deleted...")
            for i in range(60, 0, -10):
                print_colored(Colors.YELLOW, f"  {i} seconds remaining...", flush=True)
                time.sleep(10)
            print()
        
        resources_after = self.tracker.take_snapshot()
        resources_deleted = resources_before - resources_after
        
        duration = time.time() - start_time
        
        # Verify target lab resources are deleted
        target_lab_after = self.tracker.get_lab_resources(resources_after, lab_id)
        warnings = []
        error_message = None
        
        if not target_lab_after.is_empty():
            warnings.append(
                f"Warning: {target_lab_after.count()} Lab{lab_num} resources still exist after cleanup"
            )
        
        # CRITICAL: Verify remaining labs are intact
        cross_lab_deletions = []
        for remaining_lab_id in remaining_labs:
            remaining_lab_after = self.tracker.get_lab_resources(resources_after, remaining_lab_id)
            remaining_lab_before_snapshot = remaining_labs_before[remaining_lab_id]
            
            # Check if any resources were deleted
            if remaining_lab_after.count() < remaining_lab_before_snapshot.count():
                deleted_stacks = remaining_lab_before_snapshot.stacks - remaining_lab_after.stacks
                deleted_buckets = remaining_lab_before_snapshot.s3_buckets - remaining_lab_after.s3_buckets
                deleted_logs = remaining_lab_before_snapshot.log_groups - remaining_lab_after.log_groups
                
                if deleted_stacks or deleted_buckets or deleted_logs:
                    cross_lab_deletions.append({
                        "lab": remaining_lab_id,
                        "stacks": list(deleted_stacks),
                        "buckets": list(deleted_buckets),
                        "logs": list(deleted_logs)
                    })
        
        if cross_lab_deletions:
            error_message = f"CRITICAL: Lab{lab_num} cleanup deleted resources from other labs: {cross_lab_deletions}"
            success = False
        
        # Special verification for Lab5 (critical bug fix)
        if lab_num == 5:
            lab6_after = self.tracker.get_lab_resources(resources_after, "lab6")
            lab7_after = self.tracker.get_lab_resources(resources_after, "lab7")
            
            # Check for critical stacks
            critical_lab6_stack = "stack-lab6-pooled"
            critical_lab7_stack = "stack-pooled-lab7"
            
            if critical_lab6_stack not in " ".join(lab6_after.stacks):
                if critical_lab6_stack in " ".join(resources_before.stacks):
                    error_message = f"CRITICAL BUG: Lab5 cleanup deleted {critical_lab6_stack}!"
                    success = False
            
            if critical_lab7_stack not in " ".join(lab7_after.stacks):
                if critical_lab7_stack in " ".join(resources_before.stacks):
                    error_message = f"CRITICAL BUG: Lab5 cleanup deleted {critical_lab7_stack}!"
                    success = False
        
        result = StepResult(
            step_number=step_num,
            step_name=f"Cleanup Lab{lab_num}",
            success=success,
            duration_seconds=duration,
            resources_before=resources_before,
            resources_after=resources_after,
            resources_deleted=resources_deleted,
            error_message=error_message,
            warnings=warnings
        )
        
        self.results.append(result)
        self._print_step_summary(result)
        return result

    def step_10_redeploy_all_labs(self) -> StepResult:
        """Step 10: Run deploy-all-labs script again to redeploy all labs."""
        print()
        print_separator()
        print_colored(Colors.BLUE, "STEP 10: Redeploy All Labs")
        print_separator()
        print()
        
        # This is identical to step 2
        start_time = time.time()
        resources_before = self.tracker.take_snapshot()
        
        print_colored(Colors.YELLOW, f"Resources before redeployment: {resources_before.count()}")
        print()
        
        # Run deploy-all-labs script
        script_path = SCRIPTS_DIR / "deploy-all-labs.sh"
        args = ["--all", "--email", self.email]
        args.extend(self.profile_args)  # Add profile args as separate items
        
        success, output, script_duration = self.run_script(script_path, args, timeout=5400)
        
        # Wait for resources to be created
        if not self.dry_run:
            print_colored(Colors.YELLOW, "Waiting 60 seconds for resources to be created...")
            for i in range(60, 0, -10):
                print_colored(Colors.YELLOW, f"  {i} seconds remaining...", flush=True)
                time.sleep(10)
            print()
        
        resources_after = self.tracker.take_snapshot()
        resources_deleted = resources_before - resources_after
        
        duration = time.time() - start_time
        
        # Verify all labs deployed
        warnings = []
        expected_labs = set(LAB_IDS)
        deployed_labs = set()
        
        for stack in resources_after.stacks:
            for lab_id in LAB_IDS:
                if lab_id in stack.lower():
                    deployed_labs.add(lab_id)
        
        missing_labs = expected_labs - deployed_labs
        if missing_labs:
            warnings.append(f"Warning: Labs not deployed: {', '.join(sorted(missing_labs))}")
        
        result = StepResult(
            step_number=10,
            step_name="Redeploy All Labs",
            success=success and len(missing_labs) == 0,
            duration_seconds=duration,
            resources_before=resources_before,
            resources_after=resources_after,
            resources_deleted=resources_deleted,
            warnings=warnings
        )
        
        self.results.append(result)
        self._print_step_summary(result)
        return result
    
    def step_11_cleanup_all_labs_final(self) -> StepResult:
        """Step 11: Run cleanup-all-labs script and verify all resources deleted."""
        print()
        print_separator()
        print_colored(Colors.BLUE, "STEP 11: Cleanup All Labs (Final Verification)")
        print_separator()
        print()
        
        start_time = time.time()
        resources_before = self.tracker.take_snapshot()
        
        print_colored(Colors.YELLOW, f"Resources before final cleanup: {resources_before.count()}")
        print()
        
        # Run cleanup-all-labs script
        script_path = SCRIPTS_DIR / "cleanup-all-labs.sh"
        args = self.profile_args.copy()  # Use profile_args list
        
        success, output, script_duration = self.run_script(script_path, args, timeout=1800, stdin_input="yes")
        
        # Wait for resources to be deleted
        if not self.dry_run:
            print_colored(Colors.YELLOW, "Waiting 60 seconds for resources to be deleted...")
            for i in range(60, 0, -10):
                print_colored(Colors.YELLOW, f"  {i} seconds remaining...", flush=True)
                time.sleep(10)
            print()
        
        resources_after = self.tracker.take_snapshot()
        resources_deleted = resources_before - resources_after
        
        duration = time.time() - start_time
        
        # Verify all resources are deleted
        warnings = []
        error_message = None
        
        if not resources_after.is_empty():
            error_message = f"CRITICAL: {resources_after.count()} resources still exist after final cleanup"
            success = False
            
            # List remaining resources
            if resources_after.stacks:
                warnings.append(f"Remaining stacks: {', '.join(sorted(resources_after.stacks))}")
            if resources_after.s3_buckets:
                warnings.append(f"Remaining S3 buckets: {', '.join(sorted(resources_after.s3_buckets))}")
            if resources_after.log_groups:
                warnings.append(f"Remaining log groups: {', '.join(sorted(resources_after.log_groups))}")
            if resources_after.cognito_pools:
                warnings.append(f"Remaining Cognito pools: {', '.join(sorted(resources_after.cognito_pools))}")
        
        result = StepResult(
            step_number=11,
            step_name="Cleanup All Labs (Final Verification)",
            success=success,
            duration_seconds=duration,
            resources_before=resources_before,
            resources_after=resources_after,
            resources_deleted=resources_deleted,
            error_message=error_message,
            warnings=warnings
        )
        
        self.results.append(result)
        self._print_step_summary(result)
        return result

    def _print_step_summary(self, result: StepResult):
        """Print a summary of a step result."""
        print()
        print_separator("-", 80, Colors.YELLOW)
        
        status_color = Colors.GREEN if result.success else Colors.RED
        status_text = "✓ PASS" if result.success else "✗ FAIL"
        print_colored(status_color, f"{status_text} - Step {result.step_number}: {result.step_name}")
        
        print_colored(Colors.YELLOW, f"Duration: {result.duration_seconds:.2f} seconds ({result.duration_seconds/60:.2f} minutes)")
        print_colored(Colors.YELLOW, f"Resources before: {result.resources_before.count()}")
        print_colored(Colors.YELLOW, f"Resources after: {result.resources_after.count()}")
        print_colored(Colors.YELLOW, f"Resources deleted: {result.resources_deleted.count()}")
        
        if result.warnings:
            print()
            print_colored(Colors.YELLOW, "Warnings:")
            for warning in result.warnings:
                print_colored(Colors.YELLOW, f"  - {warning}")
        
        if result.error_message:
            print()
            print_colored(Colors.RED, f"Error: {result.error_message}")
        
        print_separator("-", 80, Colors.YELLOW)
        print()
    
    def print_final_report(self):
        """Print a comprehensive final report of all test steps."""
        print()
        print_separator("=", 80, Colors.BLUE)
        print_colored(Colors.BLUE, "END-TO-END CLEANUP ISOLATION TEST - FINAL REPORT")
        print_separator("=", 80, Colors.BLUE)
        print()
        
        total_duration = sum(r.duration_seconds for r in self.results)
        passed_steps = sum(1 for r in self.results if r.success)
        failed_steps = len(self.results) - passed_steps
        
        print_colored(Colors.YELLOW, f"Total Steps: {len(self.results)}")
        print_colored(Colors.GREEN if passed_steps == len(self.results) else Colors.YELLOW, 
                     f"Passed: {passed_steps}")
        if failed_steps > 0:
            print_colored(Colors.RED, f"Failed: {failed_steps}")
        else:
            print_colored(Colors.GREEN, f"Failed: {failed_steps}")
        print_colored(Colors.YELLOW, f"Total Duration: {total_duration:.2f} seconds ({total_duration/60:.2f} minutes)")
        print()
        
        print_separator("-", 80, Colors.YELLOW)
        print_colored(Colors.BLUE, "Step-by-Step Summary:")
        print_separator("-", 80, Colors.YELLOW)
        print()
        
        for result in self.results:
            status_color = Colors.GREEN if result.success else Colors.RED
            status = "✓" if result.success else "✗"
            print_colored(status_color, 
                         f"{status} Step {result.step_number}: {result.step_name} "
                         f"({result.duration_seconds:.2f}s, "
                         f"{result.resources_deleted.count()} resources deleted)")
            
            if result.error_message:
                print_colored(Colors.RED, f"  ERROR: {result.error_message}")
            
            if result.warnings:
                for warning in result.warnings:
                    print_colored(Colors.YELLOW, f"  WARNING: {warning}")
        
        print()
        print_separator("-", 80, Colors.YELLOW)
        print_colored(Colors.BLUE, "Resource Tracking Summary:")
        print_separator("-", 80, Colors.YELLOW)
        print()
        
        for result in self.results:
            print_colored(Colors.BLUE, f"Step {result.step_number}: {result.step_name}")
            print_colored(Colors.YELLOW, 
                         f"  Before: {result.resources_before.count()} resources "
                         f"({len(result.resources_before.stacks)} stacks, "
                         f"{len(result.resources_before.s3_buckets)} buckets, "
                         f"{len(result.resources_before.log_groups)} logs)")
            print_colored(Colors.YELLOW, 
                         f"  After:  {result.resources_after.count()} resources "
                         f"({len(result.resources_after.stacks)} stacks, "
                         f"{len(result.resources_after.s3_buckets)} buckets, "
                         f"{len(result.resources_after.log_groups)} logs)")
            print_colored(Colors.YELLOW, f"  Deleted: {result.resources_deleted.count()} resources")
            print()
        
        # Save detailed report to JSON file
        report_file = WORKSHOP_ROOT / "tests" / "end_to_end_test_report.json"
        report_data = {
            "test_name": "End-to-End Cleanup Isolation Test",
            "timestamp": datetime.now().isoformat(),
            "dry_run": self.dry_run,
            "aws_profile": self.aws_profile,
            "total_steps": len(self.results),
            "passed_steps": passed_steps,
            "failed_steps": failed_steps,
            "total_duration_seconds": total_duration,
            "steps": [r.to_dict() for r in self.results]
        }
        
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        print_colored(Colors.GREEN, f"Detailed report saved to: {report_file}")
        print()
        
        # Final verdict
        print_separator("=", 80, Colors.BLUE)
        if failed_steps == 0:
            print_colored(Colors.GREEN, "✓ ALL TESTS PASSED - Cleanup isolation is working correctly!")
        else:
            print_colored(Colors.RED, f"✗ {failed_steps} TEST(S) FAILED - Cleanup isolation has issues!")
        print_separator("=", 80, Colors.BLUE)
        print()
    
    def run_full_test(self):
        """Run the complete 11-step end-to-end test."""
        print()
        print_separator("=", 80, Colors.BLUE)
        print_colored(Colors.BLUE, "END-TO-END CLEANUP ISOLATION TEST")
        print_separator("=", 80, Colors.BLUE)
        print()
        print_colored(Colors.YELLOW, f"Mode: {'DRY-RUN' if self.dry_run else 'REAL AWS'}")
        print_colored(Colors.YELLOW, f"AWS Profile: {self.aws_profile or 'default'}")
        print_colored(Colors.YELLOW, f"Email: {self.email}")
        print_separator("=", 80, Colors.BLUE)
        print()
        print_timestamp()
        print()
        
        try:
            # Step 1: Cleanup all labs (ensure clean state)
            self.step_1_cleanup_all_labs()
            
            # Step 2: Deploy all labs
            self.step_2_deploy_all_labs()
            
            # Steps 3-9: Cleanup labs one by one
            for lab_num in range(1, 8):
                remaining_labs = [f"lab{i}" for i in range(lab_num + 1, 8)]
                self.cleanup_single_lab(lab_num, remaining_labs)
            
            # Step 10: Redeploy all labs
            self.step_10_redeploy_all_labs()
            
            # Step 11: Cleanup all labs (final verification)
            self.step_11_cleanup_all_labs_final()
        
        except Exception as e:
            print()
            print_colored(Colors.RED, f"✗ TEST EXECUTION FAILED: {str(e)}")
            import traceback
            traceback.print_exc()
        
        finally:
            # Always print final report
            self.print_final_report()



# Pytest fixtures and configuration
@pytest.fixture
def test_runner(test_config):
    """Create a test runner with configuration from command-line options."""
    dry_run = test_config["dry_run"]
    aws_profile = test_config["aws_profile"]
    email = test_config["email"]
    
    if not dry_run and not aws_profile:
        pytest.skip("Real AWS mode requires --aws-profile option")
    
    return EndToEndTestRunner(
        aws_profile=aws_profile,
        dry_run=dry_run,
        email=email
    )


# Main test function
@pytest.mark.slow
@pytest.mark.integration
def test_end_to_end_cleanup_isolation(test_runner):
    """
    Comprehensive end-to-end test of cleanup isolation across all labs.
    
    This test validates Requirements 8.1-8.15 by executing the complete
    11-step workflow:
    
    1. Cleanup all labs (ensure clean state)
    2. Deploy all labs (Lab1-Lab7)
    3. Cleanup Lab1, verify Lab2-Lab7 intact
    4. Cleanup Lab2, verify Lab3-Lab7 intact
    5. Cleanup Lab3, verify Lab4-Lab7 intact
    6. Cleanup Lab4, verify Lab5-Lab7 intact
    7. Cleanup Lab5, verify Lab6-Lab7 intact (CRITICAL: stack-lab6-pooled, stack-pooled-lab7 NOT deleted)
    8. Cleanup Lab6, verify Lab7 intact
    9. Cleanup Lab7, verify all labs cleaned
    10. Redeploy all labs
    11. Cleanup all labs, verify complete cleanup
    
    The test can run in two modes:
    - Dry-run mode (default): Simulates workflow without AWS operations
    - Real AWS mode: Executes actual deployment and cleanup (requires --real-aws --aws-profile flags)
    
    Usage:
        # Dry-run mode (fast, no AWS required)
        pytest test_end_to_end_cleanup_isolation.py -v
        
        # Real AWS mode (slow, requires AWS credentials)
        pytest test_end_to_end_cleanup_isolation.py -v --real-aws --aws-profile=<profile>
    """
    # Run the complete test
    test_runner.run_full_test()
    
    # Verify all steps passed
    failed_steps = [r for r in test_runner.results if not r.success]
    
    if failed_steps:
        error_messages = []
        for result in failed_steps:
            error_messages.append(
                f"Step {result.step_number} ({result.step_name}) failed: {result.error_message}"
            )
        
        pytest.fail(
            f"\n{len(failed_steps)} step(s) failed:\n" + 
            "\n".join(error_messages)
        )


# Individual step tests (can be run independently)
@pytest.mark.slow
def test_step_1_cleanup_all_labs(test_runner):
    """Test Step 1: Cleanup all labs to ensure clean state."""
    result = test_runner.step_1_cleanup_all_labs()
    assert result.success, f"Step 1 failed: {result.error_message}"


@pytest.mark.slow
def test_step_2_deploy_all_labs(test_runner):
    """Test Step 2: Deploy all labs."""
    # Ensure clean state first
    test_runner.step_1_cleanup_all_labs()
    
    result = test_runner.step_2_deploy_all_labs()
    assert result.success, f"Step 2 failed: {result.error_message}"


@pytest.mark.slow
@pytest.mark.parametrize("lab_num", [1, 2, 3, 4, 5, 6, 7])
def test_step_cleanup_single_lab(test_runner, lab_num):
    """Test Steps 3-9: Cleanup individual labs and verify isolation."""
    # This test assumes all labs are already deployed
    # In real execution, this would be part of the full workflow
    
    remaining_labs = [f"lab{i}" for i in range(lab_num + 1, 8)]
    result = test_runner.cleanup_single_lab(lab_num, remaining_labs)
    
    assert result.success, f"Step {lab_num + 2} failed: {result.error_message}"


@pytest.mark.slow
def test_step_10_redeploy_all_labs(test_runner):
    """Test Step 10: Redeploy all labs after individual cleanups."""
    result = test_runner.step_10_redeploy_all_labs()
    assert result.success, f"Step 10 failed: {result.error_message}"


@pytest.mark.slow
def test_step_11_cleanup_all_labs_final(test_runner):
    """Test Step 11: Final cleanup of all labs."""
    result = test_runner.step_11_cleanup_all_labs_final()
    assert result.success, f"Step 11 failed: {result.error_message}"


# Critical bug validation test
@pytest.mark.critical
def test_lab5_does_not_delete_lab6_lab7_resources(test_runner):
    """
    Critical test: Verify Lab5 cleanup does not delete Lab6 or Lab7 resources.
    
    This specifically validates the bug fix where Lab5 cleanup was incorrectly
    deleting stack-lab6-pooled and stack-pooled-lab7.
    
    Validates: Requirements 8.6 (Step 7 critical verification)
    """
    # This test can be run independently to verify the critical bug fix
    # It assumes Lab5, Lab6, and Lab7 are deployed
    
    resources_before = test_runner.tracker.take_snapshot()
    
    # Get Lab6 and Lab7 resources before Lab5 cleanup
    lab6_before = test_runner.tracker.get_lab_resources(resources_before, "lab6")
    lab7_before = test_runner.tracker.get_lab_resources(resources_before, "lab7")
    
    # Run Lab5 cleanup
    result = test_runner.cleanup_single_lab(5, ["lab6", "lab7"])
    
    # Get Lab6 and Lab7 resources after Lab5 cleanup
    resources_after = test_runner.tracker.take_snapshot()
    lab6_after = test_runner.tracker.get_lab_resources(resources_after, "lab6")
    lab7_after = test_runner.tracker.get_lab_resources(resources_after, "lab7")
    
    # Verify Lab6 resources are intact
    assert lab6_after.count() == lab6_before.count(), \
        f"Lab5 cleanup deleted Lab6 resources! Before: {lab6_before.count()}, After: {lab6_after.count()}"
    
    # Verify Lab7 resources are intact
    assert lab7_after.count() == lab7_before.count(), \
        f"Lab5 cleanup deleted Lab7 resources! Before: {lab7_before.count()}, After: {lab7_after.count()}"
    
    # Verify critical stacks are NOT deleted
    critical_stacks = ["stack-lab6-pooled", "stack-pooled-lab6", "stack-pooled-lab7"]
    for critical_stack in critical_stacks:
        if any(critical_stack in s for s in lab6_before.stacks.union(lab7_before.stacks)):
            assert any(critical_stack in s for s in lab6_after.stacks.union(lab7_after.stacks)), \
                f"CRITICAL BUG: Lab5 cleanup deleted {critical_stack}!"


# CDKToolkit shared resource tests
@pytest.mark.critical
def test_lab5_skips_cdktoolkit_when_lab6_deployed(test_runner):
    """
    Critical test: Verify Lab5 cleanup skips CDKToolkit deletion when Lab6 is deployed.
    
    CDKToolkit is a SHARED resource between Lab5 and Lab6. When Lab6 is deployed,
    Lab5 cleanup must NOT delete CDKToolkit because Lab6's pipeline stack needs it.
    
    Validates: Bug #3 fix - CDKToolkit shared resource handling
    """
    # This test assumes Lab5 and Lab6 are both deployed
    
    resources_before = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit exists before cleanup
    cdktoolkit_before = any("CDKToolkit" in s for s in resources_before.stacks)
    
    # Run Lab5 cleanup (Lab6 is still deployed)
    result = test_runner.cleanup_single_lab(5, ["lab6"])
    
    resources_after = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit still exists after Lab5 cleanup
    cdktoolkit_after = any("CDKToolkit" in s for s in resources_after.stacks)
    
    if cdktoolkit_before:
        assert cdktoolkit_after, \
            "CRITICAL BUG: Lab5 cleanup deleted CDKToolkit while Lab6 is still deployed!"


@pytest.mark.critical
def test_lab6_skips_cdktoolkit_when_lab5_deployed(test_runner):
    """
    Critical test: Verify Lab6 cleanup skips CDKToolkit deletion when Lab5 is deployed.
    
    CDKToolkit is a SHARED resource between Lab5 and Lab6. When Lab5 is deployed,
    Lab6 cleanup must NOT delete CDKToolkit because Lab5's pipeline stack needs it.
    
    Validates: Bug #3 fix - CDKToolkit shared resource handling
    """
    # This test assumes Lab5 and Lab6 are both deployed
    
    resources_before = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit exists before cleanup
    cdktoolkit_before = any("CDKToolkit" in s for s in resources_before.stacks)
    
    # Run Lab6 cleanup (Lab5 is still deployed)
    result = test_runner.cleanup_single_lab(6, ["lab5"])
    
    resources_after = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit still exists after Lab6 cleanup
    cdktoolkit_after = any("CDKToolkit" in s for s in resources_after.stacks)
    
    if cdktoolkit_before:
        assert cdktoolkit_after, \
            "CRITICAL BUG: Lab6 cleanup deleted CDKToolkit while Lab5 is still deployed!"


@pytest.mark.critical
def test_lab5_deletes_cdktoolkit_when_lab6_not_deployed(test_runner):
    """
    Critical test: Verify Lab5 cleanup deletes CDKToolkit when Lab6 is NOT deployed.
    
    When Lab6 is not deployed, Lab5 cleanup should delete CDKToolkit since it's
    no longer needed by any lab.
    
    Validates: Bug #3 fix - CDKToolkit shared resource handling
    """
    # This test assumes Lab5 is deployed but Lab6 is NOT deployed
    
    resources_before = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit exists before cleanup
    cdktoolkit_before = any("CDKToolkit" in s for s in resources_before.stacks)
    
    # Verify Lab6 is NOT deployed
    lab6_deployed = any("lab6" in s.lower() for s in resources_before.stacks)
    
    if not lab6_deployed and cdktoolkit_before:
        # Run Lab5 cleanup (Lab6 is NOT deployed)
        result = test_runner.cleanup_single_lab(5, [])
        
        resources_after = test_runner.tracker.take_snapshot()
        
        # Verify CDKToolkit is deleted after Lab5 cleanup
        cdktoolkit_after = any("CDKToolkit" in s for s in resources_after.stacks)
        
        assert not cdktoolkit_after, \
            "Lab5 cleanup should delete CDKToolkit when Lab6 is not deployed!"


@pytest.mark.critical
def test_lab6_deletes_cdktoolkit_when_lab5_not_deployed(test_runner):
    """
    Critical test: Verify Lab6 cleanup deletes CDKToolkit when Lab5 is NOT deployed.
    
    When Lab5 is not deployed, Lab6 cleanup should delete CDKToolkit since it's
    no longer needed by any lab.
    
    Validates: Bug #3 fix - CDKToolkit shared resource handling
    """
    # This test assumes Lab6 is deployed but Lab5 is NOT deployed
    
    resources_before = test_runner.tracker.take_snapshot()
    
    # Verify CDKToolkit exists before cleanup
    cdktoolkit_before = any("CDKToolkit" in s for s in resources_before.stacks)
    
    # Verify Lab5 is NOT deployed
    lab5_deployed = any("lab5" in s.lower() for s in resources_before.stacks)
    
    if not lab5_deployed and cdktoolkit_before:
        # Run Lab6 cleanup (Lab5 is NOT deployed)
        result = test_runner.cleanup_single_lab(6, [])
        
        resources_after = test_runner.tracker.take_snapshot()
        
        # Verify CDKToolkit is deleted after Lab6 cleanup
        cdktoolkit_after = any("CDKToolkit" in s for s in resources_after.stacks)
        
        assert not cdktoolkit_after, \
            "Lab6 cleanup should delete CDKToolkit when Lab5 is not deployed!"


if __name__ == "__main__":
    # Allow running the test directly
    import sys
    
    # Parse command-line arguments
    dry_run = "--real-aws" not in sys.argv
    aws_profile = None
    email = "test@example.com"
    
    for i, arg in enumerate(sys.argv):
        if arg.startswith("--aws-profile="):
            aws_profile = arg.split("=")[1]
        elif arg.startswith("--email="):
            email = arg.split("=")[1]
    
    if not dry_run and not aws_profile:
        print("Error: Real AWS mode requires --aws-profile option")
        print("Usage: python test_end_to_end_cleanup_isolation.py [--real-aws] [--aws-profile=<profile>] [--email=<email>]")
        sys.exit(1)
    
    # Create and run test
    runner = EndToEndTestRunner(
        aws_profile=aws_profile,
        dry_run=dry_run,
        email=email
    )
    
    runner.run_full_test()
    
    # Exit with appropriate code
    failed_steps = [r for r in runner.results if not r.success]
    sys.exit(len(failed_steps))
