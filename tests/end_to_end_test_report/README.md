# End-to-End Test Report

This directory contains comprehensive test results and logs from the end-to-end cleanup isolation test suite.

## Directory Structure

```
end_to_end_test_report/
├── README.md                           # This file
├── SUMMARY.md                          # High-level test summary (auto-generated)
├── end_to_end_test_report.json        # Complete test data in JSON format
├── extract_step_logs.py                # Script to extract individual step logs
├── generate_summary_report.py          # Script to generate SUMMARY.md
└── logs/                               # Individual step log files
    ├── step_01_cleanup_all_labs_ensure_clean_state.log
    ├── step_02_deploy_all_labs.log
    ├── step_03_cleanup_lab1.log
    └── ... (one log file per test step)
```

## File Descriptions

### SUMMARY.md
High-level overview of the test run including:
- Test execution metadata (timestamp, duration, mode)
- Pass/fail summary with statistics
- Quick reference to failed steps
- Resource count changes across all steps
- Recommendations and next actions

### end_to_end_test_report.json
Complete test data in structured JSON format containing:
- Test configuration (dry-run mode, AWS profile, email)
- Detailed step-by-step execution data
- Resource snapshots (before/after each step)
- Timing information for each step
- Error messages and warnings
- Resource deletion tracking

### step_XX_<step_name>.log
Individual log files for each test step (stored in `logs/` subdirectory) containing:
- Step metadata (number, name, timestamp, duration)
- Success/failure status
- Resource counts (before, after, deleted)
- Detailed resource listings (stacks, S3 buckets, log groups, Cognito pools)
- Error messages and warnings specific to that step

## Viewing Reports

### Quick Summary
```bash
cat SUMMARY.md
```

### Full JSON Report (formatted)
```bash
cat end_to_end_test_report.json | jq .
```

### Specific Step Details
```bash
cat logs/step_03_cleanup_lab1.log
```

### Find Failed Steps
```bash
grep -l "Success: False" logs/step_*.log
```

### Resource Count Changes
```bash
grep "Resources Before:" logs/step_*.log
grep "Resources After:" logs/step_*.log
```

## Analyzing Test Results

### Check Overall Test Status
```bash
# View summary
cat SUMMARY.md | head -20

# Check pass/fail counts
jq '.passed_steps, .failed_steps' end_to_end_test_report.json
```

### Investigate Failed Steps
```bash
# List failed steps
jq '.steps[] | select(.success == false) | {step_number, step_name, error_message}' end_to_end_test_report.json

# View detailed log for a failed step
cat step_XX_<failed_step_name>.log
```

### Track Resource Changes
```bash
# View resource counts across all steps
jq '.steps[] | {step: .step_number, before: .resources_before.total_count, after: .resources_after.total_count, deleted: .resources_deleted.total_count}' end_to_end_test_report.json
```

### Performance Analysis
```bash
# View step durations
jq '.steps[] | {step: .step_number, name: .step_name, duration_minutes: (.duration_seconds / 60)}' end_to_end_test_report.json

# Total test duration
jq '.total_duration_seconds / 60' end_to_end_test_report.json
```

## Report Generation

Reports are automatically generated when running the test suite:

```bash
# Run test (generates all reports automatically)
./run_end_to_end_test.sh --real-aws --profile <profile> --email <email>

# Manually regenerate reports from existing JSON
cd end_to_end_test_report
python3 extract_step_logs.py
python3 generate_summary_report.py
```

## Test Modes

### Dry-Run Mode
- Fast execution (~1-2 minutes)
- No AWS operations
- Simulated resource tracking
- Useful for validating test logic

### Real AWS Mode
- Full execution (~60-90 minutes)
- Actual AWS deployments and cleanups
- Real resource tracking
- Incurs AWS costs

## Troubleshooting

### Missing Reports
If reports are not generated:
1. Check that the test completed successfully
2. Verify `end_to_end_test_report.json` exists in the parent directory
3. Run `python3 extract_step_logs.py` manually
4. Check Python dependencies: `pip install -r requirements.txt`

### Incomplete Logs
If step logs are incomplete:
1. Check the JSON report for complete data
2. Re-run `extract_step_logs.py` to regenerate logs
3. Verify disk space is available

### JSON Parsing Errors
If JSON is malformed:
1. Validate JSON: `jq . end_to_end_test_report.json`
2. Check for truncated file (incomplete test run)
3. Re-run the test to generate a new report

## Integration with CI/CD

These reports can be integrated into CI/CD pipelines:

```bash
# Check test status
if jq -e '.failed_steps == 0' end_to_end_test_report/end_to_end_test_report.json; then
    echo "All tests passed"
    exit 0
else
    echo "Tests failed"
    cat end_to_end_test_report/SUMMARY.md
    exit 1
fi
```

## Archiving Reports

To archive reports for historical tracking:

```bash
# Create timestamped archive
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
tar -czf "test_report_${TIMESTAMP}.tar.gz" end_to_end_test_report/

# Or copy to archive directory
mkdir -p test_archives
cp -r end_to_end_test_report "test_archives/report_${TIMESTAMP}"
```

## Contributing

When adding new test steps or modifying the test suite:
1. Ensure step data is captured in the JSON report
2. Update `extract_step_logs.py` if new data fields are added
3. Update `generate_summary_report.py` for new summary sections
4. Update this README with new report sections or analysis commands
