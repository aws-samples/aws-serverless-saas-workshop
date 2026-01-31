#!/usr/bin/env python3
"""
Generate a high-level summary report from end_to_end_test_report.json

This script creates a SUMMARY.md file with key insights and statistics
from the test execution.
"""

import json
from pathlib import Path
from datetime import datetime, timedelta


def format_duration(seconds):
    """Format duration in seconds to human-readable format."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        minutes = seconds / 60
        return f"{minutes:.1f}m"
    else:
        hours = seconds / 3600
        minutes = (seconds % 3600) / 60
        return f"{hours:.0f}h {minutes:.0f}m"


def generate_summary_report():
    """Generate summary report from the test report JSON."""
    # Paths
    report_dir = Path(__file__).parent
    report_file = report_dir / "end_to_end_test_report.json"
    summary_file = report_dir / "SUMMARY.md"
    
    # Read the test report
    print(f"Reading test report from: {report_file}")
    with open(report_file, 'r') as f:
        report_data = json.load(f)
    
    # Extract key data
    test_name = report_data.get("test_name", "Unknown Test")
    timestamp = report_data.get("timestamp", "Unknown")
    dry_run = report_data.get("dry_run", False)
    aws_profile = report_data.get("aws_profile", "N/A")
    total_steps = report_data.get("total_steps", 0)
    passed_steps = report_data.get("passed_steps", 0)
    failed_steps = report_data.get("failed_steps", 0)
    total_duration = report_data.get("total_duration_seconds", 0)
    steps = report_data.get("steps", [])
    
    # Calculate statistics
    pass_rate = (passed_steps / total_steps * 100) if total_steps > 0 else 0
    
    # Find slowest steps
    slowest_steps = sorted(steps, key=lambda x: x.get("duration_seconds", 0), reverse=True)[:5]
    
    # Find failed steps
    failed_step_details = [s for s in steps if not s.get("success", True)]
    
    # Calculate resource changes
    initial_resources = steps[0].get("resources_before", {}).get("total_count", 0) if steps else 0
    final_resources = steps[-1].get("resources_after", {}).get("total_count", 0) if steps else 0
    
    # Generate summary
    print(f"Generating summary report: {summary_file}")
    with open(summary_file, 'w') as f:
        # Header
        f.write("# End-to-End Test Execution Summary\n\n")
        f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("---\n\n")
        
        # Test Overview
        f.write("## Test Overview\n\n")
        f.write(f"- **Test Name:** {test_name}\n")
        f.write(f"- **Execution Time:** {timestamp}\n")
        f.write(f"- **Mode:** {'Dry-Run (Simulated)' if dry_run else 'Real AWS'}\n")
        if not dry_run:
            f.write(f"- **AWS Profile:** {aws_profile}\n")
        f.write(f"- **Total Duration:** {format_duration(total_duration)} ({total_duration:.1f} seconds)\n")
        f.write(f"- **Total Steps:** {total_steps}\n\n")
        
        # Test Results
        f.write("## Test Results\n\n")
        status_emoji = "✅" if failed_steps == 0 else "❌"
        f.write(f"### Overall Status: {status_emoji} {'PASSED' if failed_steps == 0 else 'FAILED'}\n\n")
        f.write(f"- **Passed Steps:** {passed_steps} / {total_steps} ({pass_rate:.1f}%)\n")
        f.write(f"- **Failed Steps:** {failed_steps} / {total_steps}\n\n")
        
        # Pass/Fail Visualization
        f.write("```\n")
        f.write("Test Steps: ")
        for step in steps:
            f.write("✓" if step.get("success", True) else "✗")
        f.write("\n```\n\n")
        
        # Failed Steps Details
        if failed_step_details:
            f.write("## ❌ Failed Steps\n\n")
            for step in failed_step_details:
                step_num = step.get("step_number", "?")
                step_name = step.get("step_name", "Unknown")
                error_msg = step.get("error_message", "No error message")
                duration = step.get("duration_seconds", 0)
                
                f.write(f"### Step {step_num}: {step_name}\n\n")
                f.write(f"- **Duration:** {format_duration(duration)}\n")
                f.write(f"- **Error:** {error_msg}\n")
                f.write(f"- **Log File:** `logs/step_{step_num:02d}_{step_name.lower().replace(' ', '_').replace('(', '').replace(')', '')}.log`\n\n")
                
                # Resource impact
                resources_before = step.get("resources_before", {}).get("total_count", 0)
                resources_after = step.get("resources_after", {}).get("total_count", 0)
                f.write(f"- **Resources Before:** {resources_before}\n")
                f.write(f"- **Resources After:** {resources_after}\n")
                f.write(f"- **Change:** {resources_after - resources_before:+d}\n\n")
        
        # Performance Analysis
        f.write("## ⏱️ Performance Analysis\n\n")
        f.write(f"**Total Execution Time:** {format_duration(total_duration)}\n\n")
        
        f.write("### Slowest Steps\n\n")
        f.write("| Step | Name | Duration |\n")
        f.write("|------|------|----------|\n")
        for step in slowest_steps:
            step_num = step.get("step_number", "?")
            step_name = step.get("step_name", "Unknown")
            duration = step.get("duration_seconds", 0)
            f.write(f"| {step_num} | {step_name} | {format_duration(duration)} |\n")
        f.write("\n")
        
        # Resource Tracking
        f.write("## 📊 Resource Tracking\n\n")
        f.write(f"- **Initial Resources:** {initial_resources}\n")
        f.write(f"- **Final Resources:** {final_resources}\n")
        f.write(f"- **Net Change:** {final_resources - initial_resources:+d}\n\n")
        
        f.write("### Resource Changes by Step\n\n")
        f.write("| Step | Name | Before | After | Deleted | Change |\n")
        f.write("|------|------|--------|-------|---------|--------|\n")
        for step in steps:
            step_num = step.get("step_number", "?")
            step_name = step.get("step_name", "Unknown")[:30]  # Truncate long names
            before = step.get("resources_before", {}).get("total_count", 0)
            after = step.get("resources_after", {}).get("total_count", 0)
            deleted = step.get("resources_deleted", {}).get("total_count", 0)
            change = after - before
            f.write(f"| {step_num} | {step_name} | {before} | {after} | {deleted} | {change:+d} |\n")
        f.write("\n")
        
        # Step-by-Step Summary
        f.write("## 📝 Step-by-Step Summary\n\n")
        for step in steps:
            step_num = step.get("step_number", "?")
            step_name = step.get("step_name", "Unknown")
            success = step.get("success", True)
            duration = step.get("duration_seconds", 0)
            status_icon = "✅" if success else "❌"
            
            f.write(f"### {status_icon} Step {step_num}: {step_name}\n\n")
            f.write(f"- **Status:** {'Passed' if success else 'Failed'}\n")
            f.write(f"- **Duration:** {format_duration(duration)}\n")
            
            # Resource summary
            resources_before = step.get("resources_before", {})
            resources_after = step.get("resources_after", {})
            resources_deleted = step.get("resources_deleted", {})
            
            f.write(f"- **Resources:** {resources_before.get('total_count', 0)} → {resources_after.get('total_count', 0)}")
            if resources_deleted.get('total_count', 0) > 0:
                f.write(f" (deleted: {resources_deleted.get('total_count', 0)})")
            f.write("\n")
            
            # Breakdown
            f.write("  - Stacks: ")
            f.write(f"{len(resources_before.get('stacks', []))} → {len(resources_after.get('stacks', []))}\n")
            f.write("  - S3 Buckets: ")
            f.write(f"{len(resources_before.get('s3_buckets', []))} → {len(resources_after.get('s3_buckets', []))}\n")
            f.write("  - Log Groups: ")
            f.write(f"{len(resources_before.get('log_groups', []))} → {len(resources_after.get('log_groups', []))}\n")
            f.write("  - Cognito Pools: ")
            f.write(f"{len(resources_before.get('cognito_pools', []))} → {len(resources_after.get('cognito_pools', []))}\n")
            
            # Warnings
            warnings = step.get("warnings", [])
            if warnings:
                f.write(f"- **Warnings:** {len(warnings)}\n")
                for warning in warnings[:3]:  # Show first 3 warnings
                    f.write(f"  - {warning}\n")
                if len(warnings) > 3:
                    f.write(f"  - ... and {len(warnings) - 3} more\n")
            
            f.write("\n")
        
        # Recommendations
        f.write("## 💡 Recommendations\n\n")
        if failed_steps == 0:
            f.write("✅ **All tests passed!** The cleanup isolation is working correctly.\n\n")
            f.write("**Next Steps:**\n")
            f.write("- Review performance metrics for optimization opportunities\n")
            f.write("- Archive this report for historical tracking\n")
            f.write("- Consider running tests periodically to catch regressions\n\n")
        else:
            f.write("❌ **Some tests failed.** Review the failed steps above.\n\n")
            f.write("**Action Items:**\n")
            f.write("1. Review detailed logs for failed steps\n")
            f.write("2. Check error messages and resource states\n")
            f.write("3. Verify AWS permissions and quotas\n")
            f.write("4. Re-run failed steps individually for debugging\n")
            f.write("5. Fix identified issues and re-run full test suite\n\n")
        
        # Quick Reference
        f.write("## 🔗 Quick Reference\n\n")
        f.write("**View Full Report:**\n")
        f.write("```bash\n")
        f.write("cat end_to_end_test_report.json | jq .\n")
        f.write("```\n\n")
        
        f.write("**View Specific Step:**\n")
        f.write("```bash\n")
        f.write("cat logs/step_XX_<step_name>.log\n")
        f.write("```\n\n")
        
        f.write("**Find Failed Steps:**\n")
        f.write("```bash\n")
        f.write("grep -l \"Success: False\" logs/step_*.log\n")
        f.write("```\n\n")
        
        f.write("**Re-run Test:**\n")
        f.write("```bash\n")
        if dry_run:
            f.write("./run_end_to_end_test.sh --dry-run\n")
        else:
            f.write(f"./run_end_to_end_test.sh --real-aws --profile {aws_profile}\n")
        f.write("```\n\n")
        
        # Footer
        f.write("---\n\n")
        f.write("*This summary was automatically generated from the test execution data.*\n")
    
    print(f"✓ Summary report created: {summary_file}")
    print()
    print("Quick view:")
    print(f"  cat {summary_file}")


if __name__ == "__main__":
    generate_summary_report()
