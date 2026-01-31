# End-to-End Test Execution Summary

**Generated:** 2026-01-30 09:50:52

---

## Test Overview

- **Test Name:** End-to-End Cleanup Isolation Test
- **Execution Time:** 2026-01-30T08:22:49.799559
- **Mode:** Real AWS
- **AWS Profile:** serverless-saas-demo
- **Total Duration:** 4h 18m (15477.7 seconds)
- **Total Steps:** 11

## Test Results

### Overall Status: ❌ FAILED

- **Passed Steps:** 8 / 11 (72.7%)
- **Failed Steps:** 3 / 11

```
Test Steps: ✓✓✓✓✓✓✓✗✓✗✗
```

## ❌ Failed Steps

### Step 8: Cleanup Lab6

- **Duration:** 2.5m
- **Error:** None
- **Log File:** `logs/step_08_cleanup_lab6.log`

- **Resources Before:** 67
- **Resources After:** 53
- **Change:** -14

### Step 10: Redeploy All Labs

- **Duration:** 24.3m
- **Error:** None
- **Log File:** `logs/step_10_redeploy_all_labs.log`

- **Resources Before:** 41
- **Resources After:** 184
- **Change:** +143

### Step 11: Cleanup All Labs (Final Verification)

- **Duration:** 12.5m
- **Error:** CRITICAL: 11 resources still exist after final cleanup
- **Log File:** `logs/step_11_cleanup_all_labs_final_verification.log`

- **Resources Before:** 184
- **Resources After:** 11
- **Change:** -173

## ⏱️ Performance Analysis

**Total Execution Time:** 4h 18m

### Slowest Steps

| Step | Name | Duration |
|------|------|----------|
| 6 | Cleanup Lab4 | 1h 9m |
| 7 | Cleanup Lab5 | 46.8m |
| 5 | Cleanup Lab3 | 44.8m |
| 2 | Deploy All Labs | 24.4m |
| 10 | Redeploy All Labs | 24.3m |

## 📊 Resource Tracking

- **Initial Resources:** 0
- **Final Resources:** 11
- **Net Change:** +11

### Resource Changes by Step

