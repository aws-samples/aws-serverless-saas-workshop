"""
Test Orchestrator component for end-to-end AWS testing system.

This module coordinates the entire 10-step test workflow and manages all components.
"""

import logging
from datetime import datetime
from pathlib import Path
from typing import Callable, List, Optional

from .api_monitor import APIMonitor
from .config import TestConfig
from .log_collector import LogCollector
from .models import IsolationResult, StepResult, TestReport
from .report_generator import TestReportGenerator
from .resource_tracker import ResourceTracker
from .script_executor import ScriptExecutor
from .state_comparator import StateComparator
from .timing_recorder import TimingRecorder

logger = logging.getLogger(__name__)


class TestOrchestrator:
    """
    Orchestrates the complete end-to-end test workflow.
    
    Coordinates all components and executes the 10-step testing process:
    1. Initial Cleanup
    2. Full Deployment
    3-9. Lab Isolation Tests (Lab1-7)
    10. Final Cleanup
    """
    
    def __init__(self, config: TestConfig):
        """
        Initialize test orchestrator with configuration.
        
        Args:
            config: Test configuration
        """
        self.config = config
        
        # Validate configuration
        self._validate_config()
        
        # Initialize components
        self.resource_tracker = ResourceTracker(
            aws_profile=config.aws_profile,
            aws_region=config.aws_region
        )
        self.state_comparator = StateComparator()
        self.log_collector = LogCollector(config.log_directory)
        self.script_executor = ScriptExecutor()
        self.api_monitor = APIMonitor()
        self.timing_recorder = TimingRecorder()
        self.report_generator = TestReportGenerator(config.report_directory)
        
        # Test state
        self.step_results: List[StepResult] = []
        self.isolation_results: List[IsolationResult] = []
        self.test_start_time: Optional[datetime] = None
        self.test_end_time: Optional[datetime] = None
        
        logger.info("Test orchestrator initialized")
        logger.info(f"Configuration: {config.to_dict()}")
    
    def _validate_config(self) -> None:
        """
        Validate test configuration.
        
        Raises:
            ValueError: If configuration is invalid
        """
        if not self.config.aws_profile:
            raise ValueError("AWS profile is required")
        
        if not self.config.email:
            raise ValueError("Email is required")
        
        if self.config.timeout_hours <= 0:
            raise ValueError("Timeout hours must be positive")
        
        logger.debug("Configuration validated successfully")
    
    def run_step(
        self,
        step_number: int,
        step_name: str,
        operation: Callable[[], bool]
    ) -> StepResult:
        """
        Execute a single test step with full tracking.
        
        Args:
            step_number: Step number (1-10)
            step_name: Human-readable step name
            operation: Callable that executes the step operation
            
        Returns:
            StepResult with all captured data
        """
        logger.info(f"=" * 80)
        logger.info(f"Starting Step {step_number}: {step_name}")
        logger.info(f"=" * 80)
        
        # Start timing
        timer = self.timing_recorder.start_operation(f"Step {step_number}: {step_name}")
        
        # Capture before snapshot
        logger.info("Capturing resource state before operation...")
        before_snapshot = self.resource_tracker.capture_snapshot(
            f"step{step_number}_before"
        )
        
        # Execute operation
        start_time = datetime.now()
        success = False
        error_message = None
        log_files = []
        
        try:
            success = operation()
        except Exception as e:
            logger.error(f"Step {step_number} failed with error: {e}", exc_info=True)
            error_message = str(e)
            success = False
        
        end_time = datetime.now()
        
        # Capture after snapshot
        logger.info("Capturing resource state after operation...")
        after_snapshot = self.resource_tracker.capture_snapshot(
            f"step{step_number}_after"
        )
        
        # Compare snapshots
        state_diff = self.state_comparator.compare_snapshots(
            before_snapshot,
            after_snapshot
        )
        
        # End timing
        timing_metric = self.timing_recorder.end_operation(timer)
        
        # Create step result
        step_result = StepResult(
            step_number=step_number,
            step_name=step_name,
            success=success,
            start_time=start_time,
            end_time=end_time,
            duration=end_time - start_time,
            before_snapshot=before_snapshot,
            after_snapshot=after_snapshot,
            state_diff=state_diff,
            log_files=log_files,
            error_message=error_message
        )
        
        self.step_results.append(step_result)
        
        status = "✅ SUCCESS" if success else "❌ FAILED"
        logger.info(f"Step {step_number} completed: {status} (Duration: {step_result.duration})")
        
        return step_result
    
    def handle_failure(self, step_number: int, error: Exception) -> None:
        """
        Handle test step failure and generate partial report.
        
        Args:
            step_number: Failed step number
            error: Exception that caused the failure
        """
        logger.error(f"Test failed at Step {step_number}: {error}")
        
        # Generate partial report
        self.test_end_time = datetime.now()
        
        report = self.report_generator.generate_report(
            test_results=self.step_results,
            timing_metrics=self.timing_recorder.get_operation_metrics(),
            api_statistics=self.api_monitor.get_api_statistics(),
            config=self.config.to_dict(),
            test_start_time=self.test_start_time,
            test_end_time=self.test_end_time,
            isolation_results=self.isolation_results
        )
        
        # Export partial report
        self.report_generator.export_report(
            report,
            markdown_filename="partial_test_report.md",
            json_filename="partial_test_report.json"
        )
        
        logger.info("Partial test report generated due to failure")
    
    def run_initial_cleanup(self) -> bool:
        """
        Execute Step 1: Initial Cleanup.
        
        Runs cleanup-all-labs script to ensure clean starting state.
        
        Returns:
            True if cleanup succeeded, False otherwise
        """
        logger.info("Executing initial cleanup...")
        
        # Path to cleanup script (relative to repository root)
        cleanup_script = Path("../scripts/cleanup-all-labs.sh")
        
        if not cleanup_script.exists():
            logger.error(f"Cleanup script not found: {cleanup_script}")
            return False
        
        # Ensure script is executable
        if not self.script_executor.verify_executable(cleanup_script):
            self.script_executor.make_executable(cleanup_script)
        
        # Create log file
        log_file = self.log_collector.create_log_file("initial_cleanup")
        
        # Execute cleanup script
        # The script_executor will automatically wrap cleanup scripts with "yes yes |"
        args = ["--profile", self.config.aws_profile, "-y"]
        
        try:
            result = self.script_executor.execute_script(
                cleanup_script,
                args,
                log_file
            )
            
            # For initial cleanup, accept exit code 1 if there are no lab resources
            # Exit code 1 typically means "some resources remain" (like CDK bootstrap buckets)
            # which is acceptable for initial cleanup
            if result.success or result.exit_code == 1:
                logger.info("Initial cleanup completed successfully")
                return True
            else:
                logger.error(f"Initial cleanup failed with exit code {result.exit_code}")
                return False
                
        except Exception as e:
            logger.error(f"Initial cleanup failed with exception: {e}", exc_info=True)
            return False
    
    def run_full_deployment(self) -> bool:
        """
        Execute Step 2: Full Deployment.
        
        Runs deploy-all-labs script with parallel mode to deploy all labs.
        
        Returns:
            True if deployment succeeded, False otherwise
        """
        logger.info("Executing full deployment...")
        
        # Path to deployment script (relative to repository root)
        deploy_script = Path("../scripts/deploy-all-labs.sh")
        
        if not deploy_script.exists():
            logger.error(f"Deployment script not found: {deploy_script}")
            return False
        
        # Ensure script is executable
        if not self.script_executor.verify_executable(deploy_script):
            self.script_executor.make_executable(deploy_script)
        
        # Create log file
        log_file = self.log_collector.create_log_file("full_deployment")
        
        # Build arguments
        args = [
            "--email", self.config.email,
            "--profile", self.config.aws_profile
        ]
        
        # Add tenant email if provided
        if self.config.tenant_email:
            args.extend(["--tenant-email", self.config.tenant_email])
        
        # Add parallel mode flag (enabled by default)
        if self.config.parallel_mode:
            args.append("--parallel")
        else:
            args.append("--sequential")
        
        try:
            result = self.script_executor.execute_script(
                deploy_script,
                args,
                log_file
            )
            
            if result.success:
                logger.info("Full deployment completed successfully")
                
                # Verify all stacks reached CREATE_COMPLETE
                return self._verify_deployment_stacks()
            else:
                logger.error(f"Full deployment failed with exit code {result.exit_code}")
                return False
                
        except Exception as e:
            logger.error(f"Full deployment failed with exception: {e}", exc_info=True)
            return False
    
    def _verify_deployment_stacks(self) -> bool:
        """
        Verify all CloudFormation stacks reached CREATE_COMPLETE status.
        
        Note: Lab5, Lab6, and Lab7 may create additional tenant stacks dynamically.
        This method only verifies the base stacks that are always created.
        
        Returns:
            True if all stacks are in CREATE_COMPLETE state
        """
        import time
        
        logger.info("Verifying deployment stack statuses...")
        
        # Expected base stacks for all labs
        # Note: Lab5, Lab6, and Lab7 may create additional tenant stacks dynamically
        expected_stacks = [
            "serverless-saas-lab1",
            "serverless-saas-lab2",
            "serverless-saas-shared-lab3",
            "serverless-saas-tenant-lab3",
            "serverless-saas-shared-lab4",
            "serverless-saas-tenant-lab4",
            "serverless-saas-shared-lab5",
            "serverless-saas-pipeline-lab5",  # Lab5 pipeline (creates tenant stacks: stack-<tenantId>-lab5)
            "serverless-saas-shared-lab6",
            "serverless-saas-pipeline-lab6",  # Lab6 pipeline (creates tenant stacks: stack-.*-lab6)
            "serverless-saas-lab7",
            "stack-pooled-lab7",  # Lab7 pooled tenant stack
        ]
        
        # Retry logic to handle eventual consistency
        max_retries = 3
        retry_delay = 10  # seconds
        
        for attempt in range(max_retries):
            if attempt > 0:
                logger.info(f"Retry attempt {attempt + 1}/{max_retries} after {retry_delay}s delay...")
                time.sleep(retry_delay)
            
            # Get all stacks
            stacks = self.resource_tracker.get_cloudformation_stacks()
            stack_names = {stack.stack_name for stack in stacks}
            
            # Check if all expected stacks exist
            missing_stacks = set(expected_stacks) - stack_names
            if missing_stacks:
                logger.warning(f"Missing stacks (attempt {attempt + 1}): {missing_stacks}")
                if attempt < max_retries - 1:
                    continue  # Retry
                else:
                    logger.error(f"Missing stacks after {max_retries} attempts: {missing_stacks}")
                    return False
            
            # Check if all stacks are in CREATE_COMPLETE state
            failed_stacks = []
            for stack in stacks:
                if stack.stack_name in expected_stacks:
                    if stack.stack_status != "CREATE_COMPLETE":
                        failed_stacks.append(f"{stack.stack_name}: {stack.stack_status}")
            
            if failed_stacks:
                logger.error(f"Stacks not in CREATE_COMPLETE state: {failed_stacks}")
                return False
            
            # Log any additional tenant stacks found (Lab5, Lab6, Lab7)
            tenant_stacks = [
                stack.stack_name for stack in stacks
                if stack.stack_name not in expected_stacks
            ]
            if tenant_stacks:
                logger.info(f"Found {len(tenant_stacks)} additional tenant stacks: {tenant_stacks}")
            
            logger.info("All deployment stacks verified successfully")
            return True
        
        return False
    
    def run_lab_isolation_test(self, lab_number: int) -> bool:
        """
        Execute lab isolation test by deleting a specific lab.
        
        Args:
            lab_number: Lab number (1-7)
            
        Returns:
            True if isolation test passed, False otherwise
        """
        logger.info(f"Executing Lab{lab_number} isolation test...")
        
        # Determine stack name based on lab number
        if lab_number in [1, 2, 7]:
            stack_name = f"serverless-saas-lab{lab_number}"
        elif lab_number in [3, 4]:
            # Labs 3-4 have shared and tenant stacks
            stack_name = f"serverless-saas-lab{lab_number}"
        elif lab_number == 5:
            # Lab5 has shared and pipeline stacks + dynamic tenant stacks (stack-<tenantId>-lab5)
            stack_name = f"serverless-saas-lab{lab_number}"
        elif lab_number == 6:
            # Lab6 has shared, pipeline, and pooled stacks + dynamic tenant stacks (stack-.*-lab6)
            stack_name = f"serverless-saas-lab{lab_number}"
        else:
            logger.error(f"Invalid lab number: {lab_number}")
            return False
        
        # Path to lab cleanup script (relative to repository root)
        cleanup_script = Path(f"../Lab{lab_number}/scripts/cleanup.sh")
        
        if not cleanup_script.exists():
            logger.error(f"Cleanup script not found: {cleanup_script}")
            return False
        
        # Ensure script is executable
        if not self.script_executor.verify_executable(cleanup_script):
            self.script_executor.make_executable(cleanup_script)
        
        # Create log file
        log_file = self.log_collector.create_log_file(f"lab{lab_number}_cleanup")
        
        # Build arguments
        args = [
            "--stack-name", stack_name,
            "--profile", self.config.aws_profile,
            "-y"
        ]
        
        try:
            result = self.script_executor.execute_script(
                cleanup_script,
                args,
                log_file
            )
            
            if result.success:
                logger.info(f"Lab{lab_number} cleanup completed successfully")
                return True
            else:
                logger.error(f"Lab{lab_number} cleanup failed with exit code {result.exit_code}")
                return False
                
        except Exception as e:
            logger.error(f"Lab{lab_number} cleanup failed with exception: {e}", exc_info=True)
            return False
    
    def run_final_cleanup(self) -> bool:
        """
        Execute Step 10: Final Cleanup.
        
        Runs cleanup-all-labs script to remove all remaining resources.
        
        Returns:
            True if cleanup succeeded, False otherwise
        """
        logger.info("Executing final cleanup...")
        
        # Path to cleanup script (relative to repository root)
        cleanup_script = Path("../scripts/cleanup-all-labs.sh")
        
        if not cleanup_script.exists():
            logger.error(f"Cleanup script not found: {cleanup_script}")
            return False
        
        # Ensure script is executable
        if not self.script_executor.verify_executable(cleanup_script):
            self.script_executor.make_executable(cleanup_script)
        
        # Create log file
        log_file = self.log_collector.create_log_file("final_cleanup")
        
        # Execute cleanup script
        args = ["--profile", self.config.aws_profile, "-y"]
        
        try:
            result = self.script_executor.execute_script(
                cleanup_script,
                args,
                log_file
            )
            
            # For final cleanup, accept exit code 1 if there are no lab resources
            # Exit code 1 typically means "some resources remain" (like CDK bootstrap buckets)
            # which is acceptable for final cleanup
            if result.success or result.exit_code == 1:
                logger.info("Final cleanup completed successfully")
                return True
            else:
                logger.error(f"Final cleanup failed with exit code {result.exit_code}")
                return False
                
        except Exception as e:
            logger.error(f"Final cleanup failed with exception: {e}", exc_info=True)
            return False
    
    def run_test_suite(self) -> TestReport:
        """
        Execute complete 10-step test workflow.
        
        Returns:
            TestReport with all results
        """
        logger.info("=" * 80)
        logger.info("Starting End-to-End AWS Testing Suite")
        logger.info("=" * 80)
        
        # Start test timing
        self.test_start_time = datetime.now()
        self.timing_recorder.start_test()
        
        # Enable API monitoring
        self.api_monitor.enable_monitoring()
        
        try:
            # Step 1: Initial Cleanup
            step1_result = self.run_step(
                step_number=1,
                step_name="Initial Cleanup",
                operation=self.run_initial_cleanup
            )
            
            if not step1_result.success:
                logger.error("Initial cleanup failed, aborting test suite")
                raise RuntimeError("Initial cleanup failed")
            
            # Step 2: Full Deployment
            step2_result = self.run_step(
                step_number=2,
                step_name="Full Deployment",
                operation=self.run_full_deployment
            )
            
            if not step2_result.success:
                logger.error("Full deployment failed, aborting test suite")
                raise RuntimeError("Full deployment failed")
            
            # Steps 3-9: Lab Isolation Tests
            for lab_number in range(1, 8):
                step_number = lab_number + 2  # Steps 3-9
                step_result = self.run_step(
                    step_number=step_number,
                    step_name=f"Lab{lab_number} Isolation Test",
                    operation=lambda ln=lab_number: self.run_lab_isolation_test(ln)
                )
                
                # Verify isolation after deletion
                if step_result.success:
                    isolation_result = self.state_comparator.verify_isolation(
                        step_result.before_snapshot,
                        step_result.after_snapshot,
                        f"Lab{lab_number}"
                    )
                    self.isolation_results.append(isolation_result)
                    
                    if not isolation_result.deleted_lab_resources_removed:
                        logger.warning(f"Lab{lab_number} resources not fully removed")
                    
                    if not isolation_result.other_labs_unaffected:
                        logger.warning(f"Lab{lab_number} deletion affected other labs")
                    
                    if isolation_result.orphaned_resources:
                        logger.warning(
                            f"Found {len(isolation_result.orphaned_resources)} orphaned resources "
                            f"after Lab{lab_number} deletion"
                        )
                else:
                    logger.error(f"Lab{lab_number} isolation test failed")
            
            # Step 10: Final Cleanup
            step10_result = self.run_step(
                step_number=10,
                step_name="Final Cleanup",
                operation=self.run_final_cleanup
            )
            
            if not step10_result.success:
                logger.warning("Final cleanup failed, but test suite completed")
            
            logger.info("Test suite execution completed")
            
        except Exception as e:
            logger.error(f"Test suite failed: {e}", exc_info=True)
            self.handle_failure(1, e)
            raise
        
        finally:
            # End test timing
            self.test_end_time = datetime.now()
            self.timing_recorder.end_test()
            
            # Disable API monitoring
            self.api_monitor.disable_monitoring()
        
        # Generate final report
        report = self.report_generator.generate_report(
            test_results=self.step_results,
            timing_metrics=self.timing_recorder.get_operation_metrics(),
            api_statistics=self.api_monitor.get_api_statistics(),
            config=self.config.to_dict(),
            test_start_time=self.test_start_time,
            test_end_time=self.test_end_time,
            isolation_results=self.isolation_results
        )
        
        # Export report in both formats
        markdown_path, json_path = self.report_generator.export_report(report)
        
        logger.info("=" * 80)
        logger.info("Test Suite Complete")
        logger.info(f"Markdown Report: {markdown_path}")
        logger.info(f"JSON Report: {json_path}")
        logger.info("=" * 80)
        
        return report
