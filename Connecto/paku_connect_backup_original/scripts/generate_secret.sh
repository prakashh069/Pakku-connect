#!/usr/bin/env bash
set -euo pipefail
SECRET=$(openssl rand -base64 32 | tr -d '\n')
P12_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)
cat > .env <<EOF
PAKKU_SECRET=$SECRET
P12_PASSWORD=$P12_PASS
PAKKU_WS_PORT=8080
EOF
echo "Secrets written to .env — never commit"
