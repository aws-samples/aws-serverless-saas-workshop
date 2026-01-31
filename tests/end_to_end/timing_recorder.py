"""
Timing Recorder component for end-to-end AWS testing system.

This module measures operation durations with high precision and tracks timing metrics.
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

from .models import TimingMetric

logger = logging.getLogger(__name__)


class OperationTimer:
    """
    Timer for a single operation.
    
    Tracks start time and provides methods to calculate duration.
    """
    
    def __init__(self, operation_name: str):
        """
        Initialize operation timer.
        
        Args:
            operation_name: Name of the operation being timed
        """
        self.operation_name = operation_name
        self.start_time = datetime.now()
        self.end_time: Optional[datetime] = None
    
    def stop(self) -> timedelta:
        """
        Stop the timer and calculate duration.
        
        Returns:
            Duration of the operation
        """
        self.end_time = datetime.now()
        return self.end_time - self.start_time
    
    def get_duration(self) -> Optional[timedelta]:
        """
        Get duration if timer has been stopped.
        
        Returns:
            Duration or None if timer is still running
        """
        if self.end_time is None:
            return None
        return self.end_time - self.start_time


class TimingRecorder:
    """
    Records timing metrics for all test operations.
    
    Provides high-precision timing with millisecond accuracy and
    tracks total test execution time.
    """
    
    def __init__(self):
        """Initialize timing recorder with empty metrics."""
        self.timing_metrics: List[TimingMetric] = []
        self.active_timers: Dict[str, OperationTimer] = {}
        self.test_start_time: Optional[datetime] = None
        self.test_end_time: Optional[datetime] = None
    
    def start_test(self) -> None:
        """Start timing the overall test execution."""
        self.test_start_time = datetime.now()
        logger.info(f"Test execution started at {self.test_start_time}")
    
    def end_test(self) -> timedelta:
        """
        End timing the overall test execution.
        
        Returns:
            Total test duration
        """
        self.test_end_time = datetime.now()
        duration = self.test_end_time - self.test_start_time
        logger.info(f"Test execution ended at {self.test_end_time}, duration: {duration}")
        return duration
    
    def start_operation(self, operation_name: str) -> OperationTimer:
        """
        Start timing an operation.
        
        Args:
            operation_name: Name of the operation
            
        Returns:
            OperationTimer instance
        """
        timer = OperationTimer(operation_name)
        self.active_timers[operation_name] = timer
        logger.debug(f"Started timing operation: {operation_name}")
        return timer
    
    def end_operation(self, timer: OperationTimer) -> TimingMetric:
        """
        End timing an operation and record the metric.
        
        Args:
            timer: OperationTimer instance
            
        Returns:
            TimingMetric with recorded timing data
        """
        duration = timer.stop()
        
        metric = TimingMetric(
            operation_name=timer.operation_name,
            start_time=timer.start_time,
            end_time=timer.end_time,
            duration=duration,
            duration_seconds=duration.total_seconds()
        )
        
        self.timing_metrics.append(metric)
        
        # Remove from active timers
        if timer.operation_name in self.active_timers:
            del self.active_timers[timer.operation_name]
        
        logger.info(
            f"Operation '{timer.operation_name}' completed in {duration} "
            f"({metric.duration_seconds:.2f} seconds)"
        )
        
        return metric
    
    def record_operation(
        self,
        operation_name: str,
        start_time: datetime,
        end_time: datetime
    ) -> TimingMetric:
        """
        Manually record a timing metric (for testing or special cases).
        
        Args:
            operation_name: Name of the operation
            start_time: Operation start time
            end_time: Operation end time
            
        Returns:
            TimingMetric with recorded timing data
        """
        duration = end_time - start_time
        
        metric = TimingMetric(
            operation_name=operation_name,
            start_time=start_time,
            end_time=end_time,
            duration=duration,
            duration_seconds=duration.total_seconds()
        )
        
        self.timing_metrics.append(metric)
        logger.debug(f"Manually recorded timing for '{operation_name}': {duration}")
        
        return metric
    
    def get_total_duration(self) -> Optional[timedelta]:
        """
        Get total test execution time.
        
        Returns:
            Total duration or None if test hasn't ended
        """
        if self.test_start_time is None:
            return None
        
        if self.test_end_time is None:
            # Test still running, return current duration
            return datetime.now() - self.test_start_time
        
        return self.test_end_time - self.test_start_time
    
    def get_operation_metrics(self) -> List[TimingMetric]:
        """
        Get all recorded timing metrics.
        
        Returns:
            List of TimingMetric objects
        """
        return self.timing_metrics.copy()
    
    def get_metric_by_operation(self, operation_name: str) -> Optional[TimingMetric]:
        """
        Get timing metric for a specific operation.
        
        Args:
            operation_name: Name of the operation
            
        Returns:
            TimingMetric or None if not found
        """
        for metric in self.timing_metrics:
            if metric.operation_name == operation_name:
                return metric
        return None
    
    def get_metrics_summary(self) -> Dict[str, float]:
        """
        Get summary of timing metrics.
        
        Returns:
            Dictionary with operation names and durations in seconds
        """
        return {
            metric.operation_name: metric.duration_seconds
            for metric in self.timing_metrics
        }
    
    def get_slowest_operations(self, count: int = 5) -> List[TimingMetric]:
        """
        Get the slowest operations.
        
        Args:
            count: Number of operations to return
            
        Returns:
            List of slowest TimingMetric objects
        """
        sorted_metrics = sorted(
            self.timing_metrics,
            key=lambda m: m.duration_seconds,
            reverse=True
        )
        return sorted_metrics[:count]
    
    def get_fastest_operations(self, count: int = 5) -> List[TimingMetric]:
        """
        Get the fastest operations.
        
        Args:
            count: Number of operations to return
            
        Returns:
            List of fastest TimingMetric objects
        """
        sorted_metrics = sorted(
            self.timing_metrics,
            key=lambda m: m.duration_seconds
        )
        return sorted_metrics[:count]
    
    def clear_metrics(self) -> None:
        """Clear all timing metrics."""
        self.timing_metrics.clear()
        self.active_timers.clear()
        self.test_start_time = None
        self.test_end_time = None
        logger.info("Cleared all timing metrics")
    
    def __enter__(self):
        """Context manager entry - start test timing."""
        self.start_test()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - end test timing."""
        self.end_test()
        return False
