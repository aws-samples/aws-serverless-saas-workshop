sam build -t shared-template.yaml --use-container
sam deploy --config-file shared-samconfig.toml


sam build -t tenant-template.yaml --use-container
sam deploy --config-file tenant-samconfig.toml

