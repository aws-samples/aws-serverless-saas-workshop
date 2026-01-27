"""
Pytest configuration for end-to-end cleanup isolation tests.

This file provides custom command-line options for running tests in different modes.
"""

import pytest


def pytest_addoption(parser):
    """Add custom command-line options for pytest."""
    parser.addoption(
        "--real-aws",
        action="store_true",
        default=False,
        help="Run test against real AWS environment (default: dry-run mode)"
    )
    parser.addoption(
        "--aws-profile",
        action="store",
        default=None,
        help="AWS CLI profile to use for real AWS mode"
    )
    parser.addoption(
        "--email",
        action="store",
        default="test@example.com",
        help="Email address for lab deployments"
    )


@pytest.fixture
def test_config(request):
    """Provide test configuration from command-line options."""
    return {
        "dry_run": not request.config.getoption("--real-aws"),
        "aws_profile": request.config.getoption("--aws-profile"),
        "email": request.config.getoption("--email")
    }
