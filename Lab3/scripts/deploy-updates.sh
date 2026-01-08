#!/bin/bash
cd ../server || exit # stop execution if cd fails
rm -rf .aws-sam/

# Use virtual environment Python if available
if [ -f "../../.venv_py313/bin/python" ]; then
  PYTHON_CMD="../../.venv_py313/bin/python"
else
  PYTHON_CMD="python3"
fi

$PYTHON_CMD -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
#Deploying shared services changes
echo "Deploying shared services changes"  
echo Y | sam sync --stack-name serverless-saas-workshop-shared-lab3 -t shared-template.yaml --code --resource-id LambdaFunctions/ServerlessSaaSLayers --resource-id LambdaFunctions/SharedServicesAuthorizerFunction

#Deploying tenant services changes
echo "Deploying tenant services changes"
rm -rf .aws-sam/
echo Y | sam sync --stack-name serverless-saas-workshop-tenant-lab3 -t tenant-template.yaml --code --resource-id ServerlessSaaSLayers --resource-id BusinessServicesAuthorizerFunction --resource-id CreateProductFunction

cd ../scripts || exit
./geturl.sh