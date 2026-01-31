"""
Test Report Generator component for end-to-end AWS testing system.

This module generates comprehensive test reports in multiple formats.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from .models import (
    APIStatistics,
    IsolationResult,
    StepResult,
    TestReport,
    TimingMetric,
)

logger = logging.getLogger(__name__)


class TestReportGenerator:
    """
    Generates comprehensive test reports with all metrics and results.
    
    Supports both human-readable (Markdown) and machine-parseable (JSON) formats.
    """
    
    def __init__(self, report_directory: Path):
        """
        Initialize report generator.
        
        Args:
            report_directory: Directory to save reports
        """
        self.report_directory = report_directory
        self.report_directory.mkdir(parents=True, exist_ok=True)
    
    def generate_report(
        self,
        test_results: List[StepResult],
        timing_metrics: List[TimingMetric],
        api_statistics: Optional[APIStatistics],
        config: dict,
        test_start_time: datetime,
        test_end_time: datetime,
        isolation_results: Optional[List[IsolationResult]] = None
    ) -> TestReport:
        """
        Generate comprehensive test report.
        
        Args:
            test_results: List of step results
            timing_metrics: List of timing metrics
            api_statistics: API call statistics
            config: Test configuration
            test_start_time: Test start time
            test_end_time: Test end time
            isolation_results: List of isolation verification results
            
        Returns:
            TestReport object
        """
        total_duration = test_end_time - test_start_time
        overall_success = all(result.success for result in test_results)
        
        # Generate summary
        summary = self._generate_summary(
            test_results, total_duration, overall_success
        )
        
        report = TestReport(
            test_start_time=test_start_time,
            test_end_time=test_end_time,
            total_duration=total_duration,
            config=config,
            step_results=test_results,
            timing_metrics=timing_metrics,
            api_statistics=api_statistics,
            isolation_results=isolation_results or [],
            overall_success=overall_success,
            summary=summary
        )
        
        logger.info(f"Generated test report: {summary}")
        return report
    
    def _generate_summary(
        self,
        test_results: List[StepResult],
        total_duration,
        overall_success: bool
    ) -> str:
        """Generate summary text for the report."""
        total_steps = len(test_results)
        successful_steps = sum(1 for r in test_results if r.success)
        failed_steps = total_steps - successful_steps
        
        if overall_success:
            return (
                f"All {total_steps} test steps completed successfully "
                f"in {total_duration}"
            )
        else:
            return (
                f"{failed_steps} of {total_steps} test steps failed "
                f"(Duration: {total_duration})"
            )
    
    def export_markdown(self, report: TestReport, filename: str = "test_report.md") -> Path:
        """
        Export report in Markdown format.
        
        Args:
            report: TestReport to export
            filename: Output filename
            
        Returns:
            Path to saved report file
        """
        output_path = self.report_directory / filename
        
        with open(output_path, 'w') as f:
            # Header
            f.write("# End-to-End AWS Testing Report\n\n")
            f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            
            # Summary section
            self._write_summary_section(f, report)
            
            # Configuration section
            self._write_configuration_section(f, report)
            
            # Timing metrics section
            self._write_timing_section(f, report)
            
            # Step results section
            self._write_step_results_section(f, report)
            
            # Resource changes section
            self._write_resource_changes_section(f, report)
            
            # API statistics section
            if report.api_statistics:
                self._write_api_statistics_section(f, report)
            
            # Isolation verification section
            if report.isolation_results:
                self._write_isolation_section(f, report)
            
            # Failures section
            self._write_failures_section(f, report)
        
        logger.info(f"Exported Markdown report to {output_path}")
        return output_path
    
    def _write_summary_section(self, f, report: TestReport):
        """Write summary section to Markdown file."""
        f.write("## Summary\n\n")
        
        status_emoji = "✅" if report.overall_success else "❌"
        f.write(f"**Status:** {status_emoji} {report.summary}\n\n")
        
        f.write(f"- **Start Time:** {report.test_start_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- **End Time:** {report.test_end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- **Total Duration:** {report.total_duration}\n")
        f.write(f"- **Total Steps:** {len(report.step_results)}\n")
        
        successful = sum(1 for r in report.step_results if r.success)
        failed = len(report.step_results) - successful
        f.write(f"- **Successful Steps:** {successful}\n")
        f.write(f"- **Failed Steps:** {failed}\n\n")
    
    def _write_configuration_section(self, f, report: TestReport):
        """Write configuration section to Markdown file."""
        f.write("## Configuration\n\n")
        f.write("```yaml\n")
        for key, value in report.config.items():
            f.write(f"{key}: {value}\n")
        f.write("```\n\n")
    
    def _write_timing_section(self, f, report: TestReport):
        """Write timing metrics section to Markdown file."""
        f.write("## Timing Metrics\n\n")
        
        if not report.timing_metrics:
            f.write("*No timing metrics recorded*\n\n")
            return
        
        f.write("| Operation | Duration | Duration (seconds) |\n")
        f.write("|-----------|----------|--------------------|\n")
        
        for metric in report.timing_metrics:
            f.write(
                f"| {metric.operation_name} | {metric.duration} | "
                f"{metric.duration_seconds:.2f}s |\n"
            )
        f.write("\n")
        
        # Add slowest operations
        sorted_metrics = sorted(
            report.timing_metrics,
            key=lambda m: m.duration_seconds,
            reverse=True
        )
        f.write("### Slowest Operations\n\n")
        for i, metric in enumerate(sorted_metrics[:5], 1):
            f.write(
                f"{i}. **{metric.operation_name}**: {metric.duration} "
                f"({metric.duration_seconds:.2f}s)\n"
            )
        f.write("\n")
    
    def _write_step_results_section(self, f, report: TestReport):
        """Write step results section to Markdown file."""
        f.write("## Test Steps\n\n")
        
        for result in report.step_results:
            status_emoji = "✅" if result.success else "❌"
            f.write(f"### {status_emoji} Step {result.step_number}: {result.step_name}\n\n")
            
            f.write(f"- **Status:** {'Success' if result.success else 'Failed'}\n")
            f.write(f"- **Duration:** {result.duration}\n")
            f.write(f"- **Start Time:** {result.start_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"- **End Time:** {result.end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            
            if result.error_message:
                f.write(f"\n**Error:**\n```\n{result.error_message}\n```\n")
            
            # Log files
            if result.log_files:
                f.write(f"\n**Log Files:**\n")
                for log_file in result.log_files:
                    f.write(f"- `{log_file}`\n")
            
            f.write("\n")
    
    def _write_resource_changes_section(self, f, report: TestReport):
        """Write resource state changes section to Markdown file."""
        f.write("## Resource State Changes\n\n")
        
        for result in report.step_results:
            if not result.state_diff:
                continue
            
            diff = result.state_diff
            
            f.write(f"### Step {result.step_number}: {result.step_name}\n\n")
            
            # Created resources
            if diff.created_resources:
                f.write(f"**Created Resources:** {len(diff.created_resources)}\n")
                for resource in diff.created_resources[:10]:  # Limit to first 10
                    f.write(f"- {resource.resource_type}: {resource.resource_name}\n")
                if len(diff.created_resources) > 10:
                    f.write(f"- *(and {len(diff.created_resources) - 10} more)*\n")
                f.write("\n")
            
            # Deleted resources
            if diff.deleted_resources:
                f.write(f"**Deleted Resources:** {len(diff.deleted_resources)}\n")
                for resource in diff.deleted_resources[:10]:
                    f.write(f"- {resource.resource_type}: {resource.resource_name}\n")
                if len(diff.deleted_resources) > 10:
                    f.write(f"- *(and {len(diff.deleted_resources) - 10} more)*\n")
                f.write("\n")
            
            # Modified resources
            if diff.modified_resources:
                f.write(f"**Modified Resources:** {len(diff.modified_resources)}\n\n")
    
    def _write_api_statistics_section(self, f, report: TestReport):
        """Write API statistics section to Markdown file."""
        f.write("## API Call Statistics\n\n")
        
        stats = report.api_statistics
        
        f.write(f"- **Total API Calls:** {stats.total_calls}\n")
        f.write(f"- **Successful Calls:** {stats.successful_calls}\n")
        f.write(f"- **Failed Calls:** {stats.failed_calls}\n")
        
        if stats.total_calls > 0:
            success_rate = (stats.successful_calls / stats.total_calls) * 100
            f.write(f"- **Overall Success Rate:** {success_rate:.2f}%\n\n")
        
        # Calls by service
        if stats.calls_by_service:
            f.write("### Calls by Service\n\n")
            f.write("| Service | Total Calls | Success Rate |\n")
            f.write("|---------|-------------|---------------|\n")
            
            for service, count in sorted(
                stats.calls_by_service.items(),
                key=lambda x: x[1],
                reverse=True
            ):
                success_rate = stats.success_rate_by_service.get(service, 0.0)
                f.write(f"| {service} | {count} | {success_rate:.2f}% |\n")
            f.write("\n")
        
        # Failed calls
        if stats.failed_calls_list:
            f.write("### Failed API Calls\n\n")
            for call in stats.failed_calls_list[:20]:  # Limit to first 20
                f.write(
                    f"- **{call.service}.{call.operation}**: "
                    f"Status {call.status_code}"
                )
                if call.error_code:
                    f.write(f" - {call.error_code}")
                if call.error_message:
                    f.write(f" - {call.error_message[:100]}")
                f.write(f" (Request ID: {call.request_id})\n")
            
            if len(stats.failed_calls_list) > 20:
                f.write(f"\n*(and {len(stats.failed_calls_list) - 20} more failed calls)*\n")
            f.write("\n")
    
    def _write_isolation_section(self, f, report: TestReport):
        """Write isolation verification section to Markdown file."""
        f.write("## Lab Isolation Verification\n\n")
        
        for result in report.isolation_results:
            status_emoji = "✅" if (
                result.deleted_lab_resources_removed and
                result.other_labs_unaffected
            ) else "❌"
            
            f.write(f"### {status_emoji} {result.deleted_lab}\n\n")
            
            f.write(
                f"- **Deleted Lab Resources Removed:** "
                f"{'Yes' if result.deleted_lab_resources_removed else 'No'}\n"
            )
            f.write(
                f"- **Other Labs Unaffected:** "
                f"{'Yes' if result.other_labs_unaffected else 'No'}\n"
            )
            
            if result.orphaned_resources:
                f.write(f"- **Orphaned Resources Found:** {len(result.orphaned_resources)}\n")
                for resource in result.orphaned_resources[:5]:
                    f.write(f"  - {resource.resource_type}: {resource.resource_name}\n")
            
            f.write("\n")
    
    def _write_failures_section(self, f, report: TestReport):
        """Write failures section to Markdown file."""
        failed_steps = [r for r in report.step_results if not r.success]
        
        if not failed_steps:
            return
        
        f.write("## ⚠️ Failures\n\n")
        
        for result in failed_steps:
            f.write(f"### Step {result.step_number}: {result.step_name}\n\n")
            
            if result.error_message:
                f.write(f"**Error Message:**\n```\n{result.error_message}\n```\n\n")
            
            if result.log_files:
                f.write("**Check these log files for details:**\n")
                for log_file in result.log_files:
                    f.write(f"- `{log_file}`\n")
                f.write("\n")
    
    def export_json(self, report: TestReport, filename: str = "test_report.json") -> Path:
        """
        Export report in JSON format.
        
        Args:
            report: TestReport to export
            filename: Output filename
            
        Returns:
            Path to saved report file
        """
        output_path = self.report_directory / filename
        
        # Convert report to dictionary
        report_dict = {
            "test_start_time": report.test_start_time.isoformat(),
            "test_end_time": report.test_end_time.isoformat(),
            "total_duration_seconds": report.total_duration.total_seconds(),
            "config": report.config,
            "overall_success": report.overall_success,
            "summary": report.summary,
            "step_results": [
                {
                    "step_number": r.step_number,
                    "step_name": r.step_name,
                    "success": r.success,
                    "start_time": r.start_time.isoformat(),
                    "end_time": r.end_time.isoformat(),
                    "duration_seconds": r.duration.total_seconds(),
                    "error_message": r.error_message,
                    "log_files": [str(f) for f in r.log_files],
                    "created_resources_count": len(r.state_diff.created_resources) if r.state_diff else 0,
                    "deleted_resources_count": len(r.state_diff.deleted_resources) if r.state_diff else 0,
                }
                for r in report.step_results
            ],
            "timing_metrics": [
                {
                    "operation_name": m.operation_name,
                    "start_time": m.start_time.isoformat(),
                    "end_time": m.end_time.isoformat(),
                    "duration_seconds": m.duration_seconds,
                }
                for m in report.timing_metrics
            ],
        }
        
        # Add API statistics if available
        if report.api_statistics:
            report_dict["api_statistics"] = {
                "total_calls": report.api_statistics.total_calls,
                "successful_calls": report.api_statistics.successful_calls,
                "failed_calls": report.api_statistics.failed_calls,
                "calls_by_service": report.api_statistics.calls_by_service,
                "success_rate_by_service": report.api_statistics.success_rate_by_service,
            }
        
        # Add isolation results if available
        if report.isolation_results:
            report_dict["isolation_results"] = [
                {
                    "deleted_lab": r.deleted_lab,
                    "deleted_lab_resources_removed": r.deleted_lab_resources_removed,
                    "other_labs_unaffected": r.other_labs_unaffected,
                    "orphaned_resources_count": len(r.orphaned_resources),
                }
                for r in report.isolation_results
            ]
        
        with open(output_path, 'w') as f:
            json.dump(report_dict, f, indent=2)
        
        logger.info(f"Exported JSON report to {output_path}")
        return output_path
    
    def export_report(
        self,
        report: TestReport,
        markdown_filename: str = "test_report.md",
        json_filename: str = "test_report.json"
    ) -> tuple[Path, Path]:
        """
        Export report in both Markdown and JSON formats.
        
        Args:
            report: TestReport to export
            markdown_filename: Markdown output filename
            json_filename: JSON output filename
            
        Returns:
            Tuple of (markdown_path, json_path)
        """
        markdown_path = self.export_markdown(report, markdown_filename)
        json_path = self.export_json(report, json_filename)
        
        logger.info(
            f"Exported test report in both formats: "
            f"Markdown={markdown_path}, JSON={json_path}"
        )
        
        return markdown_path, json_path
