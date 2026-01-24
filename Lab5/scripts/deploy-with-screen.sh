#!/bin/bash

# Helper script to run deployment in a screen session
# This prevents connection timeouts during long deployments

SESSION_NAME="lab5-deployment"
AWS_PROFILE=""

# Parse command line arguments for --profile
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE=$2
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [--profile <profile>]"
            exit 1
            ;;
    esac
done

# Check if screen session already exists
screen -list | grep -q "$SESSION_NAME"
if [ $? -eq 0 ]; then
    echo "⚠️  A deployment session is already running!"
    echo ""
    echo "To reconnect to it, run:"
    echo "  screen -r $SESSION_NAME"
    echo ""
    echo "To kill it and start fresh, run:"
    echo "  screen -X -S $SESSION_NAME quit"
    echo "  Then run this script again"
    exit 1
fi

echo "=========================================="
echo "Starting Lab5 Deployment in Screen Session"
echo "=========================================="
echo ""
echo "The deployment will run in a persistent session."
echo "You can safely disconnect and it will continue running."
echo ""
echo "Useful commands:"
echo "  • Detach from session: Ctrl+A, then D"
echo "  • Reconnect later: screen -r $SESSION_NAME"
echo "  • View all sessions: screen -ls"
echo ""
echo "Starting deployment in 3 seconds..."
sleep 3

# Get the absolute path to the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Build profile argument if provided
PROFILE_ARG=""
if [[ -n "$AWS_PROFILE" ]]; then
    PROFILE_ARG="--profile $AWS_PROFILE"
fi

# Run deployment in detached screen session with logging
screen -dmS "$SESSION_NAME" bash -c "
    cd '$SCRIPT_DIR'
    
    # Redirect all output to log file and screen
    exec > >(tee -a '$LOG_FILE') 2>&1
    
    echo '==================================================='
    echo 'Lab5 Deployment Started: \$(date)'
    echo 'Log file: $LOG_FILE'
    echo '==================================================='
    echo ''
    
    ./deployment.sh -s -c $AWS_PROFILE_ARG
    EXIT_CODE=\$?
    echo ''
    echo '=========================================='
    if [ \$EXIT_CODE -eq 0 ]; then
        echo 'Deployment Completed Successfully!'
    else
        echo 'Deployment Failed with exit code: '\$EXIT_CODE
    fi
    echo 'Time: \$(date)'
    echo '=========================================='
    echo ''
    echo 'Press Enter to close this session or Ctrl+A then D to keep it open'
    exec bash
"

echo ""
echo "✓ Deployment started in background screen session"
echo ""
echo "To view the deployment progress, run:"
echo "  screen -r $SESSION_NAME"
echo ""
