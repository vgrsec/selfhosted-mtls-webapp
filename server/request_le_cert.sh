#!/usr/bin/env bash
set -euo pipefail

# ── CONFIG ────────────────────────────────────────────────────
DOMAIN="example.com"       # <<< CHANGE THIS TO YOUR DOMAIN
EMAIL="hello@example.com"        # <<< CHANGE THIS TO YOUR EMAIL
# ─────────────────────────────────────────────────────────────

# Locate script directory (assumed to be <repo>/server)
SCRIPT_DIR=/srv/docker
cd "$SCRIPT_DIR"

# Paths
SSL_KEYS_DIR="$SCRIPT_DIR/nginx/ssl_keys"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Ensure output directory exists
mkdir -p "$SSL_KEYS_DIR"

echo "Issuing LE cert for $DOMAIN"

# Temporary workspace
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
KEY_FILE="$TMPDIR/${DOMAIN}.key"
CSR_FILE="$TMPDIR/${DOMAIN}.csr"
CSR_CONF="$TMPDIR/${DOMAIN}.csr.cnf"

# 1) Generate private key & CSR with SAN
cat > "$CSR_CONF" <<EOF
[req]
req_extensions = v3_req
distinguished_name = dn
prompt = no

[dn]
CN = $DOMAIN

[v3_req]
subjectAltName = DNS:$DOMAIN
EOF

openssl genrsa -out "$KEY_FILE" 4096
openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$CSR_CONF"

echo "[+] Generated key & CSR for $DOMAIN"

# 2) Stop nginx to free port 80
echo "[+] Stopping nginx container..."
docker compose down

# 3) Run Certbot in temp workspace, then install into ssl_keys
echo "[+] Running certbot in temp workspace..."
pushd "$TMPDIR" >/dev/null

certbot certonly \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --standalone \
  --preferred-challenges http \
  --http-01-port 80 \
  --csr "$CSR_FILE"

# certbot will output:
#   0000_cert.pem  ← your new cert
#   0000_chain.pem ← the CA chain

echo "[+] Installing new certs into $SSL_KEYS_DIR"
# concatenate cert + chain → fullchain.pem (as nginx expects)
cat 0000_cert.pem 0000_chain.pem > "$SSL_KEYS_DIR/fullchain.pem"
# copy your private key → privkey.pem
cp "$KEY_FILE" "$SSL_KEYS_DIR/privkey.pem"

popd >/dev/null

# 4) Clean up any stray 000*_*.pem in the repo root
rm -f "$SCRIPT_DIR"/000*_*.pem

# 5) Restart nginx
echo "[+] Restarting nginx container..."
docker compose up -d

echo "✔ Done. nginx is up with new certificates."