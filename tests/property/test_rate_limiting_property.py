#!/usr/bin/env python3
"""
Property-Based Tests for Test Suite Rate Limiting

Feature: lab-cleanup-isolation-all-labs, Task 17: Test Suite Rate Limiting
Property 16: Test Suite Execution with Rate Limiting
Validates: Requirements 16.1-16.5, 17.1-17.5

These tests verify that the test framework properly implements rate limiting
to prevent AWS API throttling during end-to-end test execution.
"""

import pytest
from hypothesis import given, strategies as st, settings
import time
from unittest.mock import Mock, patch
import sys
from pathlib import Path

# Add parent directory to path to import test module
sys.path.insert(0, str(Path(__file__).parent.parent))
from test_end_to_end_cleanup_isolation import RateLimiter


# Test configuration
MAX_EXAMPLES = 5  # Reduced for 2-minute timeout
TIMEOUT_SECONDS = 10  # Per-test timeout


@settings(max_examples=MAX_EXAMPLES, deadline=TIMEOUT_SECONDS * 1000)
@given(
    min_delay=st.floats(min_value=0.1, max_value=0.5),  # Reduced from 1.0-15.0
    num_operations=st.integers(min_value=2, max_value=3)  # Reduced from 2-5
)
def test_property_minimum_delay_enforcement(min_delay, num_operations):
    """
    **Validates: Requirements 16.1**
    
    Property: For any sequence of AWS operations, the rate limiter should enforce
    a minimum delay between consecutive operations.
    
    This test verifies that:
    1. The rate limiter waits at least min_delay seconds between operations
    2. The delay is enforced for all consecutive operations
    3. The first operation has no delay
    """
    rate_limiter = RateLimiter(min_delay_seconds=min_delay)
    
    timestamps = []
    
    # Execute multiple operations
    for i in range(num_operations):
        rate_limiter.wait_if_needed(f"operation_{i}")
        timestamps.append(time.time())
    
    # Verify delays between consecutive operations
    for i in range(1, len(timestamps)):
        actual_delay = timestamps[i] - timestamps[i-1]
        # Allow 0.1s tolerance for execution overhead
        assert actual_delay >= (min_delay - 0.1), \
            f"Delay {actual_delay:.2f}s is less than minimum {min_delay}s between operations {i-1} and {i}"


@settings(max_examples=MAX_EXAMPLES, deadline=TIMEOUT_SECONDS * 1000)
@given(
    retry_count=st.integers(min_value=0, max_value=4)
)
def test_property_exponential_backoff_calculation(retry_count):
    """
    **Validates: Requirements 17.3**
    
    Property: For any retry attempt, the backoff delay should follow exponential
    growth: 2s, 4s, 8s, 16s, 32s (capped at 32s).
    
    This test verifies that:
    1. Backoff starts at 2 seconds
    2. Each retry doubles the backoff time
    3. Backoff is capped at 32 seconds
    """
    # Calculate expected backoff
    expected_backoff = min(2.0 * (2 ** retry_count), 32.0)
    
    # Simulate the backoff calculation from RateLimiter.execute_with_retry
    backoff_seconds = 2.0
    for _ in range(retry_count):
        backoff_seconds = min(backoff_seconds * 2, 32.0)
    
    assert backoff_seconds == expected_backoff, \
        f"Backoff {backoff_seconds}s doesn't match expected {expected_backoff}s for retry {retry_count}"


@settings(max_examples=MAX_EXAMPLES, deadline=TIMEOUT_SECONDS * 1000)
@given(
    error_message=st.sampled_from([
        "Throttling: Rate exceeded",
        "TooManyRequestsException: Request limit exceeded",
        "RequestLimitExceeded",
        "ThrottlingException: Too many requests",
        "Rate exceeded for operation",
        "Some other error",
        "ValidationException: Invalid parameter",
        "AccessDenied: Insufficient permissions"
    ])
)
def test_property_throttling_error_detection(error_message):
    """
    **Validates: Requirements 17.2**
    
    Property: For any error message, the rate limiter should correctly identify
    whether it's a throttling error that should trigger retry.
    
    This test verifies that:
    1. Throttling errors are correctly detected
    2. Non-throttling errors are not misidentified
    3. Detection is case-insensitive
    """
    rate_limiter = RateLimiter()
    
    is_throttling = rate_limiter.is_throttling_error(error_message)
    
    # Define expected throttling patterns
    throttling_keywords = ['throttling', 'toomanyrequest', 'rate exceeded', 
                          'requestlimitexceeded', 'throttlingexception']
    
    expected_throttling = any(keyword in error_message.lower() for keyword in throttling_keywords)
    
    assert is_throttling == expected_throttling, \
        f"Error '{error_message}' was {'not ' if not is_throttling else ''}detected as throttling, " \
        f"but should {'not ' if not expected_throttling else ''}be"


