"""
Script Executor component for end-to-end AWS testing system.

This module executes workshop scripts with proper format and error handling.
"""

import os
import stat
import subprocess
from pathlib import Path
from typing import List

from .log_collector import LogFile, ScriptResult
from .logging_config import get_logger

logger = get_logger("script_executor")


class ScriptExecutor:
    """
    Executes workshop scripts with proper format and error handling.
    
    Ensures scripts are executed using ./script.sh format (not bash script.sh),
    verifies execute permissions, and validates shebang lines.
    """
    
    def __init__(self):
        """Initialize Script Executor."""
        logger.info("ScriptExecutor initialized")
    
    def execute_script(
        self,
        script_path: Path,
        args: List[str],
        log_file: LogFile,
        environment: dict = None
    ) -> ScriptResult:
        """
        Execute script directly (not with bash command).
        
        Args:
            script_path: Path to script
            args: Script arguments
            log_file: Log file for output
            environment: Optional environment context
        
        Returns:
            ScriptResult with execution details
        """
        logger.info(f"Executing script: {script_path}")
        
        # Verify script exists
        if not script_path.exists():
            error_msg = f"Script not found: {script_path}"
            logger.error(error_msg)
            return ScriptResult(
                exit_code=-1,
                stdout="",
                stderr=error_msg,
                success=False,
                error_message=error_msg
            )
        
        # Verify script has execute permissions
        if not self.verify_executable(script_path):
            logger.warning(f"Script not executable, adding permissions: {script_path}")
            self.make_executable(script_path)
        
        # Validate shebang line
        if not self.validate_script_format(script_path):
            logger.warning(f"Script missing or invalid shebang line: {script_path}")
        
        # Execute script using ./script.sh format
        # Convert to absolute path and execute directly
        abs_script_path = script_path.resolve()
        
        try:
            # Build command - execute script directly
            command = [str(abs_script_path)] + args
            
            logger.info(f"Executing command: {' '.join(command)}")
            
            # Execute and capture output
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True,
                cwd=script_path.parent  # Execute in script's directory
            )
            
            stdout_lines = []
            stderr_lines = []
            
            # Read stdout in real-time
            while True:
                stdout_line = process.stdout.readline()
                if stdout_line:
                    stdout_lines.append(stdout_line)
                    log_file.write(stdout_line)
                
                # Check if process finished
                if process.poll() is not None:
                    break
            
            # Read any remaining output
            remaining_stdout, remaining_stderr = process.communicate()
            
            if remaining_stdout:
                stdout_lines.append(remaining_stdout)
                log_file.write(remaining_stdout)
            
            if remaining_stderr:
                stderr_lines.append(remaining_stderr)
                log_file.write(f"\n--- STDERR ---\n{remaining_stderr}")
            
            exit_code = process.returncode
            stdout = ''.join(stdout_lines)
            stderr = ''.join(stderr_lines)
            
            success = exit_code == 0
            error_message = None if success else f"Script exited with code {exit_code}"
            
            if success:
                logger.info(f"Script completed successfully: {script_path}")
            else:
                logger.error(f"Script failed with exit code {exit_code}: {script_path}")
            
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
            
            log_file.write(f"\n\nERROR: {error_message}\n")
            
            return ScriptResult(
                exit_code=-1,
                stdout="",
                stderr=str(e),
                success=False,
                error_message=error_message
            )
    
    def verify_executable(self, script_path: Path) -> bool:
        """
        Verify script has execute permissions.
        
        Args:
            script_path: Path to script
        
        Returns:
            True if script is executable
        """
        try:
            st = os.stat(script_path)
            is_executable = bool(st.st_mode & stat.S_IXUSR)
            
            if is_executable:
                logger.debug(f"Script is executable: {script_path}")
            else:
                logger.warning(f"Script is not executable: {script_path}")
            
            return is_executable
        
        except Exception as e:
            logger.error(f"Failed to check execute permissions: {e}")
            return False
    
    def make_executable(self, script_path: Path) -> None:
        """
        Add execute permissions to script.
        
        Args:
            script_path: Path to script
        """
        try:
            st = os.stat(script_path)
            os.chmod(script_path, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            logger.info(f"Added execute permissions to: {script_path}")
        
        except Exception as e:
            logger.error(f"Failed to add execute permissions: {e}")
    
    def validate_script_format(self, script_path: Path) -> bool:
        """
        Validate script has proper shebang line.
        
        Args:
            script_path: Path to script
        
        Returns:
            True if script has valid shebang line
        """
        try:
            with open(script_path, 'r') as f:
                first_line = f.readline().strip()
            
            # Check for shebang line
            if first_line.startswith('#!'):
                logger.debug(f"Script has valid shebang: {first_line}")
                return True
            else:
                logger.warning(f"Script missing shebang line: {script_path}")
                return False
        
        except Exception as e:
            logger.error(f"Failed to validate script format: {e}")
            return False
