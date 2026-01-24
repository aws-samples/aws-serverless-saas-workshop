# AWS Serverless SaaS Workshop - Prerequisites

This document outlines all the prerequisites needed to successfully complete the AWS Serverless SaaS Workshop.

## Required Software

### 1. AWS CLI (v2 or later)

The AWS Command Line Interface is required for deploying and managing AWS resources.

**Installation:**
- macOS: `brew install awscli`
- Windows: Download from https://aws.amazon.com/cli/
- Linux: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

**Verify installation:**
```bash
aws --version
```

### 2. AWS SAM CLI (v1.70.0 or later)

AWS Serverless Application Model CLI is used to build and deploy serverless applications.

**Installation:**
- macOS: `brew install aws-sam-cli`
- Windows/Linux: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html

**Verify installation:**
```bash
sam --version
```

### 3. Python 3.14

Python 3.14 is required for Lambda functions and deployment scripts.

**Installation:**
- macOS: `brew install python@3.14`
- Windows: Download from https://www.python.org/downloads/
- Linux: Use your package manager or build from source

**Verify installation:**
```bash
python3 --version
```

### 4. Node.js LTS (v20.x or v22.x) - REQUIRED

**IMPORTANT:** Node.js LTS (Long Term Support) version is required for building Angular client applications.

**Recommended versions:**
- Node.js v20.x (Active LTS)
- Node.js v22.x (Active LTS)

**NOT recommended:**
- Odd-numbered versions (v19, v21, v23, v25) - These are not LTS and may have compatibility issues

**Installation:**

**Option A: Using Homebrew (macOS)**
```bash
# Install Node.js v22 LTS
brew install node@22

# Add to PATH
echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Option B: Using nvm (Recommended for managing multiple versions)**
```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Install Node.js LTS
nvm install 22
nvm use 22
nvm alias default 22
```

**Option C: Direct download**
- Download from: https://nodejs.org/ (choose LTS version)

**Verify installation:**
```bash
node --version  # Should show v20.x.x or v22.x.x
npm --version
```

**Troubleshooting:** If you see an odd-numbered version (v25, v23, etc.), please install an LTS version. See [NODEJS_LTS_SETUP.md](NODEJS_LTS_SETUP.md) for detailed instructions.

### 5. AWS CDK CLI (for Lab 5 and Lab 6)

AWS Cloud Development Kit is used for infrastructure as code in later labs.

**Installation:**
```bash
npm install -g aws-cdk
```

**Verify installation:**
```bash
cdk --version
```

### 6. Git

Git is required for version control and CodeCommit operations.

**Installation:**
- macOS: `brew install git` (or use Xcode Command Line Tools)
- Windows: Download from https://git-scm.com/
- Linux: Use your package manager (e.g., `apt install git`)

**Verify installation:**
```bash
git --version
```

## AWS Account Requirements

### 1. AWS Account

You need an AWS account with appropriate permissions to create and manage:
- Lambda functions
- API Gateway
- DynamoDB tables
- Cognito User Pools
- S3 buckets
- CloudFormation stacks
- CodePipeline
- CodeCommit repositories
- CloudWatch logs and metrics
- IAM roles and policies

### 2. AWS Profile Configuration

Configure your AWS credentials with a profile named `serverless-saas-demo`:

```bash
aws configure --profile serverless-saas-demo
```

You'll be prompted for:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-west-2`)
- Default output format (e.g., `json`)

**Verify configuration:**
```bash
aws sts get-caller-identity --profile serverless-saas-demo
```

### 3. AWS Region

The workshop is designed to work in any AWS region, but we recommend using:
- `us-west-2` (Oregon)
- `us-east-1` (N. Virginia)

Make sure all required services are available in your chosen region.

## System Requirements

### Operating System
- macOS (10.15 or later)
- Linux (Ubuntu 20.04 or later, Amazon Linux 2)
- Windows 10/11 (with WSL2 recommended)

### Disk Space
- At least 5 GB of free disk space for dependencies and build artifacts

### Memory
- At least 8 GB RAM recommended

### Internet Connection
- Stable internet connection for downloading dependencies and deploying to AWS

## Optional Tools

### 1. Docker or Finch (for containerized builds)

While not required, Docker or Finch can be used for containerized SAM builds.

**Note:** The deployment scripts have been updated to work without containers.

### 2. IDE/Text Editor

Any text editor or IDE works, but we recommend:
- Visual Studio Code
- IntelliJ IDEA
- PyCharm
- Sublime Text

## Verification Script

Run this script to verify all prerequisites are installed:

```bash
#!/bin/bash

echo "Checking prerequisites..."
echo ""

# Check AWS CLI
if command -v aws &> /dev/null; then
    echo "✓ AWS CLI: $(aws --version)"
else
    echo "✗ AWS CLI: Not installed"
fi

# Check SAM CLI
if command -v sam &> /dev/null; then
    echo "✓ SAM CLI: $(sam --version)"
else
    echo "✗ SAM CLI: Not installed"
fi

# Check Python
if command -v python3 &> /dev/null; then
    echo "✓ Python: $(python3 --version)"
else
    echo "✗ Python: Not installed"
fi

# Check Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
    if [ $((NODE_MAJOR % 2)) -eq 0 ]; then
        echo "✓ Node.js: $NODE_VERSION (LTS)"
    else
        echo "⚠ Node.js: $NODE_VERSION (NOT LTS - please install v20 or v22)"
    fi
else
    echo "✗ Node.js: Not installed"
fi

# Check CDK
if command -v cdk &> /dev/null; then
    echo "✓ CDK CLI: $(cdk --version)"
else
    echo "⚠ CDK CLI: Not installed (required for Lab 5 and Lab 6)"
fi

# Check Git
if command -v git &> /dev/null; then
    echo "✓ Git: $(git --version)"
else
    echo "✗ Git: Not installed"
fi

# Check AWS credentials
if aws sts get-caller-identity --profile serverless-saas-demo &> /dev/null; then
    echo "✓ AWS Profile 'serverless-saas-demo': Configured"
else
    echo "✗ AWS Profile 'serverless-saas-demo': Not configured"
fi

echo ""
echo "Prerequisite check complete!"
```

Save this as `check-prerequisites.sh`, make it executable (`chmod +x check-prerequisites.sh`), and run it.

## Next Steps

Once all prerequisites are installed and verified:

1. Review the [Node.js LTS Setup Guide](NODEJS_LTS_SETUP.md) if you need help with Node.js
2. Start with Lab 1: [workshop/Lab1/README.md](Lab1/README.md)
3. Follow the workshop guide: https://catalog.us-east-1.prod.workshops.aws/workshops/b0c6ad36-0a4b-45d8-856b-8a64f0ac76bb/en-US

## Troubleshooting

### Node.js Version Issues

If you encounter errors like "Cannot find module './bootstrap'" or "Access Denied" on CloudFront URLs, you're likely using a non-LTS Node.js version. See [NODEJS_LTS_SETUP.md](NODEJS_LTS_SETUP.md) for solutions.

### AWS Credentials

If you get "Unable to locate credentials" errors, ensure your AWS profile is configured correctly:

```bash
aws configure --profile serverless-saas-demo
aws sts get-caller-identity --profile serverless-saas-demo
```

### SAM Build Failures

If SAM builds fail, ensure you have Python 3.14 installed and accessible in your PATH.

## Support

For issues or questions:
- Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
- Review the workshop documentation
- Open an issue in the GitHub repository
