#!/bin/bash
APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name stack-pooled --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" --output text)

get_product() {
  curl -X GET -H "Authorization: Bearer $1" -H "Content-Type: application/json" $APP_APIGATEWAYURL/products
  echo "\n $2"
}

for i in $(seq 1 550)
do
  get_product $1 $i &
done
wait
echo "All done"