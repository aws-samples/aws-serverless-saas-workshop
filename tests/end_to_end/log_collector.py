"""
Log Collector component for end-to-end AWS testing system.

This module captures and organizes logs from all operations.
"""

import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from .logging_config import get_logger

logger = get_logger("log_collector")


@dataclass
class ScriptResult:
    """Result of script execution."""
    exit_code: int
    stdout: str
    stderr: str
    success: bool
    error_message: Optional[str] = None


class LogFile:
    """Represents a log file for an operation."""
    
    def __init__(self, path: Path):
        """
        Initialize log file.
        
        Args:
            path: Path to log file
        """
        self.path = path
        self.handle = None
    
    def open(self) -> None:
        """Open log file for writing."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = open(self.path, 'w', encoding='utf-8')
        logger.info(f"Opened log file: {self.path}")
    
    def write(self, message: str) -> None:
        """
        Write message to log file.
        
        Args:
            message: Message to write
        """
        if self.handle:
            self.handle.write(message)
            self.handle.flush()
    
    def close(self) -> None:
        """Close log file."""
        if self.handle:
            self.handle.close()
            self.handle = None
            logger.info(f"Closed log file: {self.path}")
    
    def __enter__(self):
        """Context manager entry."""
        self.open()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()


class LogCollector:
    """
    Captures and organizes logs from all operations.
    
    Creates separate log files for each operation, captures stdout/stderr,
    displays real-time progress to console, and organizes logs in structured hierarchy.
    """
    
    def __init__(self, log_directory: Path):
        """
        Initialize log collector.
        
        Args:
            log_directory: Base directory for log files
        """
        self.log_directory = Path(log_directory)
        self.log_directory.mkdir(parents=True, exist_ok=True)
        logger.info(f"LogCollector initialized with directory: {self.log_directory}")
    
    def create_log_file(
        self,
        operation: str,
        lab: Optional[str] = None
    ) -> LogFile:
        """
        Create log file for operation.
        
        Args:
            operation: Operation name (e.g., "cleanup", "deployment", "isolation")
            lab: Optional lab identifier (e.g., "lab1", "lab2")
        
        Returns:
            LogFile instance
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        if lab:
            filename = f"{operation}_{lab}_{timestamp}.log"
        else:
            filename = f"{operation}_{timestamp}.log"
        
        log_path = self.log_directory / filename
        
        logger.info(f"Creating log file: {log_path}")
        return LogFile(log_path)
    
    def log_to_console(
        self,
        message: str,
        level: str = "INFO"
    ) -> None:
        """
        Display message to console with timestamp.
        
        Args:
            message: Message to display
            level: Log level (INFO, WARNING, ERROR)
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        formatted_message = f"[{timestamp}] [{level}] {message}"
        
        if level == "ERROR":
            print(formatted_message, file=sys.stderr)
        else:
            print(formatted_message)
        
        sys.stdout.flush()
        sys.stderr.flush()
    
    def write_header(
        self,
        log_file: LogFile,
        operation: str,
        environment: dict
    ) -> None:
        """
        Write log file header with environment context.
        
        Args:
            log_file: Log file to write to
            operation: Operation name
            environment: Environment context (AWS profile, region, etc.)
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        header = [
            "=" * 80,
            f"Operation: {operation}",
            f"Timestamp: {timestamp}",
            "=" * 80,
            "",
            "Environment Context:",
            "-" * 80
        ]
        
        for key, value in environment.items():
            header.append(f"  {key}: {value}")
        
        header.extend(["", "=" * 80, ""])
        
        log_file.write("\n".join(header))
    
    def organize_logs(self) -> dict:
        """
        Organize logs by operation type.
        
        Returns:
            Dictionary mapping operation types to log file paths
        """
        logs_by_operation = {}
        
        for log_file in self.log_directory.glob("*.log"):
            operation_type = log_file.stem.split("_")[0]
            
            if operation_type not in logs_by_operation:
                logs_by_operation[operation_type] = []
            
            logs_by_operation[operation_type].append(log_file)
        
        # Sort by timestamp
        for operation_type in logs_by_operation:
            logs_by_operation[operation_type].sort()
        
        logger.info(f"Organized {len(logs_by_operation)} operation types")
        return logs_by_operation
    
    def capture_script_output(
        self,
        script_path: str,
        args: List[str],
        log_file: LogFile,
        environment: Optional[dict] = None
    ) -> ScriptResult:
        """
        Execute script and capture output to log file.
        
        Args:
            script_path: Path to script to execute
            args: Script arguments
            log_file: Log file to write output to
            environment: Optional environment context
        
        Returns:
            ScriptResult with exit code and output
        """
        logger.info(f"Executing script: {script_path} {' '.join(args)}")
        self.log_to_console(f"Executing: {script_path} {' '.join(args)}")
        
        # Write environment context if provided
        if environment:
            self.write_header(log_file, script_path, environment)
        
        # Build command
        command = [script_path] + args
        
        try:
            # Execute script and capture output
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            stdout_lines = []
            stderr_lines = []
            
            # Read stdout in real-time
            while True:
                stdout_line = process.stdout.readline()
                if stdout_line:
                    stdout_lines.append(stdout_line)
                    log_file.write(stdout_line)
                    # Display to console
                    print(stdout_line, end='')
                    sys.stdout.flush()
                
                # Check if process finished
                if process.poll() is not None:
                    break
            
            # Read any remaining output
            remaining_stdout, remaining_stderr = process.communicate()
            
            if remaining_stdout:
                stdout_lines.append(remaining_stdout)
                log_file.write(remaining_stdout)
                print(remaining_stdout, end='')
            
            if remaining_stderr:
                stderr_lines.append(remaining_stderr)
                log_file.write(f"\n--- STDERR ---\n{remaining_stderr}")
                print(remaining_stderr, end='', file=sys.stderr)
            
            exit_code = process.returncode
            stdout = ''.join(stdout_lines)
            stderr = ''.join(stderr_lines)
            
            # Write exit code to log
            self.capture_exit_code(exit_code, log_file)
            
            success = exit_code == 0
            error_message = None if success else f"Script exited with code {exit_code}"
            
            if success:
                self.log_to_console(f"Script completed successfully: {script_path}")
            else:
                self.log_to_console(
                    f"Script failed with exit code {exit_code}: {script_path}",
                    level="ERROR"
                )
            
            return ScriptResult(
                exit_code=exit_code,
                stdout=stdout,
                stderr=stderr,
                success=success,
                error_message=error_message
            )
        
        except Exception as e:
            error_message = f"Failed to execute script: {str(e)}"
            logger.error(error_message)
            self.log_to_console(error_message, level="ERROR")
            
            log_file.write(f"\n\nERROR: {error_message}\n")
            
            return ScriptResult(
                exit_code=-1,
                stdout="",
                stderr=str(e),
                success=False,
                error_message=error_message
            )
    
    def capture_exit_code(
        self,
        exit_code: int,
        log_file: LogFile
    ) -> None:
        """
        Capture script exit code in log file.
        
        Args:
            exit_code: Script exit code
            log_file: Log file to write to
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        footer = [
            "",
            "=" * 80,
            f"Script Exit Code: {exit_code}",
            f"Timestamp: {timestamp}",
            "=" * 80
        ]
        
        log_file.write("\n".join(footer))
