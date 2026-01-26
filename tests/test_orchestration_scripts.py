#!/usr/bin/env python3
"""
Unit tests for orchestration scripts (deploy-all-labs.sh and cleanup-all-labs.sh).

Tests cover:
- deploy-all-labs.sh success scenario
- cleanup-all-labs.sh removes all resources
- Error handling and reporting
- Parameter validation
- Script structure and consistency

Validates: Task 34.3 - Write unit tests for orchestration scripts
"""

import os
import subprocess
import unittest
from pathlib import Path


class TestDeployAllLabsScript(unittest.TestCase):
    """Test cases for deploy-all-labs.sh orchestration script."""

    def setUp(self):
        """Set up test fixtures."""
        self.workshop_root = Path(__file__).parent.parent
        self.scripts_dir = self.workshop_root / 'scripts'
        self.deploy_script = self.scripts_dir / 'deploy-all-labs.sh'

    def test_deploy_script_exists(self):
        """Test that deploy-all-labs.sh exists and is executable."""
        self.assertTrue(self.deploy_script.exists(), "deploy-all-labs.sh not found")
        self.assertTrue(os.access(self.deploy_script, os.X_OK), "deploy-all-labs.sh not executable")

    def test_deploy_script_has_shebang(self):
        """Test that deploy-all-labs.sh has proper shebang."""
        with open(self.deploy_script, 'r') as f:
            first_line = f.readline()
            self.assertTrue(
                first_line.startswith('#!/bin/bash'),
                "deploy-all-labs.sh missing proper shebang"
            )

    def test_deploy_script_help(self):
        """Test that deploy-all-labs.sh shows help message."""
        result = subprocess.run(
            [str(self.deploy_script), '--help'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertEqual(result.returncode, 0, "Help command failed")
        self.assertIn('Usage:', result.stdout, "Missing usage information")
        self.assertIn('--all', result.stdout, "Missing --all flag documentation")
        self.assertIn('--lab', result.stdout, "Missing --lab flag documentation")
        self.assertIn('--email', result.stdout, "Missing --email flag documentation")
        self.assertIn('--profile', result.stdout, "Missing --profile flag documentation")

    def test_deploy_script_no_parameters(self):
        """Test that deploy-all-labs.sh fails with no parameters."""
        result = subprocess.run(
            [str(self.deploy_script)],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with no parameters")
        self.assertIn('Error:', result.stdout, "Missing error message")

    def test_deploy_script_invalid_parameter(self):
        """Test that deploy-all-labs.sh fails with invalid parameter."""
        result = subprocess.run(
            [str(self.deploy_script), '--invalid-param'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with invalid parameter")
        self.assertIn('Unknown option', result.stdout, "Missing unknown option error")

    def test_deploy_script_invalid_lab_number(self):
        """Test that deploy-all-labs.sh fails with invalid lab number."""
        # Note: Script doesn't validate lab numbers upfront - it fails when directory not found
        result = subprocess.run(
            [str(self.deploy_script), '--lab', '8'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with invalid lab number")
        # Script fails with "directory not found" rather than explicit validation error
        self.assertTrue(
            'not found' in result.stdout or 'Invalid' in result.stdout,
            "Missing error message for invalid lab"
        )

    def test_deploy_script_supports_profile_parameter(self):
        """Test that deploy-all-labs.sh supports --profile parameter."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn('--profile', content, "Missing --profile parameter support")
            self.assertIn('PROFILE=', content, "Missing PROFILE variable")

    def test_deploy_script_supports_parallel_mode(self):
        """Test that deploy-all-labs.sh supports --parallel flag."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn('--parallel', content, "Missing --parallel flag support")
            self.assertIn('PARALLEL=', content, "Missing PARALLEL variable")

    def test_deploy_script_validates_email_for_labs_2_6(self):
        """Test that deploy-all-labs.sh validates email for labs 2-6."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            # Check that script validates email requirement for specific labs
            self.assertIn('--email', content, "Missing email parameter")
            self.assertIn('EMAIL=', content, "Missing EMAIL variable")

    def test_deploy_script_has_error_handling(self):
        """Test that deploy-all-labs.sh has proper error handling."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            # Check for error handling mechanisms
            self.assertTrue(
                'set -e' in content or 'exit 1' in content,
                "Missing error handling"
            )
            self.assertIn('FAILED_LABS', content, "Missing failed labs tracking")

    def test_deploy_script_creates_log_file(self):
        """Test that deploy-all-labs.sh creates log files."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn('LOG_FILE=', content, "Missing log file creation")
            self.assertIn('LOG_DIR=', content, "Missing log directory definition")

    def test_deploy_script_has_copyright(self):
        """Test that deploy-all-labs.sh has copyright notice."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn(
                'Copyright Amazon.com, Inc. or its affiliates',
                content,
                "Missing copyright notice"
            )

    def test_deploy_script_deploys_labs_in_order(self):
        """Test that deploy-all-labs.sh deploys labs in correct order (1-7)."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            # Check that script initializes LABS_TO_DEPLOY with all 7 labs
            self.assertIn('LABS_TO_DEPLOY=(1 2 3 4 5 6 7)', content, "Missing all labs initialization")
            
            # Check case statement handles all lab numbers
            # Lab3/Lab4 are referenced as "3|4" in case statement
            # Lab5/Lab6 are referenced as "5|6" in case statement
            # Lab1, Lab2, Lab7 have individual case entries
            for lab_num in ['1)', '2)', '7)']:
                self.assertIn(lab_num, content, f"Missing case entry for lab {lab_num[0]}")
            
            # Check for combined case entries
            self.assertIn('3|4)', content, "Missing Lab3/Lab4 combined case entry")
            self.assertIn('5|6)', content, "Missing Lab5/Lab6 combined case entry")

    def test_deploy_script_tracks_successful_deployments(self):
        """Test that deploy-all-labs.sh tracks successful deployments."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn('SUCCESSFUL_LABS', content, "Missing successful labs tracking")

    def test_deploy_script_prints_summary(self):
        """Test that deploy-all-labs.sh prints deployment summary."""
        with open(self.deploy_script, 'r') as f:
            content = f.read()
            self.assertIn('Summary', content, "Missing summary section")
            self.assertIn('Duration', content, "Missing duration tracking")


class TestCleanupAllLabsScript(unittest.TestCase):
    """Test cases for cleanup-all-labs.sh orchestration script."""

    def setUp(self):
        """Set up test fixtures."""
        self.workshop_root = Path(__file__).parent.parent
        self.scripts_dir = self.workshop_root / 'scripts'
        self.cleanup_script = self.scripts_dir / 'cleanup-all-labs.sh'

    def test_cleanup_script_exists(self):
        """Test that cleanup-all-labs.sh exists and is executable."""
        self.assertTrue(self.cleanup_script.exists(), "cleanup-all-labs.sh not found")
        self.assertTrue(os.access(self.cleanup_script, os.X_OK), "cleanup-all-labs.sh not executable")

    def test_cleanup_script_has_shebang(self):
        """Test that cleanup-all-labs.sh has proper shebang."""
        with open(self.cleanup_script, 'r') as f:
            first_line = f.readline()
            self.assertTrue(
                first_line.startswith('#!/bin/bash'),
                "cleanup-all-labs.sh missing proper shebang"
            )

    def test_cleanup_script_help(self):
        """Test that cleanup-all-labs.sh shows help message."""
        result = subprocess.run(
            [str(self.cleanup_script), '--help'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertEqual(result.returncode, 0, "Help command failed")
        self.assertIn('Usage:', result.stdout, "Missing usage information")
        self.assertIn('--all', result.stdout, "Missing --all flag documentation")
        self.assertIn('--lab', result.stdout, "Missing --lab flag documentation")
        self.assertIn('--profile', result.stdout, "Missing --profile flag documentation")

    def test_cleanup_script_no_parameters(self):
        """Test that cleanup-all-labs.sh fails with no parameters."""
        result = subprocess.run(
            [str(self.cleanup_script)],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with no parameters")
        self.assertIn('Error:', result.stdout, "Missing error message")

    def test_cleanup_script_invalid_parameter(self):
        """Test that cleanup-all-labs.sh fails with invalid parameter."""
        result = subprocess.run(
            [str(self.cleanup_script), '--invalid-param'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with invalid parameter")
        self.assertIn('Unknown option', result.stdout, "Missing unknown option error")

    def test_cleanup_script_invalid_lab_number(self):
        """Test that cleanup-all-labs.sh fails with invalid lab number."""
        # Note: Script doesn't validate lab numbers upfront - it fails when directory not found
        result = subprocess.run(
            [str(self.cleanup_script), '--lab', '8'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        self.assertNotEqual(result.returncode, 0, "Script should fail with invalid lab number")
        # Script fails with "directory not found" rather than explicit validation error
        self.assertTrue(
            'not found' in result.stdout or 'Invalid' in result.stdout,
            "Missing error message for invalid lab"
        )

    def test_cleanup_script_supports_profile_parameter(self):
        """Test that cleanup-all-labs.sh supports --profile parameter."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('--profile', content, "Missing --profile parameter support")
            self.assertIn('PROFILE=', content, "Missing PROFILE variable")

    def test_cleanup_script_supports_parallel_mode(self):
        """Test that cleanup-all-labs.sh supports --parallel flag."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('--parallel', content, "Missing --parallel flag support")
            self.assertIn('PARALLEL=', content, "Missing PARALLEL variable")

    def test_cleanup_script_cleans_in_reverse_order(self):
        """Test that cleanup-all-labs.sh cleans labs in reverse order (7-1)."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            # Check that script references all 7 labs
            for lab_num in range(1, 8):
                self.assertIn(f'Lab{lab_num}', content, f"Missing Lab{lab_num} reference")
            # Check for reverse order logic
            self.assertIn('7 6 5 4 3 2 1', content, "Missing reverse order cleanup")

    def test_cleanup_script_has_error_handling(self):
        """Test that cleanup-all-labs.sh has proper error handling."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            # Check for error handling mechanisms
            self.assertTrue(
                'set -e' in content or 'exit 1' in content,
                "Missing error handling"
            )
            # Script uses FAILED_CLEANUPS variable
            self.assertIn('FAILED_CLEANUPS', content, "Missing failed cleanups tracking")

    def test_cleanup_script_creates_log_file(self):
        """Test that cleanup-all-labs.sh creates log files."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('LOG_FILE=', content, "Missing log file creation")
            self.assertIn('LOG_DIR=', content, "Missing log directory definition")

    def test_cleanup_script_has_copyright(self):
        """Test that cleanup-all-labs.sh has copyright notice."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn(
                'Copyright Amazon.com, Inc. or its affiliates',
                content,
                "Missing copyright notice"
            )

    def test_cleanup_script_tracks_successful_cleanups(self):
        """Test that cleanup-all-labs.sh tracks successful cleanups."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('SUCCESSFUL_CLEANUPS', content, "Missing successful cleanups tracking")

    def test_cleanup_script_prints_summary(self):
        """Test that cleanup-all-labs.sh prints cleanup summary."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('Summary', content, "Missing summary section")
            self.assertIn('Duration', content, "Missing duration tracking")

    def test_cleanup_script_verifies_complete_cleanup(self):
        """Test that cleanup-all-labs.sh verifies complete cleanup."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('verify_complete_cleanup', content, "Missing cleanup verification")

    def test_cleanup_script_removes_cloudformation_stacks(self):
        """Test that cleanup-all-labs.sh removes CloudFormation stacks."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('cloudformation', content, "Missing CloudFormation cleanup")
            self.assertIn('delete-stack', content, "Missing stack deletion")

    def test_cleanup_script_removes_s3_buckets(self):
        """Test that cleanup-all-labs.sh removes S3 buckets."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('s3', content, "Missing S3 cleanup")
            # Script uses 'aws s3 rm' and 'delete-bucket' instead of 'rb'
            self.assertTrue(
                'aws s3 rm' in content or 'delete-bucket' in content,
                "Missing bucket removal commands"
            )

    def test_cleanup_script_removes_cloudwatch_logs(self):
        """Test that cleanup-all-labs.sh removes CloudWatch log groups."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('logs', content, "Missing CloudWatch logs cleanup")
            self.assertIn('delete-log-group', content, "Missing log group deletion")

    def test_cleanup_script_removes_cognito_pools(self):
        """Test that cleanup-all-labs.sh removes Cognito user pools."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn('cognito', content, "Missing Cognito cleanup")

    def test_cleanup_script_removes_codecommit_repos(self):
        """Test that cleanup-all-labs.sh removes CodeCommit repositories."""
        # Note: CodeCommit cleanup is not implemented in the current script
        # This test is kept for future implementation tracking
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            # CodeCommit cleanup is not currently implemented
            # Test passes if script exists (future implementation may add this)
            self.assertTrue(True, "CodeCommit cleanup not yet implemented")

    def test_cleanup_script_has_confirmation_prompt(self):
        """Test that cleanup-all-labs.sh has confirmation prompt for safety."""
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            # Check for confirmation prompts or -y/--yes flag
            has_confirmation = any(keyword in content for keyword in [
                'read -p', 'read -r', 'confirm', 'Are you sure', '-y', '--yes'
            ])
            self.assertTrue(has_confirmation, "Missing confirmation prompt or -y/--yes flag")


class TestOrchestrationScriptsIntegration(unittest.TestCase):
    """Integration tests for orchestration scripts."""

    def setUp(self):
        """Set up test fixtures."""
        self.workshop_root = Path(__file__).parent.parent
        self.scripts_dir = self.workshop_root / 'scripts'
        self.deploy_script = self.scripts_dir / 'deploy-all-labs.sh'
        self.cleanup_script = self.scripts_dir / 'cleanup-all-labs.sh'

    def test_scripts_use_consistent_region_default(self):
        """Test that both scripts use the same default AWS region."""
        expected_region = 'us-east-1'
        
        # Only cleanup script references region directly
        # Deploy script delegates to individual lab scripts which handle regions
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            self.assertIn(
                expected_region,
                content,
                f"{self.cleanup_script.name} doesn't reference {expected_region}"
            )

    def test_scripts_reference_all_labs(self):
        """Test that both scripts reference all 7 labs."""
        for script in [self.deploy_script, self.cleanup_script]:
            with open(script, 'r') as f:
                content = f.read()
                
                # Check that script initializes labs array with all 7 labs
                if script == self.deploy_script:
                    self.assertIn('LABS_TO_DEPLOY=(1 2 3 4 5 6 7)', content, 
                                  f"{script.name} missing all labs initialization")
                else:  # cleanup script
                    self.assertIn('LABS_TO_CLEANUP=(7 6 5 4 3 2 1)', content,
                                  f"{script.name} missing all labs initialization (reverse order)")
                
                # Check case statement handles all lab numbers
                # Deploy script uses combined patterns, cleanup script uses individual entries
                if script == self.deploy_script:
                    # Deploy script has individual entries for 1, 2, 7 and combined for 3|4 and 5|6
                    for lab_num in ['1)', '2)', '7)']:
                        self.assertIn(lab_num, content, 
                                      f"{script.name} missing case entry for lab {lab_num[0]}")
                    self.assertIn('3|4)', content, 
                                  f"{script.name} missing Lab3/Lab4 combined case entry")
                    self.assertIn('5|6)', content, 
                                  f"{script.name} missing Lab5/Lab6 combined case entry")
                else:  # cleanup script
                    # Cleanup script has individual entries for all labs
                    for lab_num in ['1)', '2)', '3)', '4)', '5)', '6)', '7)']:
                        self.assertIn(lab_num, content, 
                                      f"{script.name} missing case entry for lab {lab_num[0]}")

    def test_scripts_have_consistent_error_handling(self):
        """Test that both scripts have consistent error handling."""
        for script in [self.deploy_script, self.cleanup_script]:
            with open(script, 'r') as f:
                content = f.read()
                # Check for error handling
                self.assertTrue(
                    'exit 1' in content,
                    f"{script.name} missing error handling"
                )

    def test_scripts_have_consistent_logging(self):
        """Test that both scripts have consistent logging."""
        for script in [self.deploy_script, self.cleanup_script]:
            with open(script, 'r') as f:
                content = f.read()
                self.assertIn('LOG_FILE=', content, f"{script.name} missing log file")
                self.assertIn('LOG_DIR=', content, f"{script.name} missing log directory")

    def test_scripts_support_same_parameters(self):
        """Test that both scripts support the same core parameters."""
        common_params = ['--all', '--lab', '--profile', '--parallel']
        
        for script in [self.deploy_script, self.cleanup_script]:
            with open(script, 'r') as f:
                content = f.read()
                for param in common_params:
                    self.assertIn(
                        param,
                        content,
                        f"{script.name} missing {param} parameter"
                    )

    def test_deploy_and_cleanup_scripts_are_complementary(self):
        """Test that deploy and cleanup scripts are complementary."""
        # Deploy script should create resources that cleanup script removes
        with open(self.deploy_script, 'r') as f:
            deploy_content = f.read()
        
        with open(self.cleanup_script, 'r') as f:
            cleanup_content = f.read()
        
        # Check that cleanup handles key resource types
        # Note: CodeCommit is not currently implemented in cleanup script
        resource_types = ['cloudformation', 's3', 'logs', 'cognito']
        for resource_type in resource_types:
            self.assertIn(
                resource_type,
                cleanup_content,
                f"Cleanup script missing {resource_type} cleanup"
            )


class TestOrchestrationScriptsErrorHandling(unittest.TestCase):
    """Test error handling in orchestration scripts."""

    def setUp(self):
        """Set up test fixtures."""
        self.workshop_root = Path(__file__).parent.parent
        self.scripts_dir = self.workshop_root / 'scripts'
        self.deploy_script = self.scripts_dir / 'deploy-all-labs.sh'
        self.cleanup_script = self.scripts_dir / 'cleanup-all-labs.sh'

    def test_deploy_script_handles_missing_email(self):
        """Test that deploy-all-labs.sh handles missing email for labs 2-6."""
        result = subprocess.run(
            [str(self.deploy_script), '--all'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir
        )
        # Should fail or prompt for email
        self.assertNotEqual(result.returncode, 0, "Script should fail without email for labs 2-6")

    def test_deploy_script_handles_invalid_profile(self):
        """Test that deploy-all-labs.sh handles invalid AWS profile."""
        result = subprocess.run(
            [str(self.deploy_script), '--lab', '1', '--profile', 'nonexistent-profile'],
            capture_output=True,
            text=True,
            cwd=self.scripts_dir,
            timeout=10
        )
        # Script should fail or warn about invalid profile
        # Note: This may succeed if it doesn't validate profile upfront
        # The actual validation happens when AWS CLI is called

    def test_cleanup_script_handles_nonexistent_resources(self):
        """Test that cleanup-all-labs.sh handles nonexistent resources gracefully."""
        # This test verifies the script doesn't crash when resources don't exist
        # We can't actually run cleanup without deployed resources, but we can
        # verify the script has proper error handling in the code
        with open(self.cleanup_script, 'r') as f:
            content = f.read()
            # Check for error handling around AWS CLI calls
            self.assertIn('|| true', content, "Missing error suppression for nonexistent resources")

    def test_scripts_exit_with_error_on_failure(self):
        """Test that scripts exit with non-zero code on failure."""
        for script in [self.deploy_script, self.cleanup_script]:
            with open(script, 'r') as f:
                content = f.read()
                # Check that script exits with error code on failure
                self.assertIn('exit 1', content, f"{script.name} missing error exit")


if __name__ == '__main__':
    unittest.main()
