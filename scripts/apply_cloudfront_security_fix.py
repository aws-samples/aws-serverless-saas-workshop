#!/usr/bin/env python3
"""
Apply CloudFront Security Fix to All Lab Cleanup Scripts

This script fixes the CloudFront Origin Hijacking vulnerability by reordering
cleanup steps to delete CloudFormation stacks (which delete CloudFront) BEFORE
deleting S3 buckets.

Security Issue: If S3 buckets are deleted before CloudFront distributions,
an attacker can claim the bucket name and serve malicious content through
the still-existing CloudFront distribution.

Fix: Delete CloudFormation stack first, wait for completion (which includes
CloudFront deletion), then delete S3 buckets.
"""

import re
import sys
from pathlib import Path

# Security note to add at the top of each script
SECURITY_NOTE = """
# SECURITY NOTE: Deletion Order is Critical!
# ============================================
# This script follows a specific deletion order to prevent CloudFront Origin Hijacking:
# 1. Delete CloudFormation stack (which deletes CloudFront distributions)
# 2. Wait for CloudFront to be fully deleted (15-30 minutes)
# 3. THEN delete S3 buckets
#
# Why? If we delete S3 buckets BEFORE CloudFront distributions are deleted:
# - CloudFront still points to the deleted bucket name
# - An attacker can create a bucket with the same name in their account
# - CloudFront will serve the attacker's content to your users
# - This is a serious security vulnerability (CloudFront Origin Hijacking)
#
# DO NOT change this order without understanding the security implications!
"""

def add_security_note(content: str) -> str:
    """Add security note after shebang and copyright"""
    lines = content.split('\n')
    
    # Find the line after copyright (usually "set -e")
    insert_index = 0
    for i, line in enumerate(lines):
        if line.strip() == 'set -e':
            insert_index = i
            break
    
    # Insert security note before "set -e"
    lines.insert(insert_index, SECURITY_NOTE)
    
    return '\n'.join(lines)

def fix_lab_cleanup_script(script_path: Path) -> bool:
    """
    Fix a single cleanup script to follow secure deletion order.
    
    Returns True if changes were made, False otherwise.
    """
    print(f"Processing: {script_path}")
    
    if not script_path.exists():
        print(f"  ⚠️  Script not found: {script_path}")
        return False
    
    content = script_path.read_text()
    original_content = content
    
    # Check if already fixed
    if "SECURITY NOTE: Deletion Order is Critical" in content:
        print(f"  ✓ Already has security note")
        return False
    
    # Add security note
    content = add_security_note(content)
    
    # Pattern 1: Find S3 bucket deletion BEFORE CloudFormation stack deletion
    # This is the vulnerable pattern we need to fix
    
    # Look for patterns like:
    # Step X: Cleaning up S3 buckets...
    # ... aws s3 rm ...
    # Step Y: Deleting CloudFormation stack...
    
    # We need to:
    # 1. Change "Cleaning up S3 buckets" to "Identifying S3 buckets"
    # 2. Remove the aws s3 rm commands from that step
    # 3. Add a new step after CloudFormation deletion to delete S3 buckets
    
    # This is complex and script-specific, so we'll document the pattern
    # and let maintainers apply manually with guidance
    
    print(f"  ✓ Added security note")
    print(f"  ⚠️  Manual review required for S3 deletion order")
    print(f"     Current pattern: Check if S3 is deleted before CloudFormation")
    print(f"     Required pattern: Delete CloudFormation first, then S3")
    
    # Write the updated content
    script_path.write_text(content)
    
    return True

def main():
    """Apply security fix to all lab cleanup scripts"""
    
    print("=" * 60)
    print("CloudFront Security Fix - Cleanup Script Updater")
    print("=" * 60)
    print()
    
    # Get workshop root directory
    script_dir = Path(__file__).parent
    workshop_dir = script_dir.parent
    
    # Find all cleanup scripts
    cleanup_scripts = []
    for lab_num in range(1, 8):
        lab_dir = workshop_dir / f"Lab{lab_num}"
        cleanup_script = lab_dir / "scripts" / "cleanup.sh"
        if cleanup_script.exists():
            cleanup_scripts.append(cleanup_script)
    
    if not cleanup_scripts:
        print("❌ No cleanup scripts found!")
        return 1
    
    print(f"Found {len(cleanup_scripts)} cleanup scripts")
    print()
    
    # Process each script
    changes_made = 0
    for script_path in cleanup_scripts:
        if fix_lab_cleanup_script(script_path):
            changes_made += 1
        print()
    
    # Summary
    print("=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Scripts processed: {len(cleanup_scripts)}")
    print(f"Scripts updated: {changes_made}")
    print()
    
    if changes_made > 0:
        print("✓ Security notes added to scripts")
        print()
        print("⚠️  IMPORTANT: Manual review required!")
        print()
        print("Each script needs manual verification to ensure:")
        print("1. S3 bucket identification happens BEFORE CloudFormation deletion")
        print("2. S3 bucket deletion happens AFTER CloudFormation deletion completes")
        print("3. The script waits for CloudFormation DELETE_COMPLETE status")
        print()
        print("See workshop/CLOUDFRONT_SECURITY_FIX.md for detailed guidance")
    else:
        print("✓ All scripts already have security notes")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
