#!/bin/bash -x
. /home/ec2-user/.nvm/nvm.sh

#Install python3.8
echo "Installing python3.8"
wget https://www.python.org/ftp/python/3.8.11/Python-3.8.11.tgz
tar xzvf Python-3.8.11.tgz
cd Python-3.8.11
./configure --with-ssl
make
sudo make install
cd ..
sudo rm -rf Python-3.8.11
rm Python-3.8.11.tgz
sudo alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.8
sudo alternatives --set python3 /usr/local/bin/python3.8

# Uninstall aws cli v1 and Install latest aws cli version2
sudo pip2 uninstall awscli -y

echo "Installing latest aws cli version2"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws 

# Install latest sam cli
echo "Installing latest sam cli"
wget https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install
if [ $? -ne 0 ]; then
	echo "Sam cli is already present, so upgrading to latest version"
	sudo ./sam-installation/install --update    
fi
rm aws-sam-cli-linux-x86_64.zip
rm -rf sam-installation

# Install git-remote-codecommit 
echo "Installing git-remote-codecommit"
curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
rm get-pip.py

pip install git-remote-codecommit

# Install latest node
echo "Installing latest node"
nvm deactivate
nvm uninstall node
nvm install --lts
nvm use node
nvm alias default node


# Install latest cdk cli
echo "Installing latest cdk cli"
sudo npm uninstall -g aws-cdk
sudo npm install -g aws-cdk

# Install latest angular 
echo "Installing latest angular"
sudo npm install -g @angular/cli@12.1.1

#Install jq
sudo yum -y install jq  