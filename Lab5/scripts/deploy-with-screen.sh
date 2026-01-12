#!/bin/bash

# Helper script to run deployment in a screen session
# This prevents connection timeouts during long deployments

SESSION_NAME="lab5-deployment"

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

# Get the current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create a new screen session and run the deployment
screen -dmS "$SESSION_NAME" bash -c "
    cd '$SCRIPT_DIR'
    echo '=========================================='
    echo 'Lab5 Deployment Started'
    echo 'Time: \$(date)'
    echo '=========================================='
    echo ''
    ./deployment.sh -s -c
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
