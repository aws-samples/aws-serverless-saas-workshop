#!/bin/bash -x

# Define the VSCode Server user
VSCODE_USER="participant"

# Installing NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | sudo -u $VSCODE_USER bash

. /home/$VSCODE_USER/.nvm/nvm.sh

# Install python3.8 or higher
if [ -f /etc/os-release ] && grep -q "VERSION_ID=\"2\"" /etc/os-release; then
    # Amazon Linux 2
    sudo yum install -y amazon-linux-extras
    sudo amazon-linux-extras enable python3.8
    sudo yum install -y python3.8
    sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1
    sudo alternatives --set python3 /usr/bin/python3.8
else
    # Amazon Linux 2023 or other distributions
    sudo dnf install -y python3.11 python3.11-pip python3-virtualenv python3-pytest
    sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
    sudo alternatives --set python3 /usr/bin/python3.11
fi

# Uninstall aws cli v1 and Install aws cli version-2.3.0
sudo pip uninstall awscli -y 2>/dev/null || true

echo "Installing aws cli version-2.3.0"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.3.0.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws 

# Install sam cli version 1.64.0
echo "Installing sam cli version 1.64.0"
wget https://github.com/aws/aws-sam-cli/releases/download/v1.64.0/aws-sam-cli-linux-x86_64.zip
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install
if [ $? -ne 0 ]; then
    echo "Sam cli is already present, so deleting existing version"
    sudo rm /usr/local/bin/sam
    sudo rm -rf /usr/local/aws-sam-cli
    echo "Now installing sam cli version 1.64.0"
    sudo ./sam-installation/install    
fi
rm aws-sam-cli-linux-x86_64.zip
rm -rf sam-installation

# Install git-remote-codecommit version 1.15.1
echo "Installing git-remote-codecommit version 1.15.1"
curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
rm get-pip.py

python3 -m pip install git-remote-codecommit==1.15.1

# Install node v14.18.1
echo "Installing node v14.18.1"
sudo -u $VSCODE_USER bash -c "source /home/$VSCODE_USER/.nvm/nvm.sh && nvm deactivate && nvm uninstall node && nvm install v14.18.1 && nvm use v14.18.1 && nvm alias default v14.18.1"

# Install cdk cli version ^2.40.0
echo "Installing cdk cli version ^2.40.0"
npm uninstall -g aws-cdk
npm install -g aws-cdk@"^2.40.0"

# Install jq
if [ -f /etc/os-release ] && grep -q "VERSION_ID=\"2\"" /etc/os-release; then
    # Amazon Linux 2
    sudo yum -y install jq-1.5
else
    # Amazon Linux 2023 or other distributions
    sudo dnf -y install jq
fi

# Install pylint version 2.11.1
python3 -m pip install pylint==2.11.1

# Install boto3
python3 -m pip install boto3

# Install VSCode Server specific requirements
# Install nginx if not already installed
if ! command -v nginx &> /dev/null; then
    if [ -f /etc/os-release ] && grep -q "VERSION_ID=\"2\"" /etc/os-release; then
        # Amazon Linux 2
        sudo amazon-linux-extras install -y nginx1
    else
        # Amazon Linux 2023 or other distributions
        sudo dnf install -y nginx
    fi
fi

# Install code-server if not already installed
if ! command -v code-server &> /dev/null; then
    curl -fsSL https://code-server.dev/install.sh | sh
    sudo systemctl enable --now code-server@$VSCODE_USER
fi

# Set proper permissions for the VSCode user
sudo chown -R $VSCODE_USER:$VSCODE_USER /home/$VSCODE_USER
