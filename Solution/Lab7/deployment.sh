REGION=$(aws configure get region)
sam build -t template.yaml --use-container
sam deploy --config-file samconfig.toml --region=$REGION
  

CUR_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='CURBucketname'].Value" --output text)
AWSCURInitializerFunctionName=$(aws cloudformation list-exports --query "Exports[?Name=='AWSCURInitializerFunctionName'].Value" --output text)

aws s3 cp SampleCUR/ s3://$CUR_BUCKET/curoutput/year=2022/month=10/ --recursive

aws lambda invoke --function-name $AWSCURInitializerFunctionName lambdaoutput.json