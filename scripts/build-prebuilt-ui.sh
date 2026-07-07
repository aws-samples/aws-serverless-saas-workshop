#!/bin/bash
set -e

PREBUILT_BUCKET="serverless-saas-workshop-prebuilt-ui"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TMPDIR=$(mktemp -d)

echo "Building prebuilt UI zips..."
echo "Temp dir: $TMPDIR"

# --- Lab1 Application ---
echo ""
echo "=== Building Lab1 Application ==="
cd "$REPO_ROOT/Lab1/client/Application"

cat > ./src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  apiGatewayUrl: '__APP_API_GATEWAY_URL__'
};
EOF
cp ./src/environments/environment.prod.ts ./src/environments/environment.ts

npm install --loglevel=error && npm run build
cd dist && zip -qr "$TMPDIR/lab1-application.zip" . && cd ..
echo "Created lab1-application.zip"

# --- Lab2 Admin ---
echo ""
echo "=== Building Lab2 Admin ==="
cd "$REPO_ROOT/Lab2/client/Admin"

cat > ./src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  apiUrl: '__ADMIN_API_GATEWAY_URL__',
};
EOF
cat > ./src/environments/environment.ts << 'EOF'
export const environment = {
  production: false,
  apiUrl: '__ADMIN_API_GATEWAY_URL__',
};
EOF
cat > ./src/aws-exports.ts << 'EOF'
const awsmobile = {
    "aws_project_region": "__AWS_REGION__",
    "aws_cognito_region": "__AWS_REGION__",
    "aws_user_pools_id": "__ADMIN_USERPOOL_ID__",
    "aws_user_pools_web_client_id": "__ADMIN_APPCLIENTID__",
};

export default awsmobile;
EOF

npm install --loglevel=error && npm run build
cd dist && zip -qr "$TMPDIR/lab2-admin.zip" . && cd ..
echo "Created lab2-admin.zip"

# --- Lab2 Landing ---
echo ""
echo "=== Building Lab2 Landing ==="
cd "$REPO_ROOT/Lab2/client/Landing"

cat > ./src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  apiGatewayUrl: '__ADMIN_API_GATEWAY_URL__'
};
EOF
cat > ./src/environments/environment.ts << 'EOF'
export const environment = {
  production: false,
  apiGatewayUrl: '__ADMIN_API_GATEWAY_URL__'
};
EOF

npm install --loglevel=error && npm run build
cd dist && zip -qr "$TMPDIR/lab2-landing.zip" . && cd ..
echo "Created lab2-landing.zip"

# --- Lab3 Application (also used by Lab4, Lab5) ---
echo ""
echo "=== Building Lab3 Application ==="
cd "$REPO_ROOT/Lab3/client/Application"

cat > ./src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  regApiGatewayUrl: '__ADMIN_API_GATEWAY_URL__',
  apiGatewayUrl: '__APP_API_GATEWAY_URL__',
  userPoolId: '__APP_USERPOOL_ID__',
  appClientId: '__APP_APPCLIENTID__',
};
EOF
cat > ./src/environments/environment.ts << 'EOF'
export const environment = {
  production: true,
  regApiGatewayUrl: '__ADMIN_API_GATEWAY_URL__',
  apiGatewayUrl: '__APP_API_GATEWAY_URL__',
  userPoolId: '__APP_USERPOOL_ID__',
  appClientId: '__APP_APPCLIENTID__',
};
EOF

npm install --legacy-peer-deps --loglevel=error && npm run build
cd dist && zip -qr "$TMPDIR/lab3-application.zip" . && cd ..
echo "Created lab3-application.zip"

# --- Upload to S3 ---
echo ""
echo "=== Uploading to s3://$PREBUILT_BUCKET ==="
aws s3 cp "$TMPDIR/lab1-application.zip" "s3://$PREBUILT_BUCKET/lab1-application.zip"
aws s3 cp "$TMPDIR/lab2-admin.zip" "s3://$PREBUILT_BUCKET/lab2-admin.zip"
aws s3 cp "$TMPDIR/lab2-landing.zip" "s3://$PREBUILT_BUCKET/lab2-landing.zip"
aws s3 cp "$TMPDIR/lab3-application.zip" "s3://$PREBUILT_BUCKET/lab3-application.zip"

rm -rf "$TMPDIR"
echo ""
echo "Done! All prebuilt UI zips uploaded to s3://$PREBUILT_BUCKET"
