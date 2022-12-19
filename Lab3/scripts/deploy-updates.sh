#!/bin/bash
cd ../server || exit # stop execution if cd fails
rm -rf .aws-sam/
python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi
#Deploying shared services changes
echo "Deploying shared services changes"  
echo Y | sam sync --stack-name serverless-saas -t shared-template.yaml --code --resource-id LambdaFunctions/ServerlessSaaSLayers --resource-id LambdaFunctions/SharedServicesAuthorizerFunction -u

#Deploying tenant services changes
echo "Deploying tenant services changes"
rm -rf .aws-sam/
echo Y | sam sync --stack-name stack-pooled -t tenant-template.yaml --code --resource-id ServerlessSaaSLayers --resource-id BusinessServicesAuthorizerFunction --resource-id CreateProductFunction -u

cd ../scripts || exit
./geturl.sh