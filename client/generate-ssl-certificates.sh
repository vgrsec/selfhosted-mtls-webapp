#!/usr/bin/env bash
set -euo pipefail

# Detect macOS
OS_NAME="$(uname -s)"
if [ "$OS_NAME" != "Darwin" ]; then
  echo "This script must be run on macOS. Detected OS: $OS_NAME"
  exit 1
fi
echo "Running on macOS. Continuing..."

# ── CONFIG ────────────────────────────────────────────────────
DOMAIN="example.com"
EMAIL="hello@example.com"
P12_PASS="yourP12password"
# ─────────────────────────────────────────────────────────────

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../project/client
SERVER_ROOT="$(cd "$SCRIPT_DIR/../server" && pwd)"             # .../project/server

# Local output root
OUTPUT_DIR="$SCRIPT_DIR/private_keys"

# Local subdirs
LOCAL_CLIENT_CA_DIR="$OUTPUT_DIR/client_certs"
LOCAL_SSL_KEYS_DIR="$OUTPUT_DIR/ssl_keys"
LOCAL_LE_DIR="$OUTPUT_DIR/letsencrypt"

# Ensure local dirs exist & are empty
for d in "$LOCAL_CLIENT_CA_DIR" "$LOCAL_SSL_KEYS_DIR" "$LOCAL_LE_DIR/live"; do
  if [[ -d "$d" ]]; then
    rm -rf "$d"/*
  else
    mkdir -p "$d"
  fi
done

echo "Outputting everything under: $OUTPUT_DIR"

# Temp workspace
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

###########################################
# 1) CA cert for client mTLS              #
###########################################
CA_KEY_LOCAL="$LOCAL_CLIENT_CA_DIR/ca.key"
CA_CERT_LOCAL="$LOCAL_CLIENT_CA_DIR/ca.crt"

if [[ ! -f "$CA_KEY_LOCAL" ]]; then
  echo "[+] Generating CA key…"
  openssl genrsa -out "$CA_KEY_LOCAL" 4096
fi

if [[ ! -f "$CA_CERT_LOCAL" ]]; then
  echo "[+] Self-signing CA cert…"
  cat > "$tmpdir/ca_ext.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
[req_distinguished_name]

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
EOF
  openssl req -x509 -new -key "$CA_KEY_LOCAL" \
    -sha256 -days 3650 \
    -subj "/C=KS/ST=Oz/L=Emerald City/O=Wizard/OU=BehindCurtain/CN=${DOMAIN}-CA" \
    -extensions v3_ca -config "$tmpdir/ca_ext.cnf" \
    -out "$CA_CERT_LOCAL"
fi

###########################################
# 2) Client cert + PKCS#12 for mTLS       #
###########################################
CLIENT_KEY_LOCAL="$LOCAL_CLIENT_CA_DIR/client_key.pem"
CLIENT_CSR="$tmpdir/client.csr"
CLIENT_CERT_LOCAL="$LOCAL_CLIENT_CA_DIR/client_cert.pem"
CLIENT_P12_LOCAL="$LOCAL_CLIENT_CA_DIR/client_identity.p12"
EXT_FILE="$tmpdir/client_ext.cnf"

echo "[+] Generating client key & CSR…"
openssl genrsa -out "$CLIENT_KEY_LOCAL" 4096
openssl req -new -key "$CLIENT_KEY_LOCAL" \
  -subj "/CN=mtls-client/O=Org" -out "$CLIENT_CSR"

echo "[+] Signing client cert…"
cat > "$EXT_FILE" <<EOF
[usr_cert]
basicConstraints=CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF
openssl x509 -req -in "$CLIENT_CSR" -CA "$CA_CERT_LOCAL" -CAkey "$CA_KEY_LOCAL" -CAcreateserial \
  -out "$CLIENT_CERT_LOCAL" -days 3650 -sha256 -extfile "$EXT_FILE" -extensions usr_cert

echo "[+] Bundling PKCS#12…"
openssl pkcs12 -export -inkey "$CLIENT_KEY_LOCAL" -in "$CLIENT_CERT_LOCAL" -certfile "$CA_CERT_LOCAL" \
  -out "$CLIENT_P12_LOCAL" -passout pass:"$P12_PASS"

###########################################
# 3) Apple mobileconfig for enrollment    #
###########################################
UUID1=$(uuidgen)
UUID2=$(uuidgen)
BASE64_P12=$(openssl base64 -in "$CLIENT_P12_LOCAL" -A)
MOBILECONFIG="$LOCAL_CLIENT_CA_DIR/mtls_client_${DOMAIN}.mobileconfig"
cat > "$MOBILECONFIG" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>PayloadContent</key><array><dict>
    <key>Password</key><string>${P12_PASS}</string>
    <key>PayloadCertificateFileName</key><string>client_identity.p12</string>
    <key>PayloadContent</key><data>${BASE64_P12}</data>
    <key>PayloadIdentifier</key><string>com.${DOMAIN//./}.cert.${UUID1}</string>
    <key>PayloadUUID</key><string>${UUID1}</string>
    <key>PayloadType</key><string>com.apple.security.pkcs12</string>
    <key>PayloadVersion</key><integer>1</integer>
  </dict></array>
  <key>PayloadDisplayName</key><string>${DOMAIN} mTLS Client Profile</string>
  <key>PayloadIdentifier</key><string>com.${DOMAIN//./}.clientprofile.${UUID2}</string>
  <key>PayloadUUID</key><string>${UUID2}</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
</dict></plist>
EOF

echo "[+] Created mobileconfig: $MOBILECONFIG"

###########################################
# 4) Server key + CSR + placeholders      #
###########################################
SVR_KEY_LOCAL="$LOCAL_SSL_KEYS_DIR/server_key.pem"
SVR_CSR_LOCAL="$LOCAL_LE_DIR/live/server.csr"
CSR_CONF="$tmpdir/server_csr.cnf"
PLACE_CERT_LOCAL="$LOCAL_SSL_KEYS_DIR/fullchain.pem"
PLACE_KEY_LOCAL="$LOCAL_SSL_KEYS_DIR/privkey.pem"

mkdir -p "$(dirname "$SVR_CSR_LOCAL")"

echo "[+] Generating server key & CSR…"
cat > "$CSR_CONF" <<EOF
[req]
distinguished_name = dn
req_extensions = ext
prompt = no

[dn]
CN = $DOMAIN

[ext]
subjectAltName = DNS:$DOMAIN
EOF
openssl genrsa -out "$SVR_KEY_LOCAL" 4096
openssl req -new -key "$SVR_KEY_LOCAL" -config "$CSR_CONF" -out "$SVR_CSR_LOCAL"

# Placeholder cert for nginx startup
echo "[+] Creating placeholder certs…"
openssl x509 -req -in "$SVR_CSR_LOCAL" -signkey "$SVR_KEY_LOCAL" -days 7 -out "$PLACE_CERT_LOCAL"
cp "$SVR_KEY_LOCAL" "$PLACE_KEY_LOCAL"

###########################################
# 5) Diffie–Hellman parameters           #
###########################################
DHPARAM_LOCAL="$LOCAL_SSL_KEYS_DIR/ssl-dhparams.pem"
if [[ ! -f "$DHPARAM_LOCAL" ]]; then
  openssl dhparam -out "$DHPARAM_LOCAL" 2048
  echo "[+] DH params: $DHPARAM_LOCAL"
fi

###########################################
# 6) Deploy only server-needed files     #
###########################################
echo "[+] Deploying server artifacts…"
# server target dirs
S_CACERT_DIR="$SERVER_ROOT/srv/docker/nginx/client_certs"
S_SSLKEYS_DIR="$SERVER_ROOT/srv/docker/nginx/ssl_keys"
S_LELIVE_DIR="$SERVER_ROOT/etc/letsencrypt/live"

# clear server dirs
rm -rf "$S_CACERT_DIR"/* "$S_SSLKEYS_DIR"/* "$S_LELIVE_DIR"/*

# copy mTLS CA cert
cp "$CA_CERT_LOCAL" "$S_CACERT_DIR/"

# copy HTTPS keys & placeholders & DH params
cp "$SVR_KEY_LOCAL" "$PLACE_CERT_LOCAL" "$PLACE_KEY_LOCAL" "$DHPARAM_LOCAL" "$S_SSLKEYS_DIR/"

# copy server CSR for Let's Encrypt
cp "$SVR_CSR_LOCAL" "$SERVER_ROOT/etc/letsencrypt/"

###########################################
# Done!                                   #
###########################################
echo
echo "✔ Generated all certs under: $OUTPUT_DIR"
echo
echo "✔ Server-ready CA → $S_CACERT_DIR/ca.crt"
echo "✔ Server-ready SSL → $(ls -1 $S_SSLKEYS_DIR)"
echo "✔ Server CSR → $SERVER_ROOT/etc/letsencrypt/$(basename $SVR_CSR_LOCAL)"