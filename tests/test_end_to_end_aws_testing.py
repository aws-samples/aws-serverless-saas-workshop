#!/usr/bin/env python3
"""
Main entry point for end-to-end AWS testing system.

This script executes the complete 10-step test workflow and generates reports.
"""

import argparse
import logging
import sys
from pathlib import Path

from end_to_end.config import TestConfig
from end_to_end.logging_config import setup_logging
from end_to_end.orchestrator import TestOrchestrator

logger = logging.getLogger(__name__)


def parse_arguments() -> argparse.Namespace:
    """
    Parse command-line arguments.
    
    Returns:
        Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="End-to-End AWS Testing System for Serverless SaaS Workshop",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run with default settings
  python test_end_to_end_aws_testing.py --profile my-profile --email admin@example.com
  
  # Run with tenant auto-creation
  python test_end_to_end_aws_testing.py --profile my-profile --email admin@example.com --tenant-email tenant@example.com
  
  # Run with custom region and sequential mode
  python test_end_to_end_aws_testing.py --profile my-profile --email admin@example.com --region us-west-2 --sequential
  
  # Run with custom timeout
  python test_end_to_end_aws_testing.py --profile my-profile --email admin@example.com --timeout 8
        """
    )
    
    # Required arguments
    parser.add_argument(
        "--profile",
        required=True,
        help="AWS CLI profile name (REQUIRED)"
    )
    
    parser.add_argument(
        "--email",
        required=True,
        help="Email address for admin and tenant accounts (REQUIRED)"
    )
    
    # Optional arguments
    parser.add_argument(
        "--tenant-email",
        help="Tenant admin email for Lab3-4 auto-creation (optional)"
    )
    
    parser.add_argument(
        "--region",
        default="us-east-1",
        help="AWS region (default: us-east-1)"
    )
    
    parser.add_argument(
        "--parallel",
        action="store_true",
        default=True,
        help="Enable parallel deployment mode (DEFAULT)"
    )
    
    parser.add_argument(
        "--sequential",
        action="store_true",
        help="Disable parallel deployment mode"
    )
    
    parser.add_argument(
        "--timeout",
        type=int,
        default=6,
        help="Maximum test execution time in hours (default: 6)"
    )
    
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path("workshop/tests/end_to_end_test_report/logs"),
        help="Directory for log files (default: workshop/tests/end_to_end_test_report/logs)"
    )
    
    parser.add_argument(
        "--report-dir",
        type=Path,
        default=Path("workshop/tests/end_to_end_test_report"),
        help="Directory for test reports (default: workshop/tests/end_to_end_test_report)"
    )
    
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )
    
    return parser.parse_args()


def main() -> int:
    """
    Main entry point for end-to-end testing.
    
    Returns:
        Exit code (0 for success, 1 for failure)
    """
    # Parse arguments
    args = parse_arguments()
    
    # Set up logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    setup_logging(log_directory=args.log_dir, log_level=log_level)
    
    logger.info("=" * 80)
    logger.info("End-to-End AWS Testing System")
    logger.info("=" * 80)
    logger.info(f"AWS Profile: {args.profile}")
    logger.info(f"AWS Region: {args.region}")
    logger.info(f"Email: {args.email}")
    logger.info(f"Tenant Email: {args.tenant_email or 'Not provided'}")
    logger.info(f"Parallel Mode: {not args.sequential}")
    logger.info(f"Timeout: {args.timeout} hours")
    logger.info(f"Log Directory: {args.log_dir}")
    logger.info(f"Report Directory: {args.report_dir}")
    logger.info("=" * 80)
    
    try:
        # Create test configuration
        config = TestConfig(
            aws_profile=args.profile,
            aws_region=args.region,
            email=args.email,
            tenant_email=args.tenant_email,
            parallel_mode=not args.sequential,
            timeout_hours=args.timeout,
            log_directory=args.log_dir,
            report_directory=args.report_dir
        )
        
        # Create orchestrator
        orchestrator = TestOrchestrator(config)
        
        # Run test suite
        logger.info("Starting test suite execution...")
        report = orchestrator.run_test_suite()
        
        # Check overall success
        if report.overall_success:
            logger.info("=" * 80)
            logger.info("✅ TEST SUITE PASSED")
            logger.info("=" * 80)
            return 0
        else:
            logger.error("=" * 80)
            logger.error("❌ TEST SUITE FAILED")
            logger.error("=" * 80)
            return 1
            
    except KeyboardInterrupt:
        logger.warning("Test suite interrupted by user")
        return 130  # Standard exit code for SIGINT
        
    except Exception as e:
        logger.error(f"Test suite failed with exception: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
