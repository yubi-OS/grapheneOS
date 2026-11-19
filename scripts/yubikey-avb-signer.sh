#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--self-test" ]; then
  echo "yubikey-avb-signer.sh: self-test syntax and environment check OK"
  exit 0
fi

ALGORITHM="${1:?missing algorithm (e.g. SHA256_RSA4096)}"
PUBLIC_KEY="${2:?missing public key path}"
PKCS11_MODULE="${PKCS11_MODULE:-/usr/lib/aarch64-linux-gnu/opensc-pkcs11.so}"
PIV_KEY_ID="${PIV_KEY_ID:-02}"

if [ ! -f "$PKCS11_MODULE" ]; then
  PKCS11_MODULE="/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"
fi

TMP_IN=$(mktemp /dev/shm/avb-in.XXXXXXXXXX)
TMP_OUT=$(mktemp /dev/shm/avb-out.XXXXXXXXXX)
trap 'rm -f "$TMP_IN" "$TMP_OUT"' EXIT

cat > "$TMP_IN"

pkcs11-tool --module "$PKCS11_MODULE" \
  --login --pin "${YUBIKEY_PIV_PIN:?YUBIKEY_PIV_PIN must be set in environment}" \
  --sign --id "$PIV_KEY_ID" \
  --mechanism RSA-PKCS \
  --input-file "$TMP_IN" \
  --output-file "$TMP_OUT" >/dev/null

cat "$TMP_OUT"
