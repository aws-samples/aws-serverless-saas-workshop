#!/bin/bash
##
## This script aims to automatically deploy the labs
## using the completed labs found in the Solutions folder.
##

echo "################ Running pre-req script... ################"
cd ../Cloud9Setup/
./increase-disk-size.sh
# ./pre-requisites.sh
cd ../scripts/
echo "################ Done running pre-req script... ################"

# echo "################ Running labs... ################"

# #### Note that deploying lab1 is not a requirement ####
# # echo "################ Running lab1... ################"
# # cd ../Solution/Lab1/scripts
# # ./deployment.sh -s -c --stack-name serverless-saas-workshop-lab1
# # cd ../../../scripts/
# # echo "################ Done running lab1. ################"
# #######################################################

echo "################ Running lab2... ################"

cd ../Solution/Lab2/scripts
./deployment.sh -s -c --email syeduh+serverlesslab@amazon.com
./deployment.sh -s
cd ../../../scripts/

echo "################ Done running lab2. ################"

echo "################ Sleeping for a minute before moving to next lab... ################"
sleep 60

echo "################ Running lab3... ################"

cd ../Solution/Lab3/scripts
./deployment.sh -s -c
./deployment.sh -s
cd ../../../scripts/

echo "################ Done running lab3. ################"

echo "################ Sleeping for a minute before moving to next lab... ################"
sleep 60

echo "################ Running lab4... ################"

cd ../Solution/Lab4/scripts
./deployment.sh -s
cd ../../../scripts/

echo "################ Done running lab4. ################"

echo "################ Sleeping for a minute before moving to next lab... ################"
sleep 60

echo "################ Running lab5... ################"

cd ../Solution/Lab5/scripts/
./deployment.sh -s -c
./deployment.sh -s
cd ../../../scripts/

echo "################ Done running lab5. ################"

echo "################ Sleeping for a minute before moving to next lab... ################"
sleep 60

echo "################ Running lab6... ################"

cd ../Solution/Lab6/scripts/
./deployment.sh
cd ../../../scripts/

echo "################ Done running lab6. ################"