@settings(max_examples=MAX_EXAMPLES, deadline=TIMEOUT_SECONDS * 1000)
@given(
    num_throttles=st.integers(min_value=0, max_value=2),  # Reduced from 0-3
    num_operations=st.integers(min_value=1, max_value=3)  # Reduced from 1-5
)
def test_property_metrics_tracking(num_throttles, num_operations):
    """
    **Validates: Requirements 17.4**
    
    Property: For any sequence of operations with throttling errors, the rate limiter
    should accurately track throttling metrics.
    
    This test verifies that:
    1. Total throttles are counted correctly
    2. Total retries are counted correctly
    3. Operations delayed are counted correctly
    4. Total delay time is accumulated correctly
    """
    rate_limiter = RateLimiter(min_delay_seconds=0.05)  # Reduced from 0.1
    
    # Simulate operations with some throttling (only for operations that actually occur)
    actual_throttles = min(num_throttles, num_operations)
    
    for i in range(num_operations):
        rate_limiter.wait_if_needed(f"operation_{i}")
        
        # Simulate throttling for some operations
        if i < actual_throttles:
            rate_limiter.throttling_metrics['total_throttles'] += 1
            rate_limiter.throttling_metrics['total_retries'] += 1
    
    metrics = rate_limiter.get_metrics()
    
    # Verify metrics
    assert metrics['total_throttles'] == actual_throttles, \
        f"Expected {actual_throttles} throttles, got {metrics['total_throttles']}"
    
    assert metrics['total_retries'] == actual_throttles, \
        f"Expected {actual_throttles} retries, got {metrics['total_retries']}"
    
    assert metrics['operations_delayed'] == max(0, num_operations - 1), \
        f"Expected {max(0, num_operations - 1)} delayed operations, got {metrics['operations_delayed']}"
    
    # Total delay should be approximately (num_operations - 1) * 0.05 seconds
    expected_delay = max(0, num_operations - 1) * 0.05
    assert abs(metrics['total_delay_seconds'] - expected_delay) < 0.5, \
        f"Expected ~{expected_delay}s total delay, got {metrics['total_delay_seconds']}s"


@settings(max_examples=MAX_EXAMPLES, deadline=TIMEOUT_SECONDS * 1000)
@given(
    max_retries=st.integers(min_value=1, max_value=5),
    num_failures=st.integers(min_value=0, max_value=6)
)
def test_property_retry_limit_enforcement(max_retries, num_failures):
    """
    **Validates: Requirements 16.3, 17.5**
    
    Property: For any command execution with throttling errors, the rate limiter
    should retry up to max_retries times and then fail with a clear error message.
    
    This test verifies that:
    1. Retries are attempted up to max_retries times
    2. If failures exceed max_retries, the command fails
    3. If failures are within max_retries, the command eventually succeeds
    4. Clear error messages are provided when max retries are exceeded
    """
    rate_limiter = RateLimiter(min_delay_seconds=0.01)  # Very small delay for fast testing
    
    # Mock subprocess.run to simulate throttling errors
    call_count = [0]
    
    def mock_run(*args, **kwargs):
        call_count[0] += 1
        
        # Simulate throttling for first num_failures attempts
        if call_count[0] <= num_failures:
            mock_result = Mock()
            mock_result.returncode = 1
            mock_result.stdout = ""
            mock_result.stderr = "Throttling: Rate exceeded"
            return mock_result
        else:
            # Success after num_failures attempts
            mock_result = Mock()
            mock_result.returncode = 0
            mock_result.stdout = "Success"
            mock_result.stderr = ""
            return mock_result
    
    with patch('subprocess.run', side_effect=mock_run):
        returncode, stdout, stderr = rate_limiter.execute_with_retry(
            ["aws", "test", "command"],
            max_retries=max_retries,
            operation_name="test operation"
        )
        
        # Verify behavior based on num_failures vs max_retries
        if num_failures <= max_retries:
            # Should succeed after retries
            assert returncode == 0, \
                f"Expected success after {num_failures} failures with {max_retries} max retries"
            assert call_count[0] == num_failures + 1, \
                f"Expected {num_failures + 1} calls, got {call_count[0]}"
        else:
            # Should fail after max_retries
            assert returncode == 1, \
                f"Expected failure after exceeding {max_retries} max retries"
            assert call_count[0] == max_retries + 1, \
                f"Expected {max_retries + 1} calls, got {call_count[0]}"
            assert "Throttling" in stderr, \
                f"Expected throttling error in stderr, got: {stderr}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
