#!/usr/bin/env bash
set -euo pipefail

# generate-wireguard-configs.sh
# Generates WireGuard server & client configs with embedded Base64 keys,
# using a throwaway Python venv. Outputs to ./private_keys/wireguard_configs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/private_keys}"
CONF_DIR="$OUTPUT_DIR/wireguard_configs"

# Prepare output
mkdir -p "$CONF_DIR"

# Find python3
PYTHON_BIN=$(command -v python3) || {
  echo "Error: python3 not found in PATH." >&2
  exit 1
}

# Create & activate venv
VENV_DIR="$(mktemp -d)"
"$PYTHON_BIN" -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# Install dependency
pip install --quiet --upgrade pip cryptography

# Run Python to generate configs
python << 'PYCODE'
import os, base64
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

# Paths
base = Path(os.environ.get("OUTPUT_DIR", "")) or Path(__file__).parent / "private_keys"
conf_dir = base / "wireguard_configs"
conf_dir.mkdir(parents=True, exist_ok=True)

# Generate keypairs
srv_priv = x25519.X25519PrivateKey.generate()
srv_pub  = srv_priv.public_key()
cli_priv = x25519.X25519PrivateKey.generate()
cli_pub  = cli_priv.public_key()

def to_b64(obj, private: bool):
    raw = (
        obj.private_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PrivateFormat.Raw,
            encryption_algorithm=serialization.NoEncryption()
        )
        if private else
        obj.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )
    )
    return base64.b64encode(raw).decode("ascii")

S_PRIV = to_b64(srv_priv, True)
S_PUB  = to_b64(srv_pub,  False)
C_PRIV = to_b64(cli_priv, True)
C_PUB  = to_b64(cli_pub,  False)

# Write server config
(srv_conf := conf_dir / "wg0.conf").write_text(f"""[Interface]
PrivateKey = {S_PRIV}
Address    = 172.20.0.5/24
ListenPort = 51820
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey  = {C_PUB}
AllowedIPs = 172.20.0.100/32
""")

# Write client config
(cli_conf := conf_dir / "wg-client.conf").write_text(f"""[Interface]
PrivateKey = {C_PRIV}
Address    = 172.20.0.100/32
DNS        = 172.20.0.3

[Peer]
PublicKey  = {S_PUB}
Endpoint   = your.server.domain:51820
AllowedIPs = 172.20.0.0/24
PersistentKeepalive = 25
""")

print(f"Generated server config: {srv_conf}")
print(f"Generated client config: {cli_conf}")
PYCODE

# Teardown venv
deactivate
rm -rf "$VENV_DIR"

echo "Temporary venv removed."
echo "All configs written under: $CONF_DIR"