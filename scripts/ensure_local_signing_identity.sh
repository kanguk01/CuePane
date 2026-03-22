#!/bin/zsh

set -euo pipefail

IDENTITY_NAME="${CUEPANE_SIGNING_IDENTITY:-CuePane Local Signer}"
KEYCHAIN_PATH="${CUEPANE_SIGNING_KEYCHAIN_PATH:-$HOME/.cuepane-local-signing/CuePaneLocal.keychain-db}"
KEYCHAIN_PASSWORD="${CUEPANE_SIGNING_KEYCHAIN_PASSWORD:-cuepane-local}"
WORK_DIR="$(dirname "$KEYCHAIN_PATH")"
CERT_DIR="$WORK_DIR/generated"
OPENSSL_CONFIG="$CERT_DIR/openssl.cnf"
CERT_PATH="$CERT_DIR/cert.pem"
P12_PATH="$CERT_DIR/cert.p12"

mkdir -p "$CERT_DIR"

ensure_keychain_in_search_list() {
  local -a current_keychains
  current_keychains=("${(@f)$(security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"$//')}")

  if [[ ! " ${current_keychains[*]} " == *" ${KEYCHAIN_PATH} "* ]]; then
    security list-keychains -d user -s "$KEYCHAIN_PATH" "${current_keychains[@]}"
  fi
}

if ! security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
  if [[ -f "$KEYCHAIN_PATH" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  fi

  rm -rf "$CERT_DIR"
  mkdir -p "$CERT_DIR"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

  cat > "$OPENSSL_CONFIG" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY_NAME
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_PATH" \
    -days 3650 \
    -nodes \
    -config "$OPENSSL_CONFIG" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -out "$P12_PATH" \
    -inkey "$CERT_DIR/key.pem" \
    -in "$CERT_PATH" \
    -passout "pass:$KEYCHAIN_PASSWORD" >/dev/null 2>&1

  security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
ensure_keychain_in_search_list

echo "$IDENTITY_NAME"
