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

# Uninstall aws cli v1 and Install aws cli version-2.3.0
sudo pip2 uninstall awscli -y

echo "Installing aws cli version-2.3.0"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.3.0.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws 

# Install sam cli version 1.33.0
echo "Installing sam cli version 1.33.0"
wget https://github.com/aws/aws-sam-cli/releases/download/v1.33.0/aws-sam-cli-linux-x86_64.zip
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install
if [ $? -ne 0 ]; then
	echo "Sam cli is already present, so deleting existing version"
	sudo rm /usr/local/bin/sam
	sudo rm -rf /usr/local/aws-sam-cli
	echp "Now installing sam cli version 1.33.0"
	sudo ./sam-installation/install    
fi
rm aws-sam-cli-linux-x86_64.zip
rm -rf sam-installation

# Install git-remote-codecommit version 1.15.1
echo "Installing git-remote-codecommit version 1.15.1"
curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
rm get-pip.py

pip install git-remote-codecommit==1.15.1

# Install node v14.18.1
echo "Installing node v14.18.1"
nvm deactivate
nvm uninstall node
nvm install v14.18.1
nvm use v14.18.1
nvm alias default v14.18.1


# Install cdk cli version 1.129.0
echo "Installing cdk cli version 1.129.0"
sudo npm uninstall -g aws-cdk
sudo npm install -g aws-cdk@1.129.0

# Install angular version 12.1.1
echo "Installing angular version 12.1.1"
sudo npm install -g @angular/cli@12.1.1

#Install jq version 1.5
sudo yum -y install jq-1.5

#Install pylint version 2.11.1
python3 -m pip install pylint==2.11.1
