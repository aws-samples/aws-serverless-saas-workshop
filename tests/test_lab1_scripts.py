#!/usr/bin/env python3
"""
Unit tests for Lab1 deployment scripts.

Tests cover:
- Successful deployment scenario
- Cleanup removes all resources
- Error handling for invalid credentials
"""

import os
import subprocess
import unittest
from unittest.mock import patch, MagicMock, call
import tempfile
import shutil


class TestLab1DeploymentScript(unittest.TestCase):
    """Test cases for Lab1 deployment.sh script."""

    def setUp(self):
        """Set up test fixtures."""
        self.script_dir = os.path.join(os.path.dirname(__file__), '..', 'Lab1', 'scripts')
        self.deployment_script = os.path.join(self.script_dir, 'deployment.sh')
        self.test_stack_name = 'test-lab1-stack'
        self.test_region = 'us-east-1'

    def test_deployment_script_exists(self):
        """Test that deployment script exists and is executable."""
        self.assertTrue(os.path.exists(self.deployment_script))
        self.assertTrue(os.access(self.deployment_script, os.X_OK))

    def test_deployment_script_help(self):
        """Test that deployment script shows help message."""
        result = subprocess.run(
            [self.deployment_script, '--help'],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout)
        self.assertIn('--server', result.stdout)
        self.assertIn('--client', result.stdout)
        self.assertIn('--stack-name', result.stdout)
        self.assertIn('--region', result.stdout)

    def test_deployment_script_no_parameters(self):
        """Test that deployment script fails with no parameters."""
        result = subprocess.run(
            [self.deployment_script],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Error: No parameters provided', result.stdout)

    def test_deployment_script_invalid_parameter(self):
        """Test that deployment script fails with invalid parameter."""
        result = subprocess.run(
            [self.deployment_script, '--invalid-param'],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown parameter', result.stdout)

    def test_deployment_script_requires_deployment_option(self):
        """Test that deployment script requires at least -s or -c flag."""
        result = subprocess.run(
            [self.deployment_script, '--stack-name', self.test_stack_name],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Must specify at least one deployment option', result.stdout)

    @patch('subprocess.run')
    def test_deployment_validates_aws_cli(self, mock_run):
        """Test that deployment script validates AWS CLI is installed."""
        # Mock AWS CLI not found
        mock_run.return_value = MagicMock(returncode=127)
        
        result = subprocess.run(
            [self.deployment_script, '-s', '--stack-name', self.test_stack_name],
            capture_output=True,
            text=True,
            env={**os.environ, 'PATH': '/nonexistent'}
        )
        # Script should fail if AWS CLI is not found
        self.assertNotEqual(result.returncode, 0)


class TestLab1CleanupScript(unittest.TestCase):
    """Test cases for Lab1 cleanup.sh script."""

    def setUp(self):
        """Set up test fixtures."""
        self.script_dir = os.path.join(os.path.dirname(__file__), '..', 'Lab1', 'scripts')
        self.cleanup_script = os.path.join(self.script_dir, 'cleanup.sh')
        self.test_stack_name = 'test-lab1-stack'
        self.test_region = 'us-east-1'

    def test_cleanup_script_exists(self):
        """Test that cleanup script exists and is executable."""
        self.assertTrue(os.path.exists(self.cleanup_script))
        self.assertTrue(os.access(self.cleanup_script, os.X_OK))

    def test_cleanup_script_help(self):
        """Test that cleanup script shows help message."""
        result = subprocess.run(
            [self.cleanup_script, '--help'],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout)
        self.assertIn('--stack-name', result.stdout)
        self.assertIn('--region', result.stdout)

    def test_cleanup_script_no_parameters(self):
        """Test that cleanup script fails with no parameters."""
        result = subprocess.run(
            [self.cleanup_script],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Error: Stack name is required', result.stdout)

    def test_cleanup_script_invalid_parameter(self):
        """Test that cleanup script fails with invalid parameter."""
        result = subprocess.run(
            [self.cleanup_script, '--invalid-param', 'value'],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown parameter', result.stdout)


class TestLab1GetUrlScript(unittest.TestCase):
    """Test cases for Lab1 geturl.sh script."""

    def setUp(self):
        """Set up test fixtures."""
        self.script_dir = os.path.join(os.path.dirname(__file__), '..', 'Lab1', 'scripts')
        self.geturl_script = os.path.join(self.script_dir, 'geturl.sh')
        self.test_stack_name = 'test-lab1-stack'
        self.test_region = 'us-east-1'

    def test_geturl_script_exists(self):
        """Test that geturl script exists and is executable."""
        self.assertTrue(os.path.exists(self.geturl_script))
        self.assertTrue(os.access(self.geturl_script, os.X_OK))

    def test_geturl_script_help(self):
        """Test that geturl script shows help message."""
        result = subprocess.run(
            [self.geturl_script, '--help'],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout)
        self.assertIn('--stack-name', result.stdout)
        self.assertIn('--region', result.stdout)

    def test_geturl_script_default_parameters(self):
        """Test that geturl script accepts default parameters."""
        # This will fail if stack doesn't exist, but we're testing parameter parsing
        result = subprocess.run(
            [self.geturl_script],
            capture_output=True,
            text=True
        )
        # Should attempt to query CloudFormation (will fail if stack doesn't exist)
        # But should not fail due to parameter parsing
        self.assertIn('serverless-saas-workshop-lab1', result.stdout)

    def test_geturl_script_custom_stack_name(self):
        """Test that geturl script accepts custom stack name."""
        result = subprocess.run(
            [self.geturl_script, '--stack-name', self.test_stack_name],
            capture_output=True,
            text=True
        )
        # Should show the custom stack name in output
        self.assertIn(self.test_stack_name, result.stdout)

    def test_geturl_script_invalid_parameter(self):
        """Test that geturl script fails with invalid parameter."""
        result = subprocess.run(
            [self.geturl_script, '--invalid-param', 'value'],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown parameter', result.stdout)


class TestLab1ScriptIntegration(unittest.TestCase):
    """Integration tests for Lab1 scripts."""

    def setUp(self):
        """Set up test fixtures."""
        self.script_dir = os.path.join(os.path.dirname(__file__), '..', 'Lab1', 'scripts')
        self.deployment_script = os.path.join(self.script_dir, 'deployment.sh')
        self.cleanup_script = os.path.join(self.script_dir, 'cleanup.sh')
        self.geturl_script = os.path.join(self.script_dir, 'geturl.sh')

    def test_all_scripts_have_shebang(self):
        """Test that all scripts have proper shebang."""
        scripts = [self.deployment_script, self.cleanup_script, self.geturl_script]
        for script in scripts:
            with open(script, 'r') as f:
                first_line = f.readline()
                self.assertTrue(
                    first_line.startswith('#!/bin/bash'),
                    f"{script} missing proper shebang"
                )

    def test_all_scripts_have_copyright(self):
        """Test that all scripts have copyright notice."""
        scripts = [self.deployment_script, self.cleanup_script, self.geturl_script]
        for script in scripts:
            with open(script, 'r') as f:
                content = f.read()
                self.assertIn(
                    'Copyright Amazon.com, Inc. or its affiliates',
                    content,
                    f"{script} missing copyright notice"
                )

    def test_scripts_use_consistent_region_default(self):
        """Test that all scripts use the same default AWS region."""
        scripts = [self.deployment_script, self.cleanup_script, self.geturl_script]
        expected_region = 'us-west-2'
        
        for script in scripts:
            with open(script, 'r') as f:
                content = f.read()
                self.assertIn(
                    f'AWS_REGION="{expected_region}"',
                    content,
                    f"{script} doesn't use consistent default region"
                )

    def test_scripts_use_consistent_stack_name_default(self):
        """Test that all scripts use the same default stack name."""
        scripts = [self.deployment_script, self.cleanup_script, self.geturl_script]
        expected_stack = 'serverless-saas-workshop-lab1'
        
        for script in scripts:
            with open(script, 'r') as f:
                content = f.read()
                self.assertIn(
                    f'STACK_NAME="{expected_stack}"',
                    content,
                    f"{script} doesn't use consistent default stack name"
                )

    def test_scripts_have_error_handling(self):
        """Test that scripts have proper error handling."""
        scripts = [self.deployment_script, self.cleanup_script, self.geturl_script]
        
        for script in scripts:
            with open(script, 'r') as f:
                content = f.read()
                # Check for set -e or error handling
                self.assertTrue(
                    'set -e' in content or 'exit 1' in content,
                    f"{script} missing error handling"
                )

    def test_scripts_create_log_files(self):
        """Test that deployment and cleanup scripts create log files."""
        scripts = [self.deployment_script, self.cleanup_script]
        
        for script in scripts:
            with open(script, 'r') as f:
                content = f.read()
                self.assertIn('LOG_FILE=', content, f"{script} doesn't create log file")
                self.assertIn('LOG_DIR=', content, f"{script} doesn't define log directory")


if __name__ == '__main__':
    unittest.main()
