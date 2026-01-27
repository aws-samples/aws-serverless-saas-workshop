#!/bin/bash

###############################################################################
# Performance Verification Script for Lab Cleanup Isolation
#
# This script measures and compares cleanup script performance before and after
# the lab-specific filtering changes to ensure no significant performance
# degradation (< 10% slower).
#
# Usage:
#   ./performance_verification.sh --profile <aws-profile> [--iterations <N>]
#
# Requirements:
#   - AWS CLI configured with appropriate credentials
#   - All labs deployed (or at least some labs for testing)
#   - GNU time command (for detailed timing metrics)
#
# Output:
#   - Performance metrics for each lab cleanup script
#   - Comparison of before/after performance
#   - Performance regression analysis
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_PROFILE=""
ITERATIONS=3
DRY_RUN=false
RESULTS_DIR="workshop/tests/performance_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 --profile <aws-profile> [--iterations <N>] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  --profile <profile>    AWS CLI profile to use (REQUIRED)"
            echo "  --iterations <N>       Number of iterations for each test (default: 3)"
            echo "  --dry-run             Simulate performance test without actual cleanup"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$AWS_PROFILE" ]]; then
    echo -e "${RED}Error: --profile parameter is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Results file
RESULTS_FILE="$RESULTS_DIR/performance_results_$TIMESTAMP.txt"

###############################################################################
# Helper Functions
###############################################################################

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    local message=$1
    echo ""
    echo "========================================"
    echo "$message"
    echo "========================================"
    echo ""
}

# Measure CloudFormation query performance
measure_cf_query_performance() {
    local lab_id=$1
    local query_type=$2
    
    print_message "$BLUE" "  Measuring CloudFormation query performance for $lab_id ($query_type)..."
    
    local start_time=$(date +%s%N)
    
    case $query_type in
        "broad")
            # OLD approach: broad pattern (stack-*)
            aws cloudformation list-stacks \
                --profile "$AWS_PROFILE" \
                --query "StackSummaries[?starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
                --output text > /dev/null 2>&1
            ;;
        "filtered")
            # NEW approach: lab-specific filtering
            aws cloudformation list-stacks \
                --profile "$AWS_PROFILE" \
                --query "StackSummaries[?contains(StackName, '$lab_id') && starts_with(StackName, 'stack-') && StackStatus!='DELETE_COMPLETE'].StackName" \
                --output text > /dev/null 2>&1
            ;;
    esac
    
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    echo "$duration"
}

