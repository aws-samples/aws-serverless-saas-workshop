"""
Utility functions for end-to-end AWS testing system.

This module provides common utility functions used across components.
"""

import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional


def format_duration(duration: timedelta) -> str:
    """
    Format duration as human-readable string.
    
    Args:
        duration: Duration to format
    
    Returns:
        Formatted duration string (e.g., "1h 23m 45s")
    """
    total_seconds = int(duration.total_seconds())
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    
    parts = []
    if hours > 0:
        parts.append(f"{hours}h")
    if minutes > 0:
        parts.append(f"{minutes}m")
    if seconds > 0 or not parts:
        parts.append(f"{seconds}s")
    
    return " ".join(parts)


def format_timestamp(dt: datetime) -> str:
    """
    Format datetime as ISO 8601 string.
    
    Args:
        dt: Datetime to format
    
    Returns:
        ISO 8601 formatted string
    """
    return dt.isoformat()


def parse_timestamp(timestamp_str: str) -> datetime:
    """
    Parse ISO 8601 timestamp string.
    
    Args:
        timestamp_str: ISO 8601 formatted string
    
    Returns:
        Parsed datetime object
    """
    return datetime.fromisoformat(timestamp_str)


def ensure_directory(path: Path) -> Path:
    """
    Ensure directory exists, creating it if necessary.
    
    Args:
        path: Directory path
    
    Returns:
        Path object
    """
    path.mkdir(parents=True, exist_ok=True)
    return path


def safe_filename(name: str) -> str:
    """
    Convert string to safe filename.
    
    Args:
        name: Original name
    
    Returns:
        Safe filename string
    """
    # Replace unsafe characters with underscores
    unsafe_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|', ' ']
    safe_name = name
    for char in unsafe_chars:
        safe_name = safe_name.replace(char, '_')
    return safe_name


def run_command(
    command: List[str],
    cwd: Optional[Path] = None,
    timeout: Optional[int] = None,
    capture_output: bool = True
) -> subprocess.CompletedProcess:
    """
    Run shell command with error handling.
    
    Args:
        command: Command and arguments as list
        cwd: Working directory
        timeout: Timeout in seconds
        capture_output: Whether to capture stdout/stderr
    
    Returns:
        CompletedProcess instance
    
    Raises:
        subprocess.TimeoutExpired: If command times out
        subprocess.CalledProcessError: If command fails
    """
    return subprocess.run(
        command,
        cwd=cwd,
        timeout=timeout,
        capture_output=capture_output,
        text=True,
        check=False  # Don't raise exception on non-zero exit
    )


def filter_dict(data: Dict[str, Any], keys: List[str]) -> Dict[str, Any]:
    """
    Filter dictionary to include only specified keys.
    
    Args:
        data: Source dictionary
        keys: Keys to include
    
    Returns:
        Filtered dictionary
    """
    return {k: v for k, v in data.items() if k in keys}


def merge_dicts(dict1: Dict[str, Any], dict2: Dict[str, Any]) -> Dict[str, Any]:
    """
    Merge two dictionaries, with dict2 values taking precedence.
    
    Args:
        dict1: First dictionary
        dict2: Second dictionary
    
    Returns:
        Merged dictionary
    """
    result = dict1.copy()
    result.update(dict2)
    return result
