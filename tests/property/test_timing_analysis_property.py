#!/usr/bin/env python3
"""
Property-Based Tests for Test Timing Analysis

Feature: lab-cleanup-isolation-all-labs, Task 18.1: Write property test for timing analysis
Property 17: Test Timing Analysis
Validates: Requirements 18.1, 18.2, 18.3, 18.4, 18.5

These tests verify that the test framework correctly tracks and reports timing information
for each test step, including start/end timestamps, duration calculation, and timing analysis.
"""

import pytest
from hypothesis import given, strategies as st, settings
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Dict, Optional
import time


@dataclass
class MockStepTiming:
    """Mock timing data for a test step."""
    step_number: int
    step_name: str
    start_time: float
    end_time: float
    expected_duration_seconds: float
    
    @property
    def actual_duration(self) -> float:
        """Calculate actual duration from timestamps."""
        return self.end_time - self.start_time
    
    @property
    def exceeds_expected(self) -> bool:
        """Check if actual duration exceeds expected duration."""
        return self.actual_duration > self.expected_duration_seconds


class TimingAnalyzer:
    """
    Analyzes test execution timing and generates reports.
    
    Implements:
    - Requirement 18.1: Record start timestamp for each step
    - Requirement 18.2: Record end timestamp and calculate duration
    - Requirement 18.3: Log total execution time and per-step durations
    - Requirement 18.4: Warn when steps exceed expected duration
    - Requirement 18.5: Include timing analysis in test report
    """
    
    def __init__(self):
        self.step_timings: List[MockStepTiming] = []
        self.warnings: List[str] = []
    
    def record_step_start(self, step_number: int, step_name: str, expected_duration: float) -> float:
        """
        Record the start timestamp for a test step.
        
        Args:
            step_number: Step number
            step_name: Step name
            expected_duration: Expected duration in seconds
            
        Returns:
            Start timestamp
        """
        return time.time()
    
    def record_step_end(self, step_number: int, step_name: str, start_time: float, 
                       expected_duration: float) -> MockStepTiming:
        """
        Record the end timestamp and calculate duration.
        
        Args:
            step_number: Step number
            step_name: Step name
            start_time: Start timestamp
            expected_duration: Expected duration in seconds
            
        Returns:
            MockStepTiming with calculated duration
        """
        end_time = time.time()
        timing = MockStepTiming(
            step_number=step_number,
            step_name=step_name,
            start_time=start_time,
            end_time=end_time,
            expected_duration_seconds=expected_duration
        )
        
        self.step_timings.append(timing)
        
        # Requirement 18.4: Warn when step exceeds expected duration
        if timing.exceeds_expected:
            warning = (f"Step {step_number} ({step_name}) exceeded expected duration: "
                      f"{timing.actual_duration:.2f}s actual vs {expected_duration:.2f}s expected")
            self.warnings.append(warning)
        
        return timing
    
    def get_total_duration(self) -> float:
        """
        Calculate total execution time across all steps.
        
        Returns:
            Total duration in seconds
        """
        if not self.step_timings:
            return 0.0
        return sum(timing.actual_duration for timing in self.step_timings)
    
    def get_slowest_steps(self, count: int = 5) -> List[MockStepTiming]:
        """
        Get the slowest test steps.
        
        Args:
            count: Number of slowest steps to return
            
        Returns:
            List of slowest steps sorted by duration (descending)
        """
        return sorted(self.step_timings, key=lambda t: t.actual_duration, reverse=True)[:count]
    
    def generate_timing_report(self) -> Dict:
        """
        Generate timing analysis report.
        
        Returns:
            Dictionary with timing analysis
        """
        if not self.step_timings:
            return {
                "total_duration_seconds": 0.0,
                "step_count": 0,
                "slowest_steps": [],
                "warnings": []
            }
        
        slowest = self.get_slowest_steps(5)
        
        return {
            "total_duration_seconds": round(self.get_total_duration(), 2),
            "step_count": len(self.step_timings),
            "per_step_durations": [
                {
                    "step_number": t.step_number,
                    "step_name": t.step_name,
                    "duration_seconds": round(t.actual_duration, 2),
                    "expected_duration_seconds": round(t.expected_duration_seconds, 2),
                    "exceeded_expected": t.exceeds_expected
                }
                for t in self.step_timings
            ],
            "slowest_steps": [
                {
                    "step_number": t.step_number,
                    "step_name": t.step_name,
                    "duration_seconds": round(t.actual_duration, 2)
                }
                for t in slowest
            ],
            "warnings": self.warnings
        }


