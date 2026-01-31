"""
Logging infrastructure for end-to-end AWS testing system.

This module sets up logging with both console and file handlers.
"""

import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


def setup_logging(
    log_directory: Path,
    log_level: int = logging.INFO,
    console_output: bool = True
) -> logging.Logger:
    """
    Set up logging infrastructure with console and file handlers.
    
    Args:
        log_directory: Directory for log files
        log_level: Logging level (default: INFO)
        console_output: Whether to output to console (default: True)
    
    Returns:
        Configured logger instance
    """
    # Create logger
    logger = logging.getLogger("end_to_end_testing")
    logger.setLevel(log_level)
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Create formatters
    detailed_formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    
    console_formatter = logging.Formatter(
        fmt="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%H:%M:%S"
    )
    
    # Create file handler
    log_directory.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_directory / f"end_to_end_test_{timestamp}.log"
    
    file_handler = logging.FileHandler(log_file, mode='w', encoding='utf-8')
    file_handler.setLevel(log_level)
    file_handler.setFormatter(detailed_formatter)
    logger.addHandler(file_handler)
    
    # Create console handler if requested
    if console_output:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(log_level)
        console_handler.setFormatter(console_formatter)
        logger.addHandler(console_handler)
    
    logger.info(f"Logging initialized. Log file: {log_file}")
    
    return logger


def get_logger(name: Optional[str] = None) -> logging.Logger:
    """
    Get logger instance.
    
    Args:
        name: Logger name (default: end_to_end_testing)
    
    Returns:
        Logger instance
    """
    if name:
        return logging.getLogger(f"end_to_end_testing.{name}")
    return logging.getLogger("end_to_end_testing")
