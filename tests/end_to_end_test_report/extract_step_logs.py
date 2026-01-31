#!/usr/bin/env python3
"""
Extract individual step logs from end_to_end_test_report.json

This script reads the test report JSON file and creates individual log files
for each step in the end_to_end_test_report/ directory.

Features:
- Creates individual log files for each test step
- Includes detailed resource information
- Formats output for easy reading
- Preserves all test data in structured format
"""

import json
from pathlib import Path
from datetime import datetime
import sys


def extract_step_logs():
    """Extract step logs from the test report JSON."""
    # Paths
    report_dir = Path(__file__).parent
    report_file = report_dir / "end_to_end_test_report.json"
    logs_dir = report_dir / "logs"
    
    # Check if report file exists
    if not report_file.exists():
        print(f"❌ Error: Report file not found: {report_file}")
        print(f"   Please run the test suite first to generate the report.")
        sys.exit(1)
    
    # Create logs directory if it doesn't exist
    logs_dir.mkdir(parents=True, exist_ok=True)
    
    # Read the test report
    print(f"📖 Reading test report from: {report_file}")
    try:
        with open(report_file, 'r') as f:
            report_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"❌ Error: Invalid JSON in report file: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error reading report file: {e}")
        sys.exit(1)
    
    # Extract steps
    steps = report_data.get("steps", [])
    if not steps:
        print(f"⚠️  Warning: No steps found in the report")
        sys.exit(0)
    
    print(f"📝 Found {len(steps)} steps in the report")
    print()
    
    # Process each step
    for step in steps:
        step_number = step["step_number"]
        step_name = step["step_name"]
        success = step["success"]
        duration = step["duration_seconds"]
        
        # Generate log filename
        step_name_slug = step_name.lower().replace(" ", "_").replace("(", "").replace(")", "")
        log_filename = f"step_{step_number:02d}_{step_name_slug}.log"
        log_filepath = logs_dir / log_filename
        
        status_icon = "✅" if success else "❌"
        print(f"{status_icon} Creating log file: {log_filename}")
        
        # Write log content
        with open(log_filepath, 'w') as f:
            # Header
            f.write("=" * 80 + "\n")
            f.write(f"Step {step_number}: {step_name}\n")
            f.write("=" * 80 + "\n")
            
            # Metadata
            timestamp = step.get('resources_before', {}).get('timestamp', 'N/A')
            f.write(f"Timestamp: {timestamp}\n")
            f.write(f"Success: {success}\n")
            f.write(f"Duration: {duration:.2f} seconds ({duration/60:.2f} minutes)\n")
            f.write("\n")
            
            # Resources summary
            resources_before = step.get("resources_before", {})
            resources_after = step.get("resources_after", {})
            resources_deleted = step.get("resources_deleted", {})
            
            f.write("RESOURCE SUMMARY\n")
            f.write("-" * 80 + "\n")
            f.write(f"Resources Before: {resources_before.get('total_count', 0)}\n")
            f.write(f"  - Stacks: {len(resources_before.get('stacks', []))}\n")
            f.write(f"  - S3 Buckets: {len(resources_before.get('s3_buckets', []))}\n")
            f.write(f"  - Log Groups: {len(resources_before.get('log_groups', []))}\n")
            f.write(f"  - Cognito Pools: {len(resources_before.get('cognito_pools', []))}\n")
            f.write("\n")
            
            f.write(f"Resources After: {resources_after.get('total_count', 0)}\n")
            f.write(f"  - Stacks: {len(resources_after.get('stacks', []))}\n")
            f.write(f"  - S3 Buckets: {len(resources_after.get('s3_buckets', []))}\n")
            f.write(f"  - Log Groups: {len(resources_after.get('log_groups', []))}\n")
            f.write(f"  - Cognito Pools: {len(resources_after.get('cognito_pools', []))}\n")
            f.write("\n")
            
            f.write(f"Resources Deleted: {resources_deleted.get('total_count', 0)}\n")
            f.write(f"  - Stacks: {len(resources_deleted.get('stacks', []))}\n")
            f.write(f"  - S3 Buckets: {len(resources_deleted.get('s3_buckets', []))}\n")
            f.write(f"  - Log Groups: {len(resources_deleted.get('log_groups', []))}\n")
            f.write(f"  - Cognito Pools: {len(resources_deleted.get('cognito_pools', []))}\n")
            f.write("\n")
            
            # Net change
            net_change = resources_after.get('total_count', 0) - resources_before.get('total_count', 0)
            f.write(f"Net Change: {net_change:+d} resources\n")
            f.write("\n")
            
            # Error message
            error_message = step.get("error_message")
            if error_message:
                f.write("ERROR\n")
                f.write("-" * 80 + "\n")
                f.write(f"{error_message}\n")
                f.write("\n")
            
            # Warnings
            warnings = step.get("warnings", [])
            if warnings:
                f.write("WARNINGS\n")
                f.write("-" * 80 + "\n")
                for i, warning in enumerate(warnings, 1):
                    f.write(f"{i}. {warning}\n")
                f.write("\n")
            
            # Detailed resource information
            f.write("=" * 80 + "\n")
            f.write("DETAILED RESOURCE INFORMATION\n")
            f.write("=" * 80 + "\n")
            f.write("\n")
            
            # Resources before
            if resources_before.get('stacks'):
                f.write(f"CloudFormation Stacks Before ({len(resources_before['stacks'])}):\n")
                f.write("-" * 80 + "\n")
                for stack in sorted(resources_before['stacks']):
                    f.write(f"  • {stack}\n")
                f.write("\n")
            
            if resources_before.get('s3_buckets'):
                f.write(f"S3 Buckets Before ({len(resources_before['s3_buckets'])}):\n")
                f.write("-" * 80 + "\n")
                for bucket in sorted(resources_before['s3_buckets']):
                    f.write(f"  • {bucket}\n")
                f.write("\n")
            
            if resources_before.get('log_groups'):
                log_groups = resources_before['log_groups']
                f.write(f"CloudWatch Log Groups Before ({len(log_groups)}):\n")
                f.write("-" * 80 + "\n")
                if len(log_groups) > 50:
                    f.write(f"(Showing first 50 of {len(log_groups)} log groups)\n")
                    for log_group in sorted(log_groups)[:50]:
                        f.write(f"  • {log_group}\n")
                    f.write(f"  ... and {len(log_groups) - 50} more\n")
                else:
                    for log_group in sorted(log_groups):
                        f.write(f"  • {log_group}\n")
                f.write("\n")
            
            if resources_before.get('cognito_pools'):
                f.write(f"Cognito User Pools Before ({len(resources_before['cognito_pools'])}):\n")
                f.write("-" * 80 + "\n")
                for pool in sorted(resources_before['cognito_pools']):
                    f.write(f"  • {pool}\n")
                f.write("\n")
            
            # Resources after
            if resources_after.get('stacks'):
                f.write(f"CloudFormation Stacks After ({len(resources_after['stacks'])}):\n")
                f.write("-" * 80 + "\n")
                for stack in sorted(resources_after['stacks']):
                    f.write(f"  • {stack}\n")
                f.write("\n")
            
            if resources_after.get('s3_buckets'):
                f.write(f"S3 Buckets After ({len(resources_after['s3_buckets'])}):\n")
                f.write("-" * 80 + "\n")
                for bucket in sorted(resources_after['s3_buckets']):
                    f.write(f"  • {bucket}\n")
                f.write("\n")
            
            if resources_after.get('log_groups'):
                log_groups = resources_after['log_groups']
                f.write(f"CloudWatch Log Groups After ({len(log_groups)}):\n")
                f.write("-" * 80 + "\n")
                if len(log_groups) > 50:
                    f.write(f"(Showing first 50 of {len(log_groups)} log groups)\n")
                    for log_group in sorted(log_groups)[:50]:
                        f.write(f"  • {log_group}\n")
                    f.write(f"  ... and {len(log_groups) - 50} more\n")
                else:
                    for log_group in sorted(log_groups):
                        f.write(f"  • {log_group}\n")
                f.write("\n")
            
            if resources_after.get('cognito_pools'):
                f.write(f"Cognito User Pools After ({len(resources_after['cognito_pools'])}):\n")
                f.write("-" * 80 + "\n")
                for pool in sorted(resources_after['cognito_pools']):
                    f.write(f"  • {pool}\n")
                f.write("\n")
            
            # Resources deleted
            if resources_deleted.get('stacks'):
                f.write(f"CloudFormation Stacks Deleted ({len(resources_deleted['stacks'])}):\n")
                f.write("-" * 80 + "\n")
                for stack in sorted(resources_deleted['stacks']):
                    f.write(f"  • {stack}\n")
                f.write("\n")
            
            if resources_deleted.get('s3_buckets'):
                f.write(f"S3 Buckets Deleted ({len(resources_deleted['s3_buckets'])}):\n")
                f.write("-" * 80 + "\n")
                for bucket in sorted(resources_deleted['s3_buckets']):
                    f.write(f"  • {bucket}\n")
                f.write("\n")
            
            if resources_deleted.get('log_groups'):
                log_groups = resources_deleted['log_groups']
                f.write(f"CloudWatch Log Groups Deleted ({len(log_groups)}):\n")
                f.write("-" * 80 + "\n")
                if len(log_groups) > 50:
                    f.write(f"(Showing first 50 of {len(log_groups)} log groups)\n")
                    for log_group in sorted(log_groups)[:50]:
                        f.write(f"  • {log_group}\n")
                    f.write(f"  ... and {len(log_groups) - 50} more\n")
                else:
                    for log_group in sorted(log_groups):
                        f.write(f"  • {log_group}\n")
                f.write("\n")
            
            if resources_deleted.get('cognito_pools'):
                f.write(f"Cognito User Pools Deleted ({len(resources_deleted['cognito_pools'])}):\n")
                f.write("-" * 80 + "\n")
                for pool in sorted(resources_deleted['cognito_pools']):
                    f.write(f"  • {pool}\n")
                f.write("\n")
            
            # Footer
            f.write("=" * 80 + "\n")
            f.write("END OF LOG\n")
            f.write("=" * 80 + "\n")
    
    print()
    print(f"✅ Successfully created {len(steps)} log files in: {logs_dir}")
    print()
    print("📄 Log files created:")
    for log_file in sorted(logs_dir.glob("step_*.log")):
        print(f"   • {log_file.name}")
    print()
    print("💡 Next steps:")
    print(f"   • View summary: cat {report_dir}/SUMMARY.md")
    print(f"   • View specific step: cat {logs_dir}/step_XX_<name>.log")
    print(f"   • Find failures: grep -l 'Success: False' {logs_dir}/step_*.log")


if __name__ == "__main__":
    extract_step_logs()
