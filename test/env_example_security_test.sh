#!/usr/bin/env bash
# Test that .env.example does not contain real secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env.example"

if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: $ENV_FILE not found (run from project root or test/ directory)"
  exit 1
fi

echo "Testing $ENV_FILE for real secrets..."

# Test: File should not contain the known real RSA private key (even if commented)
if grep -Fq 'LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb2dJQkFBS0NBUUVB' "$ENV_FILE"; then
  echo "FAIL: $ENV_FILE contains real RSA private key"
  exit 1
fi

# Test: File should not contain the known real worker secret (even if commented)
if grep -Fq 'dECXNlqctXJ/a+1FI4AaeLZY4Rp+Pxo23WwmJxC2xew=' "$ENV_FILE"; then
  echo "FAIL: $ENV_FILE contains real worker secret"
  exit 1
fi

# Test: Should reference the generation command
if ! grep -Fq 'mix lightning.gen_worker_keys' "$ENV_FILE"; then
  echo "FAIL: $ENV_FILE should reference 'mix lightning.gen_worker_keys'"
  exit 1
fi

echo "PASS: No real secrets found in $ENV_FILE"
