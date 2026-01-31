#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

##############################################################################
# Update Exit Codes in All Lab Cleanup Scripts
#
# This script updates Lab3, Lab4, Lab5, Lab7, and global cleanup scripts
# to integrate the exit-codes.sh module.
#
# Changes made:
# 1. Source exit-codes.sh after parameter-parsing-template.sh
# 2. Add setup_exit_handlers() after confirmation
# 3. Replace exit 0 (user cancellation) with exit_with_code $EXIT_USER_INTERRUPT
# 4. Replace exit 1 with exit_with_code $EXIT_FAILURE
# 5. Add final verification using cleanup-verification module
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Lab3 cleanup script
print_message "$YELLOW" "Updating Lab3 cleanup script..."
LAB3_SCRIPT="$SCRIPT_DIR/../Lab3/scripts/cleanup.sh"

# Add exit-codes source after parameter-parsing-template
sed -i.bak '/source.*parameter-parsing-template.sh/a\
\
# Source exit codes module\
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"
' "$LAB3_SCRIPT"

# Add setup_exit_handlers after confirmation
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/s/exit 0/exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"/' "$LAB3_SCRIPT"
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/a\
\
# Setup exit handlers after confirmation\
setup_exit_handlers
' "$LAB3_SCRIPT"

# Replace exit 1 with exit_with_code
sed -i.bak 's/exit 1$/exit_with_code $EXIT_FAILURE "Operation failed"/g' "$LAB3_SCRIPT"

print_message "$GREEN" "Lab3 cleanup script updated"

# Lab4 cleanup script
print_message "$YELLOW" "Updating Lab4 cleanup script..."
LAB4_SCRIPT="$SCRIPT_DIR/../Lab4/scripts/cleanup.sh"

# Similar updates for Lab4
sed -i.bak '/source.*parameter-parsing-template.sh/a\
\
# Source exit codes module\
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"
' "$LAB4_SCRIPT"

sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/s/exit 0/exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"/' "$LAB4_SCRIPT"
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/a\
\
# Setup exit handlers after confirmation\
setup_exit_handlers
' "$LAB4_SCRIPT"

sed -i.bak 's/exit 1$/exit_with_code $EXIT_FAILURE "Operation failed"/g' "$LAB4_SCRIPT"

print_message "$GREEN" "Lab4 cleanup script updated"

# Lab5 cleanup script
print_message "$YELLOW" "Updating Lab5 cleanup script..."
LAB5_SCRIPT="$SCRIPT_DIR/../Lab5/scripts/cleanup.sh"

sed -i.bak '/source.*parameter-parsing-template.sh/a\
\
# Source exit codes module\
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"
' "$LAB5_SCRIPT"

sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/s/exit 0/exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"/' "$LAB5_SCRIPT"
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/a\
\
# Setup exit handlers after confirmation\
setup_exit_handlers
' "$LAB5_SCRIPT"

sed -i.bak 's/exit 1$/exit_with_code $EXIT_FAILURE "Operation failed"/g' "$LAB5_SCRIPT"

print_message "$GREEN" "Lab5 cleanup script updated"

# Lab7 cleanup script
print_message "$YELLOW" "Updating Lab7 cleanup script..."
LAB7_SCRIPT="$SCRIPT_DIR/../Lab7/scripts/cleanup.sh"

sed -i.bak '/source.*parameter-parsing-template.sh/a\
\
# Source exit codes module\
source "$SCRIPT_DIR/../../scripts/lib/exit-codes.sh"
' "$LAB7_SCRIPT"

sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/s/exit 0/exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"/' "$LAB7_SCRIPT"
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/a\
\
# Setup exit handlers after confirmation\
setup_exit_handlers
' "$LAB7_SCRIPT"

sed -i.bak 's/exit 1$/exit_with_code $EXIT_FAILURE "Operation failed"/g' "$LAB7_SCRIPT"

print_message "$GREEN" "Lab7 cleanup script updated"

# Global cleanup script
print_message "$YELLOW" "Updating global cleanup script..."
GLOBAL_SCRIPT="$SCRIPT_DIR/cleanup-all-labs.sh"

sed -i.bak '/source.*parameter-parsing-template.sh/a\
\
# Source exit codes module\
source "$SCRIPT_DIR/lib/exit-codes.sh"
' "$GLOBAL_SCRIPT"

sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/s/exit 0/exit_with_code $EXIT_USER_INTERRUPT "User cancelled cleanup"/' "$GLOBAL_SCRIPT"
sed -i.bak '/if \[\[ ! \$REPLY =~ \^\[Yy\]\[Ee\]\[Ss\]\$ \]\]; then/,/fi/a\
\
# Setup exit handlers after confirmation\
setup_exit_handlers
' "$GLOBAL_SCRIPT"

sed -i.bak 's/exit 1$/exit_with_code $EXIT_FAILURE "Operation failed"/g' "$GLOBAL_SCRIPT"

print_message "$GREEN" "Global cleanup script updated"

print_message "$GREEN" "All cleanup scripts updated successfully!"
print_message "$YELLOW" "Backup files created with .bak extension"
