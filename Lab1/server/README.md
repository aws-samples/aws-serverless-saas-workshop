## Deployment Instructions

### Standard Deployment
```
sam build -t template.yaml
sam deploy --config-file samconfig.toml --profile serverless-saas-demo
```

### Event Engine Deployment
If using AWS Event Engine with a pre-configured S3 bucket:
```
sam build && sam package \
  --output-template-file packaged.yaml \
  --s3-bucket aws-sam-cli-managed-default-samclisourcebucket-8tf6bmi4rdcx \
  --region us-west-2 \
  --profile serverless-saas-demo

sam deploy \
  --template-file packaged.yaml \
  --config-file samconfig.toml \
  --profile serverless-saas-demo
```

