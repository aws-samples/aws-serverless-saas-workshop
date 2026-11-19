# AWS Serverless SaaS Workshop - Event Engine Assets

This directory contains assets used for deploying the AWS Serverless SaaS Workshop in Event Engine environments.

## Templates

### VSCode Server Template (vscode-module-sam-template.yaml)

This template replaces the original Cloud9-based development environment with a VSCode Server environment. Cloud9 is being deprecated, and VSCode Server provides a modern, feature-rich alternative.

#### Key Features

- **VSCode Server**: Deploys a VSCode Server instance on an EC2 instance
- **CloudFront Distribution**: Provides secure access to the VSCode Server
- **Pre-installed Tools**: Includes all necessary tools for the workshop (AWS CLI, SAM CLI, Node.js, Python, etc.)
- **Workshop Repository**: Automatically clones the workshop repository
- **Security**: Uses a generated password stored in AWS Secrets Manager

#### Deployment

To deploy the VSCode Server environment:

```bash
# Option 1: Using command line parameters
sam build -t event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --stack-name serverless-saas-vscode-env --capabilities CAPABILITY_NAMED_IAM

# Option 2: Using the provided samconfig.toml file
sam build -t event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --config-file samconfig.toml
```

After deployment, you'll receive:
- A URL to access the VSCode Server
- A password to log in

### Legacy Cloud9 Template (initialize-module-sam-template.yaml)

This is the original template that deploys a Cloud9 IDE environment. It's kept for backward compatibility but is not recommended for new deployments as Cloud9 is being deprecated.

## Migration from Cloud9 to VSCode Server

If you have existing workshops using Cloud9, you can update them to use VSCode Server by:

1. Using the `vscode-module-sam-template.yaml` template instead of the Cloud9 template
2. Updating any documentation to reference VSCode Server instead of Cloud9
3. Ensuring any workshop-specific tools or configurations are included in the VSCode Server setup

## Pre-requisites Scripts

- `pre-requisites-event-engine.sh`: Script to install required tools and dependencies in the development environment
