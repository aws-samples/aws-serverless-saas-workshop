# Cloud9 References Audit

This document catalogs all Cloud9 references found in the AWS Serverless SaaS Workshop that need to be removed or updated as part of the modernization effort.

## Summary

Cloud9 is being deprecated and all references need to be removed from the workshop. This includes:
- The Cloud9Setup directory and all its contents
- Documentation references to Cloud9 IDE
- Instructions that assume Cloud9 environment
- File paths that reference Cloud9 environment structure

## Files and Directories to Remove

### 1. Cloud9Setup Directory (Complete Removal)
**Location:** `workshop/Cloud9Setup/`

**Contents to be deleted:**
- `.gitignore`
- `README.md`
- `increase-disk-size.sh` - Script to increase Cloud9 disk size
- `pre-requisites.sh` - Cloud9-specific prerequisite installation
- `pre-requisites-versions-check.sh` - Version checking for Cloud9
- `samconfig.toml` - SAM configuration for Cloud9 setup

**Action:** Delete entire directory

## Documentation Files Requiring Updates

### 2. Workshop Content Documentation
**File:** `.kiro/specs/workshop-modernization/workshop-content.md`

**Cloud9 References Found:**
- Line 101: "Run the command below to clone the workshop repository inside the bash terminal of your Cloud9 IDE."
- Line 109: "Use the script below to increase the disk size of your Cloud9 instance to 50 GB."
- Line 112: References `~/environment/aws-serverless-saas-workshop/Cloud9Setup/`
- Line 119: References `~/environment/aws-serverless-saas-workshop/Cloud9Setup/`
- Line 123: "This script will install/upgrade below inside your Cloud9 IDE:"
- Line 202: "Deploy Lab1 by running the below command inside your Cloud9 bash terminal."
- Line 236: "Open the Cloud9 terminal and enter this following command"
- Line 335: "let's look at how the code is organized in the Cloud9 IDE."
- Line 481: "Copy the SaaS Admin site URL from the Cloud9 bash terminal"
- Line 493: "Copy the Landing site URL from the Cloud9 bash terminal"
- Line 722: "In the Cloud9 bash terminal run the below command"
- Line 739: "Copy the App site URL from the Cloud9 bash terminal"

**Action:** Replace all Cloud9-specific instructions with local development environment instructions

### 3. Baseline Documentation
**File:** `workshop/BASELINE_DOCUMENTATION.md`

**Cloud9 References Found:**
- Line 32: "Cloud9Setup/ # Cloud9 setup scripts (TO BE REMOVED)"
- Line 141-144: Section documenting Cloud9 references that need removal

**Action:** Update to reflect Cloud9 removal completion

### 4. Lab Server README Files

The following lab README files may contain Cloud9 references and need to be reviewed:
- `workshop/Lab1/server/README.md`
- `workshop/Lab2/server/README.md`
- `workshop/Lab3/server/README.md`
- `workshop/Lab4/server/README.md`
- `workshop/Lab5/server/README.md`
- `workshop/Lab6/server/README.md`

**Action:** Review each file and remove/update Cloud9 references

### 5. Event Engine Assets
**File:** `workshop/event-engine-assets/pre-requisites-event-engine.sh`

May contain Cloud9-specific setup instructions.

**Action:** Review and update if Cloud9 references exist

## Replacement Strategy

### Replace Cloud9 Terminal References With:
- "your local terminal"
- "a terminal window"
- "the command line"
- "your development environment terminal"

### Replace Cloud9 IDE References With:
- "your preferred IDE (VS Code, IntelliJ, etc.)"
- "your local development environment"
- "your code editor"

### Replace Cloud9 File Paths With:
- `~/environment/aws-serverless-saas-workshop/` → `<workshop-root>/`
- Cloud9-specific paths → relative paths from workshop root

### Update Prerequisites Section:
Remove Cloud9-specific prerequisites and add:
- Local development environment setup
- AWS CLI installation and configuration
- SAM CLI installation
- Python 3.14 installation
- Node.js installation (for Angular applications)
- Git installation

## Validation

After updates, verify:
1. No files contain "Cloud9", "cloud9", or "C9" references (except in this audit document)
2. Cloud9Setup directory is completely removed
3. All documentation uses generic local development terminology
4. All file paths are relative or use generic placeholders
5. Prerequisites section includes local development setup instructions

## Requirements Validated

This audit addresses:
- **Requirement 3.1:** Remove all Cloud9 setup scripts and configuration files
- **Requirement 3.2:** Remove Cloud9 references from documentation and README files
- **Requirement 3.3:** Update setup instructions to use local development environments

## Next Steps

1. Complete subtask 5.1: Document all locations (✓ COMPLETE - this file)
2. Subtask 5.2-5.8: Update each lab's documentation
3. Subtask 5.9: Write property test to verify Cloud9 removal
