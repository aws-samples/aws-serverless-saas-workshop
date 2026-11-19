# Setup VSCode Server Development Environment

This directory contains scripts and instructions for setting up a VSCode Server development environment for the AWS Serverless SaaS Workshop.

## Deployment Options

### Option 1: Using command line parameters
```bash
sam build -t ../event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --stack-name serverless-saas-vscode-env --capabilities CAPABILITY_NAMED_IAM
```

### Option 2: Using the provided samconfig.toml file
```bash
# Using the samconfig.toml in the event-engine-assets directory
sam build -t ../event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --config-file ../event-engine-assets/samconfig.toml

# Or using the samconfig.toml in this directory
sam build -t ../event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --config-file samconfig.toml
```

After deployment completes, you can access the VSCode Server environment using the URL and password provided in the CloudFormation outputs. The URL will open VSCode Server at the /Workshop directory, where the aws-serverless-saas-workshop repository has been cloned.

## Scripts

### pre-requisites.sh
This script installs all the necessary tools and dependencies for the workshop, including:
- Python 3.8+
- AWS CLI
- SAM CLI
- Node.js
- CDK CLI
- git-remote-codecommit
- VSCode Server specific requirements (nginx, code-server)

### pre-requisites-versions-check.sh
This script checks if all the required tools and dependencies are installed with the correct versions. It also verifies that the VSCode Server instance is properly configured.

### increase-disk-size.sh
This script increases the EBS volume size of the VSCode Server instance to 50 GiB.

## Usage

1. Deploy the VSCode Server environment using one of the deployment options above.
2. Connect to the VSCode Server environment using the URL and password provided in the CloudFormation outputs.
3. Run the pre-requisites-versions-check.sh script to verify that all required tools are installed:
   ```bash
   cd VSCodeSetup
   chmod +x pre-requisites-versions-check.sh
   ./pre-requisites-versions-check.sh
   ```
4. If any tools are missing or have incorrect versions, run the pre-requisites.sh script:
   ```bash
   chmod +x pre-requisites.sh
   ./pre-requisites.sh
   ```
5. If you need to increase the disk size, run the increase-disk-size.sh script:
   ```bash
   chmod +x increase-disk-size.sh
   ./increase-disk-size.sh
   ```

## Differences from Cloud9

VSCode Server provides several advantages over Cloud9:
- Modern, feature-rich IDE experience
- Better performance and stability
- Continued support (Cloud9 is being deprecated)
- More customization options
- Better extension support