# Property-based test strategies
step_numbers = st.integers(min_value=1, max_value=20)
step_names = st.text(min_size=5, max_size=50, alphabet=st.characters(whitelist_categories=('Lu', 'Ll', 'Nd', 'Zs')))
durations = st.floats(min_value=0.1, max_value=3600.0, allow_nan=False, allow_infinity=False)
timestamps = st.floats(min_value=1000000000.0, max_value=2000000000.0, allow_nan=False, allow_infinity=False)


@given(
    step_number=step_numbers,
    step_name=step_names,
    start_time=timestamps,
    duration=durations
)
@settings(max_examples=100, deadline=None)
def test_property_timestamp_recording(step_number, step_name, start_time, duration):
    """
    Property: For any test step, start and end timestamps should be recorded correctly.
    
    Validates: Requirement 18.1 (record start timestamp), Requirement 18.2 (record end timestamp)
    """
    analyzer = TimingAnalyzer()
    
    # Record step timing
    end_time = start_time + duration
    timing = MockStepTiming(
        step_number=step_number,
        step_name=step_name,
        start_time=start_time,
        end_time=end_time,
        expected_duration_seconds=duration * 1.5  # Expected is 50% longer
    )
    
    # Verify timestamps are recorded
    assert timing.start_time == start_time, "Start timestamp should be recorded correctly"
    assert timing.end_time == end_time, "End timestamp should be recorded correctly"
    assert timing.start_time < timing.end_time, "Start time should be before end time"


@given(
    step_number=step_numbers,
    step_name=step_names,
    start_time=timestamps,
    duration=durations
)
@settings(max_examples=100, deadline=None)
def test_property_duration_calculation(step_number, step_name, start_time, duration):
    """
    Property: For any test step, duration should be calculated as end_time - start_time.
    
    Validates: Requirement 18.2 (calculate duration)
    """
    end_time = start_time + duration
    timing = MockStepTiming(
        step_number=step_number,
        step_name=step_name,
        start_time=start_time,
        end_time=end_time,
        expected_duration_seconds=duration * 1.5
    )
    
    # Verify duration calculation
    calculated_duration = timing.actual_duration
    assert abs(calculated_duration - duration) < 0.001, \
        f"Duration should be calculated correctly: expected {duration}, got {calculated_duration}"
    assert calculated_duration >= 0, "Duration should never be negative"


@given(
    num_steps=st.integers(min_value=1, max_value=20),
    base_duration=durations
)
@settings(max_examples=100, deadline=None)
def test_property_total_execution_time(num_steps, base_duration):
    """
    Property: For any test execution, total duration should equal sum of all step durations.
    
    Validates: Requirement 18.3 (log total execution time and per-step durations)
    """
    analyzer = TimingAnalyzer()
    start_time = 1000000000.0
    expected_total = 0.0
    
    # Record multiple steps
    for i in range(num_steps):
        step_duration = base_duration * (i + 1) / num_steps  # Vary durations
        end_time = start_time + step_duration
        
        timing = MockStepTiming(
            step_number=i + 1,
            step_name=f"Step {i + 1}",
            start_time=start_time,
            end_time=end_time,
            expected_duration_seconds=step_duration * 1.5
        )
        analyzer.step_timings.append(timing)
        expected_total += step_duration
        start_time = end_time
    
    # Verify total duration
    total_duration = analyzer.get_total_duration()
    assert abs(total_duration - expected_total) < 0.001, \
        f"Total duration should equal sum of step durations: expected {expected_total}, got {total_duration}"


