#!/bin/bash

# Lab6 Deployment with Screen Session
# This script runs the Lab6 deployment in a persistent screen session
# to prevent connection timeout issues during long deployments

SESSION_NAME="lab6-deployment"
LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"
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
echo "Logs will be saved to: $LOG_FILE"
echo ""
echo "To reconnect and monitor progress:"
echo "  screen -r $SESSION_NAME"
echo ""
echo "To view logs in real-time (from another terminal):"
echo "  tail -f $LOG_FILE"
echo ""
echo "To detach from the screen session (while keeping it running):"
echo "  Press: Ctrl+A, then D"
echo ""
echo "Starting deployment now..."
echo ""

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
    echo 'Lab6 Deployment Started: \$(date)'
    echo 'Log file: $LOG_FILE'
    echo '==================================================='
    echo ''
    
    ./deployment.sh -s -c $PROFILE_ARG
    EXIT_CODE=\$?
    
    echo ''
    echo '==================================================='
    if [ \$EXIT_CODE -eq 0 ]; then
        echo '✓ Deployment completed successfully!'
        echo ''
        echo 'Access your applications:'
        ADMIN_URL=\$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name serverless-saas-workshop-shared-lab6 --query \"Stacks[0].Outputs[?OutputKey=='AdminAppSite'].OutputValue\" --output text 2>/dev/null)
        LANDING_URL=\$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name serverless-saas-workshop-shared-lab6 --query \"Stacks[0].Outputs[?OutputKey=='LandingApplicationSite'].OutputValue\" --output text 2>/dev/null)
        APP_URL=\$(aws cloudformation describe-stacks $PROFILE_ARG --stack-name serverless-saas-workshop-shared-lab6 --query \"Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue\" --output text 2>/dev/null)
        echo \"  Admin: https://\$ADMIN_URL\"
        echo \"  Landing: https://\$LANDING_URL\"
        echo \"  App: https://\$APP_URL\"
    else
        echo '✗ Deployment failed with exit code: '\$EXIT_CODE
        echo ''
        echo 'Check the log file for details: $LOG_FILE'
    fi
    echo 'Completed at: \$(date)'
    echo '==================================================='
    echo ''
    echo 'Press Enter to close this screen session...'
    read
"

sleep 2

echo "✓ Screen session started successfully!"
echo ""
echo "Monitor deployment:"
echo "  screen -r $SESSION_NAME    # Reconnect to screen session"
echo "  tail -f $LOG_FILE          # Watch logs in real-time"
echo ""
echo "Check status:"
echo "  screen -list               # List all screen sessions"