| Step | Name | Before | After | Deleted | Change |
|------|------|--------|-------|---------|--------|
| 1 | Cleanup All Labs (Ensure Clean | 0 | 0 | 0 | +0 |
| 2 | Deploy All Labs | 0 | 238 | 238 | +238 |
| 3 | Cleanup Lab1 | 238 | 224 | 0 | -14 |
| 4 | Cleanup Lab2 | 224 | 195 | 0 | -29 |
| 5 | Cleanup Lab3 | 195 | 151 | 0 | -44 |
| 6 | Cleanup Lab4 | 151 | 107 | 0 | -44 |
| 7 | Cleanup Lab5 | 107 | 67 | 0 | -40 |
| 8 | Cleanup Lab6 | 67 | 53 | 0 | -14 |
| 9 | Cleanup Lab7 | 53 | 41 | 0 | -12 |
| 10 | Redeploy All Labs | 41 | 184 | 143 | +143 |
| 11 | Cleanup All Labs (Final Verifi | 184 | 11 | 0 | -173 |

## 📝 Step-by-Step Summary

### ✅ Step 1: Cleanup All Labs (Ensure Clean State)

- **Status:** Passed
- **Duration:** 2.0m
- **Resources:** 0 → 0
  - Stacks: 0 → 0
  - S3 Buckets: 0 → 0
  - Log Groups: 0 → 0
  - Cognito Pools: 0 → 0

### ✅ Step 2: Deploy All Labs

- **Status:** Passed
- **Duration:** 24.4m
- **Resources:** 0 → 238 (deleted: 238)
  - Stacks: 0 → 45
  - S3 Buckets: 0 → 28
  - Log Groups: 0 → 155
  - Cognito Pools: 0 → 10

### ✅ Step 3: Cleanup Lab1

- **Status:** Passed
- **Duration:** 6.2m
- **Resources:** 238 → 224
  - Stacks: 45 → 44
  - S3 Buckets: 28 → 26
  - Log Groups: 155 → 144
  - Cognito Pools: 10 → 10

### ✅ Step 4: Cleanup Lab2

- **Status:** Passed
- **Duration:** 21.0m
- **Resources:** 224 → 195
  - Stacks: 44 → 37
  - S3 Buckets: 26 → 23
  - Log Groups: 144 → 127
  - Cognito Pools: 10 → 8

### ✅ Step 5: Cleanup Lab3

- **Status:** Passed
- **Duration:** 44.8m
- **Resources:** 195 → 151
  - Stacks: 37 → 29
  - S3 Buckets: 23 → 18
  - Log Groups: 127 → 98
  - Cognito Pools: 8 → 6

### ✅ Step 6: Cleanup Lab4

- **Status:** Passed
- **Duration:** 1h 9m
- **Resources:** 151 → 107
  - Stacks: 29 → 21
  - S3 Buckets: 18 → 13
  - Log Groups: 98 → 69
  - Cognito Pools: 6 → 4

### ✅ Step 7: Cleanup Lab5

- **Status:** Passed
- **Duration:** 46.8m
- **Resources:** 107 → 67
  - Stacks: 21 → 12
  - S3 Buckets: 13 → 8
  - Log Groups: 69 → 45
  - Cognito Pools: 4 → 2

### ❌ Step 8: Cleanup Lab6

- **Status:** Failed
- **Duration:** 2.5m
- **Resources:** 67 → 53
  - Stacks: 12 → 11
  - S3 Buckets: 8 → 8
  - Log Groups: 45 → 32
  - Cognito Pools: 2 → 2
- **Warnings:** 1
  - Warning: 41 Lab6 resources still exist after cleanup

### ✅ Step 9: Cleanup Lab7

- **Status:** Passed
- **Duration:** 4.6m
- **Resources:** 53 → 41
  - Stacks: 11 → 9
  - S3 Buckets: 8 → 5
  - Log Groups: 32 → 25
  - Cognito Pools: 2 → 2

### ❌ Step 10: Redeploy All Labs

- **Status:** Failed
- **Duration:** 24.3m
- **Resources:** 41 → 184 (deleted: 143)
  - Stacks: 9 → 35
  - S3 Buckets: 5 → 23
  - Log Groups: 25 → 118
  - Cognito Pools: 2 → 8
- **Warnings:** 1
  - Warning: Labs not deployed: lab5

### ❌ Step 11: Cleanup All Labs (Final Verification)

- **Status:** Failed
- **Duration:** 12.5m
- **Resources:** 184 → 11
  - Stacks: 35 → 9
  - S3 Buckets: 23 → 0
  - Log Groups: 118 → 0
  - Cognito Pools: 8 → 2
- **Warnings:** 2
  - Remaining stacks: serverless-saas-pipeline-lab6, serverless-saas-shared-lab6, serverless-saas-shared-lab6-APIGatewayLambdaPermissions-151VNHMVSUWD, serverless-saas-shared-lab6-APIs-1D660X1O23M5N, serverless-saas-shared-lab6-Cognito-1SLGT6NWZT335, serverless-saas-shared-lab6-CustomResources-1M06GPG5N2WG9, serverless-saas-shared-lab6-DynamoDBTables-1QZJEQV5VTGE9, serverless-saas-shared-lab6-LambdaFunctions-170TNQ3H7UHRG, serverless-saas-shared-lab6-UserInterface-1U9USKEU0252Y
  - Remaining Cognito pools: OperationUsers-ServerlessSaas-lab6-UserPool, PooledTenant-ServerlessSaaS-lab6-UserPool

## 💡 Recommendations

❌ **Some tests failed.** Review the failed steps above.

**Action Items:**
1. Review detailed logs for failed steps
2. Check error messages and resource states
3. Verify AWS permissions and quotas
4. Re-run failed steps individually for debugging
5. Fix identified issues and re-run full test suite

## 🔗 Quick Reference

**View Full Report:**
```bash
cat end_to_end_test_report.json | jq .
```

**View Specific Step:**
```bash
cat logs/step_XX_<step_name>.log
```

**Find Failed Steps:**
```bash
grep -l "Success: False" logs/step_*.log
```

**Re-run Test:**
```bash
./run_end_to_end_test.sh --real-aws --profile serverless-saas-demo
```

---

*This summary was automatically generated from the test execution data.*
