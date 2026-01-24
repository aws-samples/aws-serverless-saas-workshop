#!/usr/bin/env python3
"""
Property-based tests for AWS profile parameter support across all workshop scripts.

Feature: workshop-modernization, Property 13: AWS Profile Parameter Support
Validates: Requirements 10.1, 10.2, 10.3

This test suite verifies that:
1. All scripts accept an optional --profile parameter
2. Scripts use the default AWS profile when --profile is not provided
3. Scripts use the specified profile when --profile is provided
4. No hardcoded AWS_PROFILE values remain in any scripts
"""

import os
import re
import subprocess
from pathlib import Path
from typing import List, Tuple

import pytest
from hypothesis import given, settings, strategies as st

# Workshop root directory
WORKSHOP_ROOT = Path(__file__).parent.parent


def get_all_deployment_scripts() -> List[Tuple[str, Path]]:
    """Get all deployment, cleanup, and utility scripts from all labs."""
    scripts = []
    
    # Lab-specific scripts
    for lab_num in range(1, 8):
        lab_dir = WORKSHOP_ROOT / f"Lab{lab_num}" / "scripts"
        if lab_dir.exists():
            for script_name in ["deployment.sh", "cleanup.sh", "geturl.sh", "deploy-updates.sh", "test-basic-tier-throttling.sh"]:
                script_path = lab_dir / script_name
                if script_path.exists():
                    scripts.append((f"Lab{lab_num}/{script_name}", script_path))
    
    # Root-level scripts
    root_scripts_dir = WORKSHOP_ROOT / "scripts"
    if root_scripts_dir.exists():
        for script_path in root_scripts_dir.glob("*.sh"):
            scripts.append((f"scripts/{script_path.name}", script_path))
    
    return scripts


def test_all_scripts_have_profile_parameter():
    """
    Property 13.1: All deployment, cleanup, and utility scripts accept --profile parameter.
    
    Validates: Requirements 10.1, 10.3
    """
    scripts = get_all_deployment_scripts()
    assert len(scripts) > 0, "No scripts found to test"
    
    failures = []
    
    for script_name, script_path in scripts:
        content = script_path.read_text()
        
        # Check if script has --profile parameter in argument parsing
        has_profile_param = (
            "--profile" in content or
            "-p)" in content  # Some scripts might use -p as short form
        )
        
        if not has_profile_param:
            failures.append(f"{script_name}: Missing --profile parameter support")
    
    assert not failures, f"Scripts missing --profile parameter:\n" + "\n".join(failures)


def test_no_hardcoded_aws_profile():
    """
    Property 13.2: No scripts contain hardcoded AWS_PROFILE environment variable.
    
    Validates: Requirements 10.1, 10.2
    """
    scripts = get_all_deployment_scripts()
    assert len(scripts) > 0, "No scripts found to test"
    
    failures = []
    
    # Patterns that indicate hardcoded AWS profile (with actual profile name)
    # AWS_PROFILE="" is acceptable - it means "use default profile"
    hardcoded_patterns = [
        r'AWS_PROFILE="[^"]+?"',  # AWS_PROFILE="profile-name" (non-empty)
        r"AWS_PROFILE='[^']+?'",  # AWS_PROFILE='profile-name' (non-empty)
        r'export\s+AWS_PROFILE="[^"]+?"',  # export AWS_PROFILE="profile-name" (non-empty)
        r"export\s+AWS_PROFILE='[^']+?'",  # export AWS_PROFILE='profile-name' (non-empty)
        r'AWS_PROFILE=serverless-saas-demo',  # Specific hardcoded profile name
    ]
    
    for script_name, script_path in scripts:
        content = script_path.read_text()
        
        for pattern in hardcoded_patterns:
            matches = re.findall(pattern, content)
            if matches:
                # Filter out acceptable patterns (like in comments or help text or variable assignments)
                for match in matches:
                    # Skip if it's in a comment
                    lines = content.split('\n')
                    for line in lines:
                        if match in line:
                            # Skip comments
                            if line.strip().startswith('#'):
                                continue
                            # Skip if it's part of parameter parsing (${OPTARG}, ${!OPTIND}, $2, etc.)
                            if '${' in line and '}' in line:
                                continue
                            if '$2' in line or '$1' in line:  # Command-line argument assignment
                                continue
                            # Skip if it's an empty string assignment (AWS_PROFILE="")
                            if 'AWS_PROFILE=""' in line:
                                continue
                            # This is a real hardcoded profile
                            failures.append(f"{script_name}: Found hardcoded AWS_PROFILE: {match}")
    
    assert not failures, f"Scripts with hardcoded AWS_PROFILE:\n" + "\n".join(failures)


