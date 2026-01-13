#!/bin/bash

# Lab6 Deployment with Screen Session
# This script runs the Lab6 deployment in a persistent screen session
# to prevent connection timeout issues during long deployments

SESSION_NAME="lab6-deployment"

# Check if screen session already exists
if screen -list | grep -q "$SESSION_NAME"; then
    echo "⚠ Warning: Screen session '$SESSION_NAME' already exists!"
    echo ""
    echo "To reconnect to the existing session:"
    echo "  screen -r $SESSION_NAME"
    echo ""
    echo "To kill the existing session and start fresh:"
    echo "  screen -X -S $SESSION_NAME quit"
    echo "  ./deploy-with-screen.sh"
    exit 1
fi

echo "Starting Lab6 deployment in screen session: $SESSION_NAME"
echo "=========================================================="
echo ""
echo "The deployment will run in the background."
echo "Estimated time: 15-25 minutes"
echo ""
echo "To reconnect and monitor progress:"
echo "  screen -r $SESSION_NAME"
echo ""
echo "To detach from the screen session (while keeping it running):"
echo "  Press: Ctrl+A, then D"
echo ""
echo "Starting deployment now..."
echo ""

# Run deployment in detached screen session
screen -dmS "$SESSION_NAME" bash -c '
    cd "$(dirname "$0")"
    echo "==================================================="
    echo "Lab6 Deployment Started: $(date)"
    echo "==================================================="
    echo ""
    
    ./deployment.sh
    EXIT_CODE=$?
    
    echo ""
    echo "==================================================="
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✓ Deployment completed successfully!"
    else
        echo "✗ Deployment failed with exit code: $EXIT_CODE"
    fi
    echo "Completed at: $(date)"
    echo "==================================================="
    echo ""
    echo "Press Enter to close this screen session..."
    read
'

sleep 2

echo "✓ Screen session started successfully!"
echo ""
echo "Reconnect anytime with:"
echo "  screen -r $SESSION_NAME"
