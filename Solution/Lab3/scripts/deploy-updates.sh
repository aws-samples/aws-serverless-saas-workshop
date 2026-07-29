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
echo Y | sam sync --stack-name serverless-saas -t template.yaml --code --resource-id LambdaFunctions/ServerlessSaaSLayers --resource-id LambdaFunctions/SharedServicesAuthorizerFunction -u

#Deploying tenant services changes
echo "Deploying tenant services changes"
rm -rf .aws-sam/
echo Y | sam sync --stack-name stack-pooled -t tenant-template.yaml --code --resource-id ServerlessSaaSLayers --resource-id BusinessServicesAuthorizerFunction --resource-id CreateProductFunction -u

cd ../scripts || exit

#sam sync --code publishes new layer versions without rewiring the functions that use them
../../../scripts/update_lambda_layer.sh serverless-saas serverless-saas-dependencies
if [[ $? -ne 0 ]]; then
  echo "****ERROR: Failed to update Lambda layer version!!****"
  exit 1
fi
../../../scripts/update_lambda_layer.sh stack-pooled serverless-saas-dependencies-pooled
if [[ $? -ne 0 ]]; then
  echo "****ERROR: Failed to update pooled Lambda layer version!!****"
  exit 1
fi

./geturl.sh