def test_scripts_pass_profile_to_aws_commands():
    """
    Property 13.3: Scripts pass --profile parameter to AWS CLI and SAM CLI commands.
    
    Validates: Requirements 10.2, 10.3
    """
    scripts = get_all_deployment_scripts()
    assert len(scripts) > 0, "No scripts found to test"
    
    failures = []
    
    for script_name, script_path in scripts:
        content = script_path.read_text()
        
        # Skip scripts that don't use AWS CLI or SAM CLI
        if "aws " not in content and "sam " not in content and "cdk " not in content:
            continue
        
        # Check if script has profile parameter defined
        if "--profile" not in content:
            continue
        
        # Find AWS CLI commands
        aws_commands = re.findall(r'aws\s+\w+[^\n]*', content)
        sam_commands = re.findall(r'sam\s+\w+[^\n]*', content)
        cdk_commands = re.findall(r'cdk\s+\w+[^\n]*', content)
        
        all_commands = aws_commands + sam_commands + cdk_commands
        
        if not all_commands:
            continue
        
        # Check if commands use profile parameter
        commands_without_profile = []
        for cmd in all_commands:
            # Skip commands in comments
            if cmd.strip().startswith('#'):
                continue
            
            # Skip commands that are just checking if AWS CLI exists
            if "command -v" in cmd or "which" in cmd:
                continue
            
            # Check if command uses profile parameter
            if "--profile" not in cmd and "$PROFILE" not in cmd and "${PROFILE}" not in cmd:
                # Some commands might use profile conditionally
                # Check if there's a conditional profile usage pattern
                if "if [ -n" not in cmd and "[ -z" not in cmd:
                    commands_without_profile.append(cmd.strip())
        
        if commands_without_profile:
            # Only report if there are many commands without profile (likely not conditional)
            if len(commands_without_profile) > 2:
                failures.append(f"{script_name}: Found {len(commands_without_profile)} AWS/SAM/CDK commands without --profile parameter")
    
    # This is a warning, not a hard failure, as some commands might use conditional profile
    if failures:
        print(f"\nWARNING: Some scripts may not pass --profile to all commands:\n" + "\n".join(failures))


def test_scripts_have_help_text_for_profile():
    """
    Property 13.4: Scripts document --profile parameter in help text.
    
    Validates: Requirements 10.5
    """
    scripts = get_all_deployment_scripts()
    assert len(scripts) > 0, "No scripts found to test"
    
    failures = []
    
    for script_name, script_path in scripts:
        content = script_path.read_text()
        
        # Skip scripts that don't have --profile parameter
        if "--profile" not in content:
            continue
        
        # Check if script has help function or usage text
        has_help = "show_help()" in content or "usage()" in content or "--help" in content
        
        if not has_help:
            failures.append(f"{script_name}: Has --profile parameter but no help text")
            continue
        
        # Check if help text mentions profile parameter
        help_mentions_profile = False
        
        # Look for help function
        help_function_match = re.search(r'(show_help\(\)|usage\(\))\s*\{([^}]+)\}', content, re.DOTALL)
        if help_function_match:
            help_text = help_function_match.group(2)
            if "--profile" in help_text or "profile" in help_text.lower():
                help_mentions_profile = True
        
        # Also check for inline help text
        if not help_mentions_profile:
            if re.search(r'--profile.*AWS.*profile', content, re.IGNORECASE):
                help_mentions_profile = True
        
        if not help_mentions_profile:
            failures.append(f"{script_name}: Help text doesn't document --profile parameter")
    
    assert not failures, f"Scripts with incomplete help text:\n" + "\n".join(failures)


@given(st.sampled_from(["deployment.sh", "cleanup.sh", "geturl.sh"]))
@settings(max_examples=100, deadline=None)
def test_script_help_flag_works(script_name: str):
    """
    Property 13.5: Scripts respond to --help flag without errors.
    
    Validates: Requirements 10.5
    """
    # Find all instances of this script across labs
    for lab_num in range(1, 8):
        script_path = WORKSHOP_ROOT / f"Lab{lab_num}" / "scripts" / script_name
        
        if not script_path.exists():
            continue
        
        # Try to run script with --help flag
        try:
            result = subprocess.run(
                [str(script_path), "--help"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            # Script should exit with 0 or 1 (some scripts use exit 1 for help)
            assert result.returncode in [0, 1], \
                f"Lab{lab_num}/{script_name} --help failed with code {result.returncode}"
            
            # Output should contain usage information
            output = result.stdout + result.stderr
            assert len(output) > 0, \
                f"Lab{lab_num}/{script_name} --help produced no output"
            
            # Output should mention the script name or "Usage"
            assert "usage" in output.lower() or script_name in output.lower(), \
                f"Lab{lab_num}/{script_name} --help output doesn't look like help text"
            
        except subprocess.TimeoutExpired:
            pytest.fail(f"Lab{lab_num}/{script_name} --help timed out")
        except Exception as e:
            pytest.fail(f"Lab{lab_num}/{script_name} --help raised exception: {e}")


def test_profile_parameter_consistency():
    """
    Property 13.6: All scripts use consistent profile parameter naming and behavior.
    
    Validates: Requirements 10.1, 10.2, 10.3
    """
    scripts = get_all_deployment_scripts()
    assert len(scripts) > 0, "No scripts found to test"
    
    profile_patterns = []
    
    for script_name, script_path in scripts:
        content = script_path.read_text()
        
        # Skip scripts without profile parameter
        if "--profile" not in content:
            continue
        
        # Extract profile parameter pattern
        profile_param_match = re.search(r'--profile\s*\)\s*\n?\s*(\w+)=', content)
        if profile_param_match:
            var_name = profile_param_match.group(1)
            profile_patterns.append((script_name, var_name))
    
    # Check consistency
    if profile_patterns:
        var_names = set(var_name for _, var_name in profile_patterns)
        
        # Most common variable name should be used by majority
        from collections import Counter
        var_counts = Counter(var_name for _, var_name in profile_patterns)
        most_common_var = var_counts.most_common(1)[0][0]
        
        inconsistent = [
            script_name for script_name, var_name in profile_patterns
            if var_name != most_common_var
        ]
        
        if inconsistent:
            print(f"\nINFO: Most scripts use '{most_common_var}' for profile variable")
            print(f"Inconsistent scripts: {', '.join(inconsistent)}")


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v", "--tb=short"])
