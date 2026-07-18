#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$REPO_ROOT/static"

mkdir -p "$STATIC_DIR"

zip_dir() {
  local src_dir="$1"
  local dest_zip="$2"
  rm -f "$dest_zip"
  if command -v zip &>/dev/null; then
    (cd "$src_dir" && zip -qr "$dest_zip" .)
  else
    python3 -c "
import zipfile, os, sys
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(src):
        for f in files:
            abs_p = os.path.join(root, f)
            zf.write(abs_p, os.path.relpath(abs_p, src).replace(chr(92), '/'))
" "$src_dir" "$dest_zip"
  fi
}

echo "Building prebuilt UI zips..."
echo "Output dir: $STATIC_DIR"

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
zip_dir dist "$STATIC_DIR/lab1-application.zip"
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
zip_dir dist "$STATIC_DIR/lab2-admin.zip"
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
zip_dir dist "$STATIC_DIR/lab2-landing.zip"
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
zip_dir dist "$STATIC_DIR/lab3-application.zip"
echo "Created lab3-application.zip"

echo ""
echo "Done! All prebuilt UI zips saved to $STATIC_DIR"
ls -lh "$STATIC_DIR"/*.zip
