# Node.js LTS Setup Guide

## Why Use Node.js LTS?

The AWS Serverless SaaS Workshop requires Node.js LTS (Long Term Support) versions for client application deployment. LTS versions are:
- Even-numbered major versions (v20.x, v22.x, etc.)
- Stable and recommended for production use
- Fully compatible with Angular CLI and other build tools

Odd-numbered versions (v19.x, v21.x, v25.x) are not LTS and may have compatibility issues.

## Current Recommended Versions

- **Node.js v20.x** (LTS - Recommended)
- **Node.js v22.x** (LTS - Latest)

## Installation Options

### Option 1: Using Node Version Manager (nvm) - Recommended

NVM allows you to install and switch between multiple Node.js versions easily.

#### Install nvm (macOS/Linux)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

Restart your terminal or run:

```bash
source ~/.bashrc  # or ~/.zshrc for zsh
```

#### Install Node.js LTS

```bash
# Install latest LTS version
nvm install --lts

# Or install specific LTS version
nvm install 20
nvm install 22

# Use the LTS version
nvm use --lts

# Set default version
nvm alias default 20
```

#### Switch Between Versions

```bash
# List installed versions
nvm list

# Switch to specific version
nvm use 20
nvm use 22

# Check current version
node --version
```

### Option 2: Direct Installation

#### macOS

Using Homebrew:

```bash
# Install Node.js 20 (LTS)
brew install node@20

# Link it
brew link node@20

# Verify installation
node --version
```

#### Windows

1. Download Node.js LTS installer from: https://nodejs.org/
2. Run the installer
3. Verify installation:

```cmd
node --version
```

#### Linux (Ubuntu/Debian)

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
```

## Verifying Your Installation

After installation, verify you have an LTS version:

```bash
node --version
```

You should see an even-numbered major version like:
- `v20.11.0` ✅
- `v22.0.0` ✅

NOT odd-numbered versions like:
- `v19.x.x` ❌
- `v21.x.x` ❌
- `v25.x.x` ❌

## Workshop Deployment

Once you have Node.js LTS installed, you can deploy the workshop labs:

```bash
cd workshop/Lab1/scripts
./deployment.sh -s -c --region us-west-2
```

The deployment script will:
1. Check your Node.js version
2. Warn you if you're not using an LTS version
3. Allow you to continue or cancel the deployment

## Troubleshooting

### "node: command not found"

Make sure Node.js is in your PATH. If using nvm:

```bash
nvm use --lts
```

### Angular build fails with "Cannot find module"

This usually indicates a non-LTS Node.js version. Switch to LTS:

```bash
nvm use 20
```

### Multiple Node.js versions installed

Use nvm to manage versions:

```bash
# List all installed versions
nvm list

# Set default to LTS
nvm alias default 20

# Use LTS for current session
nvm use 20
```

## Additional Resources

- Node.js Official Website: https://nodejs.org/
- Node.js Release Schedule: https://nodejs.org/en/about/releases/
- NVM GitHub: https://github.com/nvm-sh/nvm
- Angular CLI Requirements: https://angular.io/guide/setup-local