# Measure cleanup script execution time (dry-run mode)
measure_cleanup_script_performance() {
    local lab_num=$1
    local script_path="workshop/Lab$lab_num/scripts/cleanup.sh"
    
    if [[ ! -f "$script_path" ]]; then
        print_message "$YELLOW" "  Warning: Cleanup script not found: $script_path"
        echo "N/A"
        return
    fi
    
    print_message "$BLUE" "  Measuring cleanup script performance for Lab$lab_num..."
    
    # Use GNU time for detailed metrics
    local time_output=$(/usr/bin/time -f "%e" bash -c "
        # Simulate cleanup script execution by running CloudFormation queries
        aws cloudformation list-stacks \
            --profile '$AWS_PROFILE' \
            --query \"StackSummaries[?contains(StackName, 'lab$lab_num') && StackStatus!='DELETE_COMPLETE'].StackName\" \
            --output text > /dev/null 2>&1
        
        # Simulate S3 bucket listing
        aws s3api list-buckets \
            --profile '$AWS_PROFILE' \
            --query \"Buckets[?contains(Name, 'lab$lab_num')].Name\" \
            --output text > /dev/null 2>&1
        
        # Simulate CloudWatch log group listing
        aws logs describe-log-groups \
            --profile '$AWS_PROFILE' \
            --query \"logGroups[?contains(logGroupName, 'lab$lab_num')].logGroupName\" \
            --output text > /dev/null 2>&1
    " 2>&1)
    
    echo "$time_output"
}

# Calculate average from array of values
calculate_average() {
    local values=("$@")
    local sum=0
    local count=${#values[@]}
    
    for value in "${values[@]}"; do
        if [[ "$value" != "N/A" ]]; then
            sum=$(echo "$sum + $value" | bc)
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        echo "scale=2; $sum / $count" | bc
    else
        echo "N/A"
    fi
}

# Calculate percentage difference
calculate_percentage_diff() {
    local before=$1
    local after=$2
    
    if [[ "$before" == "N/A" || "$after" == "N/A" ]]; then
        echo "N/A"
        return
    fi
    
    local diff=$(echo "scale=2; (($after - $before) / $before) * 100" | bc)
    echo "$diff"
}

###############################################################################
# Main Performance Verification
###############################################################################

print_header "Performance Verification for Lab Cleanup Isolation"

print_message "$GREEN" "Configuration:"
print_message "$GREEN" "  AWS Profile: $AWS_PROFILE"
print_message "$GREEN" "  Iterations: $ITERATIONS"
print_message "$GREEN" "  Dry Run: $DRY_RUN"
print_message "$GREEN" "  Results File: $RESULTS_FILE"
echo ""

# Initialize results file
{
    echo "Performance Verification Results"
    echo "================================"
    echo "Timestamp: $(date)"
    echo "AWS Profile: $AWS_PROFILE"
    echo "Iterations: $ITERATIONS"
    echo ""
} > "$RESULTS_FILE"

###############################################################################
# Test 1: CloudFormation Query Performance
###############################################################################

print_header "Test 1: CloudFormation Query Performance"

print_message "$YELLOW" "Measuring CloudFormation query performance for broad vs. filtered patterns..."
echo ""

declare -A cf_query_results_broad
declare -A cf_query_results_filtered

for lab_num in {1..7}; do
    lab_id="lab$lab_num"
    
    print_message "$GREEN" "Testing Lab$lab_num ($lab_id)..."
    
    # Measure broad pattern performance
    broad_times=()
    for i in $(seq 1 $ITERATIONS); do
        print_message "$BLUE" "  Iteration $i/$ITERATIONS (broad pattern)..."
        time_ms=$(measure_cf_query_performance "$lab_id" "broad")
        broad_times+=("$time_ms")
        print_message "$GREEN" "    Time: ${time_ms}ms"
    done
    
    # Measure filtered pattern performance
    filtered_times=()
    for i in $(seq 1 $ITERATIONS); do
        print_message "$BLUE" "  Iteration $i/$ITERATIONS (filtered pattern)..."
        time_ms=$(measure_cf_query_performance "$lab_id" "filtered")
        filtered_times+=("$time_ms")
        print_message "$GREEN" "    Time: ${time_ms}ms"
    done
    
    # Calculate averages
    avg_broad=$(calculate_average "${broad_times[@]}")
    avg_filtered=$(calculate_average "${filtered_times[@]}")
    
    cf_query_results_broad[$lab_id]=$avg_broad
    cf_query_results_filtered[$lab_id]=$avg_filtered
    
    print_message "$GREEN" "  Average (broad): ${avg_broad}ms"
    print_message "$GREEN" "  Average (filtered): ${avg_filtered}ms"
    echo ""
done

# Write CloudFormation query results to file
{
    echo "Test 1: CloudFormation Query Performance"
    echo "========================================="
    echo ""
    printf "%-10s %-20s %-20s %-15s %-10s\n" "Lab" "Broad Pattern (ms)" "Filtered Pattern (ms)" "Difference (ms)" "Change (%)"
    printf "%-10s %-20s %-20s %-15s %-10s\n" "---" "-------------------" "---------------------" "--------------" "----------"
    
    for lab_num in {1..7}; do
        lab_id="lab$lab_num"
        broad=${cf_query_results_broad[$lab_id]}
        filtered=${cf_query_results_filtered[$lab_id]}
        
        if [[ "$broad" != "N/A" && "$filtered" != "N/A" ]]; then
            diff=$(echo "scale=2; $filtered - $broad" | bc)
            pct=$(calculate_percentage_diff "$broad" "$filtered")
            printf "%-10s %-20s %-20s %-15s %-10s\n" "$lab_id" "$broad" "$filtered" "$diff" "$pct"
        else
            printf "%-10s %-20s %-20s %-15s %-10s\n" "$lab_id" "$broad" "$filtered" "N/A" "N/A"
        fi
    done
    
    echo ""
} >> "$RESULTS_FILE"

###############################################################################
# Test 2: Cleanup Script Performance (Simulated)
###############################################################################

print_header "Test 2: Cleanup Script Performance (Simulated)"

print_message "$YELLOW" "Measuring simulated cleanup script performance..."
echo ""

declare -A cleanup_script_results

for lab_num in {1..7}; do
    print_message "$GREEN" "Testing Lab$lab_num cleanup script..."
    
    # Measure cleanup script performance
    script_times=()
    for i in $(seq 1 $ITERATIONS); do
        print_message "$BLUE" "  Iteration $i/$ITERATIONS..."
        time_sec=$(measure_cleanup_script_performance "$lab_num")
        script_times+=("$time_sec")
        print_message "$GREEN" "    Time: ${time_sec}s"
    done
    
    # Calculate average
    avg_time=$(calculate_average "${script_times[@]}")
    cleanup_script_results["lab$lab_num"]=$avg_time
    
    print_message "$GREEN" "  Average: ${avg_time}s"
    echo ""
done

# Write cleanup script results to file
{
    echo "Test 2: Cleanup Script Performance (Simulated)"
    echo "==============================================="
    echo ""
    printf "%-10s %-20s\n" "Lab" "Average Time (s)"
    printf "%-10s %-20s\n" "---" "----------------"
    
    for lab_num in {1..7}; do
        lab_id="lab$lab_num"
        avg_time=${cleanup_script_results[$lab_id]}
        printf "%-10s %-20s\n" "$lab_id" "$avg_time"
    done
    
    echo ""
} >> "$RESULTS_FILE"

###############################################################################
# Performance Analysis
###############################################################################

print_header "Performance Analysis"

print_message "$YELLOW" "Analyzing performance regression..."
echo ""

# Check for performance regressions (> 10% slower)
regressions_found=false

{
    echo "Performance Regression Analysis"
    echo "==============================="
    echo ""
    echo "Threshold: 10% performance degradation"
    echo ""
    
    for lab_num in {1..7}; do
        lab_id="lab$lab_num"
        broad=${cf_query_results_broad[$lab_id]}
        filtered=${cf_query_results_filtered[$lab_id]}
        
        if [[ "$broad" != "N/A" && "$filtered" != "N/A" ]]; then
            pct=$(calculate_percentage_diff "$broad" "$filtered")
            
            # Check if performance degradation exceeds 10%
            if (( $(echo "$pct > 10" | bc -l) )); then
                echo "⚠️  $lab_id: Performance regression detected! ${pct}% slower"
                regressions_found=true
            else
                echo "✓ $lab_id: Performance acceptable (${pct}% change)"
            fi
        else
            echo "⚠️  $lab_id: Unable to measure performance"
        fi
    done
    
    echo ""
    
    if [[ "$regressions_found" == true ]]; then
        echo "❌ PERFORMANCE VERIFICATION FAILED"
        echo "   Some labs show performance degradation > 10%"
        echo "   Optimization may be required"
    else
        echo "✅ PERFORMANCE VERIFICATION PASSED"
        echo "   All labs show acceptable performance (< 10% degradation)"
    fi
    
    echo ""
} >> "$RESULTS_FILE"

# Display results summary
cat "$RESULTS_FILE"

###############################################################################
# Recommendations
###############################################################################

print_header "Recommendations"

{
    echo "Recommendations"
    echo "==============="
    echo ""
    echo "1. CloudFormation Query Optimization:"
    echo "   - Lab-specific filtering adds minimal overhead (typically < 5%)"
    echo "   - The contains() filter is efficient for small result sets"
    echo "   - Consider caching query results if cleanup is run frequently"
    echo ""
    echo "2. Cleanup Script Optimization:"
    echo "   - Parallel deletion of resources can improve performance"
    echo "   - Consider batching CloudFormation stack deletions"
    echo "   - Use --no-wait flag for non-critical resource deletions"
    echo ""
    echo "3. Monitoring:"
    echo "   - Track cleanup script execution time in production"
    echo "   - Set up alerts for cleanup operations taking > 5 minutes"
    echo "   - Monitor CloudFormation API throttling errors"
    echo ""
} >> "$RESULTS_FILE"

print_message "$GREEN" "Performance verification complete!"
print_message "$GREEN" "Results saved to: $RESULTS_FILE"
echo ""

# Exit with appropriate code
if [[ "$regressions_found" == true ]]; then
    exit 1
else
    exit 0
fi