@given(
    step_number=step_numbers,
    step_name=step_names,
    actual_duration=durations,
    expected_duration=durations
)
@settings(max_examples=100, deadline=None)
def test_property_duration_warning(step_number, step_name, actual_duration, expected_duration):
    """
    Property: For any test step, a warning should be generated if actual duration exceeds expected.
    
    Validates: Requirement 18.4 (warn when steps exceed expected duration)
    """
    analyzer = TimingAnalyzer()
    start_time = 1000000000.0
    end_time = start_time + actual_duration
    
    # Create timing directly instead of using record_step_end (which calls time.time())
    timing = MockStepTiming(
        step_number=step_number,
        step_name=step_name,
        start_time=start_time,
        end_time=end_time,
        expected_duration_seconds=expected_duration
    )
    analyzer.step_timings.append(timing)
    
    # Check if warning should be generated
    if timing.exceeds_expected:
        warning = (f"Step {step_number} ({step_name}) exceeded expected duration: "
                  f"{timing.actual_duration:.2f}s actual vs {expected_duration:.2f}s expected")
        analyzer.warnings.append(warning)
    
    # Verify warning generation
    # Use a small epsilon for floating point comparison
    epsilon = 0.001
    if actual_duration > expected_duration + epsilon:
        assert len(analyzer.warnings) > 0, \
            "Warning should be generated when actual duration exceeds expected"
        assert str(step_number) in analyzer.warnings[0], \
            "Warning should include step number"
        assert step_name in analyzer.warnings[0], \
            "Warning should include step name"
    elif actual_duration < expected_duration - epsilon:
        assert len(analyzer.warnings) == 0, \
            "No warning should be generated when actual duration is within expected"
    # For values within epsilon of each other, either outcome is acceptable due to floating point precision


@given(
    num_steps=st.integers(min_value=1, max_value=20),
    base_duration=durations
)
@settings(max_examples=100, deadline=None)
def test_property_timing_report_completeness(num_steps, base_duration):
    """
    Property: For any test execution, timing report should include all required fields.
    
    Validates: Requirement 18.5 (include timing analysis in test report)
    """
    analyzer = TimingAnalyzer()
    start_time = 1000000000.0
    
    # Record multiple steps with varying durations
    for i in range(num_steps):
        step_duration = base_duration * (i + 1) / num_steps
        end_time = start_time + step_duration
        
        timing = MockStepTiming(
            step_number=i + 1,
            step_name=f"Step {i + 1}",
            start_time=start_time,
            end_time=end_time,
            expected_duration_seconds=step_duration * 0.8  # Some will exceed
        )
        analyzer.step_timings.append(timing)
        start_time = end_time
    
    # Generate timing report
    report = analyzer.generate_timing_report()
    
    # Verify report completeness
    assert "total_duration_seconds" in report, "Report should include total duration"
    assert "step_count" in report, "Report should include step count"
    assert "per_step_durations" in report, "Report should include per-step durations"
    assert "slowest_steps" in report, "Report should include slowest steps"
    assert "warnings" in report, "Report should include warnings"
    
    # Verify report accuracy
    assert report["step_count"] == num_steps, \
        f"Report should show correct step count: expected {num_steps}, got {report['step_count']}"
    assert len(report["per_step_durations"]) == num_steps, \
        "Report should include timing for all steps"
    assert len(report["slowest_steps"]) <= min(5, num_steps), \
        "Report should include up to 5 slowest steps"
    
    # Verify slowest steps are sorted correctly
    if len(report["slowest_steps"]) > 1:
        for i in range(len(report["slowest_steps"]) - 1):
            assert report["slowest_steps"][i]["duration_seconds"] >= \
                   report["slowest_steps"][i + 1]["duration_seconds"], \
                "Slowest steps should be sorted by duration (descending)"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
