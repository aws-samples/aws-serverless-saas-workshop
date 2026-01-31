"""
API Monitor component for end-to-end AWS testing system.

This module tracks AWS API calls, responses, and errors using boto3 event system.
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional
from collections import defaultdict

import boto3
from botocore.exceptions import ClientError

from .models import APICallInfo, APIStatistics

logger = logging.getLogger(__name__)


class APIMonitor:
    """
    Monitors AWS API calls and captures response metadata.
    
    Uses boto3's event system to intercept API calls and responses,
    tracking status codes, request IDs, errors, and retry behavior.
    """
    
    def __init__(self):
        """Initialize API monitor with empty call tracking."""
        self.api_calls: List[APICallInfo] = []
        self.monitoring_enabled = False
        self._event_handlers = []
        
    def enable_monitoring(self) -> None:
        """
        Enable AWS API call monitoring.
        
        Registers event handlers with boto3 to capture API calls.
        """
        if self.monitoring_enabled:
            logger.warning("API monitoring is already enabled")
            return
        
        # Register event handlers for API calls
        event_system = boto3.Session().events
        
        # Handler for successful API responses
        handler_id = event_system.register(
            'after-call',
            self._handle_api_response
        )
        self._event_handlers.append(('after-call', handler_id))
        
        # Handler for API errors
        handler_id = event_system.register(
            'after-call-error',
            self._handle_api_error
        )
        self._event_handlers.append(('after-call-error', handler_id))
        
        self.monitoring_enabled = True
        logger.info("API monitoring enabled")
    
    def disable_monitoring(self) -> None:
        """
        Disable AWS API call monitoring.
        
        Unregisters all event handlers from boto3.
        """
        if not self.monitoring_enabled:
            return
        
        # Safety check: only unregister if we have handlers
        if not self._event_handlers:
            self.monitoring_enabled = False
            return
        
        event_system = boto3.Session().events
        for event_name, handler_id in self._event_handlers:
            try:
                event_system.unregister(event_name, handler_id)
            except Exception as e:
                logger.warning(f"Failed to unregister handler for {event_name}: {e}")
        
        self._event_handlers.clear()
        self.monitoring_enabled = False
        logger.info("API monitoring disabled")
    
    def _handle_api_response(self, event_name=None, **kwargs):
        """
        Handle successful API response event.
        
        Args:
            event_name: Name of the boto3 event
            **kwargs: Event data including parsed response
        """
        try:
            # Extract service and operation from event
            service = kwargs.get('service_name', 'unknown')
            operation = kwargs.get('operation_name', 'unknown')
            
            # Extract response metadata
            parsed = kwargs.get('parsed', {})
            response_metadata = parsed.get('ResponseMetadata', {})
            
            request_id = response_metadata.get('RequestId', 'unknown')
            status_code = response_metadata.get('HTTPStatusCode', 0)
            retry_attempts = response_metadata.get('RetryAttempts', 0)
            
            # Create API call info
            api_call = APICallInfo(
                service=service,
                operation=operation,
                request_id=request_id,
                status_code=status_code,
                timestamp=datetime.now(),
                retry_count=retry_attempts
            )
            
            self.api_calls.append(api_call)
            
        except Exception as e:
            logger.error(f"Error handling API response: {e}")
    
    def _handle_api_error(self, event_name=None, **kwargs):
        """
        Handle API error event.
        
        Args:
            event_name: Name of the boto3 event
            **kwargs: Event data including exception
        """
        try:
            # Extract service and operation from event
            service = kwargs.get('service_name', 'unknown')
            operation = kwargs.get('operation_name', 'unknown')
            
            # Extract error information
            exception = kwargs.get('exception')
            
            error_code = 'Unknown'
            error_message = str(exception)
            status_code = 0
            request_id = 'unknown'
            
            if isinstance(exception, ClientError):
                error_response = exception.response
                error_code = error_response.get('Error', {}).get('Code', 'Unknown')
                error_message = error_response.get('Error', {}).get('Message', str(exception))
                
                response_metadata = error_response.get('ResponseMetadata', {})
                status_code = response_metadata.get('HTTPStatusCode', 0)
                request_id = response_metadata.get('RequestId', 'unknown')
            
            # Create API call info for error
            api_call = APICallInfo(
                service=service,
                operation=operation,
                request_id=request_id,
                status_code=status_code,
                timestamp=datetime.now(),
                error_code=error_code,
                error_message=error_message
            )
            
            self.api_calls.append(api_call)
            
        except Exception as e:
            logger.error(f"Error handling API error: {e}")
    
    def capture_api_call(
        self,
        service: str,
        operation: str,
        request_id: str,
        status_code: int,
        timestamp: datetime,
        error_code: Optional[str] = None,
        error_message: Optional[str] = None,
        retry_count: int = 0
    ) -> None:
        """
        Manually capture an API call (for testing or special cases).
        
        Args:
            service: AWS service name
            operation: API operation name
            request_id: AWS request ID
            status_code: HTTP status code
            timestamp: Call timestamp
            error_code: Error code if call failed
            error_message: Error message if call failed
            retry_count: Number of retries
        """
        api_call = APICallInfo(
            service=service,
            operation=operation,
            request_id=request_id,
            status_code=status_code,
            timestamp=timestamp,
            error_code=error_code,
            error_message=error_message,
            retry_count=retry_count
        )
        self.api_calls.append(api_call)
    
    def capture_api_error(
        self,
        service: str,
        operation: str,
        error_code: str,
        error_message: str
    ) -> None:
        """
        Manually capture an API error (for testing or special cases).
        
        Args:
            service: AWS service name
            operation: API operation name
            error_code: Error code
            error_message: Error message
        """
        api_call = APICallInfo(
            service=service,
            operation=operation,
            request_id='manual',
            status_code=0,
            timestamp=datetime.now(),
            error_code=error_code,
            error_message=error_message
        )
        self.api_calls.append(api_call)
    
    def get_api_statistics(self) -> APIStatistics:
        """
        Calculate API call statistics.
        
        Returns:
            APIStatistics with aggregated metrics
        """
        total_calls = len(self.api_calls)
        successful_calls = sum(1 for call in self.api_calls if 200 <= call.status_code < 300)
        failed_calls = total_calls - successful_calls
        
        # Count calls by service
        calls_by_service: Dict[str, int] = defaultdict(int)
        successful_by_service: Dict[str, int] = defaultdict(int)
        
        for call in self.api_calls:
            calls_by_service[call.service] += 1
            if 200 <= call.status_code < 300:
                successful_by_service[call.service] += 1
        
        # Calculate success rate by service
        success_rate_by_service: Dict[str, float] = {}
        for service, total in calls_by_service.items():
            successful = successful_by_service.get(service, 0)
            success_rate_by_service[service] = (successful / total * 100) if total > 0 else 0.0
        
        # Get failed calls
        failed_calls_list = [call for call in self.api_calls if call.status_code < 200 or call.status_code >= 300]
        
        return APIStatistics(
            total_calls=total_calls,
            successful_calls=successful_calls,
            failed_calls=failed_calls,
            calls_by_service=dict(calls_by_service),
            success_rate_by_service=success_rate_by_service,
            failed_calls_list=failed_calls_list
        )
    
    def get_failed_calls(self) -> List[APICallInfo]:
        """
        Get all failed API calls.
        
        Returns:
            List of failed API calls
        """
        return [call for call in self.api_calls if call.status_code < 200 or call.status_code >= 300]
    
    def get_calls_by_service(self, service: str) -> List[APICallInfo]:
        """
        Get all API calls for a specific service.
        
        Args:
            service: AWS service name
            
        Returns:
            List of API calls for the service
        """
        return [call for call in self.api_calls if call.service == service]
    
    def get_calls_by_operation(self, service: str, operation: str) -> List[APICallInfo]:
        """
        Get all API calls for a specific service and operation.
        
        Args:
            service: AWS service name
            operation: API operation name
            
        Returns:
            List of API calls for the service and operation
        """
        return [
            call for call in self.api_calls
            if call.service == service and call.operation == operation
        ]
    
    def clear_calls(self) -> None:
        """Clear all captured API calls."""
        self.api_calls.clear()
        logger.info("Cleared all API call records")
    
    def __enter__(self):
        """Context manager entry - enable monitoring."""
        self.enable_monitoring()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - disable monitoring."""
        self.disable_monitoring()
        return False
