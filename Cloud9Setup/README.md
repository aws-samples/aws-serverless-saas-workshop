# Setup Development Environment

## Option 1: VSCode Server (Recommended)
The Cloud9 service is being deprecated. We recommend using VSCode Server instead.

```bash
# Option 1: Using command line parameters
sam build -t ../event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --stack-name serverless-saas-vscode-env --capabilities CAPABILITY_NAMED_IAM

# Option 2: Using the provided samconfig.toml file
sam build -t ../event-engine-assets/vscode-module-sam-template.yaml --use-container
sam deploy --config-file ../event-engine-assets/samconfig.toml
```

After deployment completes, you can access the VSCode Server environment using the URL and password provided in the CloudFormation outputs.

## Option 2: Cloud9 (Legacy)
If you still need to use Cloud9 (not recommended for new deployments):

```bash
sam build -t prereq-sam-template.yaml --use-container
sam deploy
```
