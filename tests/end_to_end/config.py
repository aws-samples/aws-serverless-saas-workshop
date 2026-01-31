"""
Configuration module for end-to-end AWS testing system.

This module defines the test configuration parameters and default values.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class TestConfig:
    """Configuration for end-to-end AWS testing."""
    
    # Required parameters
    aws_profile: str
    email: str
    
    # Optional parameters with defaults
    aws_region: str = "us-east-1"
    parallel_mode: bool = True
    timeout_hours: int = 6
    log_directory: Path = field(default_factory=lambda: Path("test_logs"))
    report_directory: Path = field(default_factory=lambda: Path("test_reports"))
    
    # Optional tenant email for Lab3-4
    tenant_email: Optional[str] = None
    
    def __post_init__(self):
        """Validate configuration after initialization."""
        # Convert string paths to Path objects
        if isinstance(self.log_directory, str):
            self.log_directory = Path(self.log_directory)
        if isinstance(self.report_directory, str):
            self.report_directory = Path(self.report_directory)
        
        # Validate required parameters
        if not self.aws_profile:
            raise ValueError("aws_profile is required")
        if not self.email:
            raise ValueError("email is required")
        
        # Validate timeout
        if self.timeout_hours <= 0:
            raise ValueError("timeout_hours must be positive")
        
        # Create directories if they don't exist
        self.log_directory.mkdir(parents=True, exist_ok=True)
        self.report_directory.mkdir(parents=True, exist_ok=True)
    
    def to_dict(self) -> dict:
        """Convert configuration to dictionary."""
        return {
            "aws_profile": self.aws_profile,
            "aws_region": self.aws_region,
            "email": self.email,
            "tenant_email": self.tenant_email,
            "parallel_mode": self.parallel_mode,
            "timeout_hours": self.timeout_hours,
            "log_directory": str(self.log_directory),
            "report_directory": str(self.report_directory),
        }
