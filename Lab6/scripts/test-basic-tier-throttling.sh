#!/bin/bash
APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name stack-pooled --query "Stacks[0].Outputs[?OutputKey=='TenantAPI'].OutputValue" --output text)

get_product() {
   
  STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X GET -H "Authorization: Bearer $1" -H "Content-Type: application/json" $APP_APIGATEWAYURL/products)
  
  echo "STATUS_CODE : $STATUS_CODE";
  
}

for i in $(seq 1 1000)
do
  get_product $1 $i &
done
wait
echo "All done"