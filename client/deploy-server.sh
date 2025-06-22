#!/usr/bin/env bash
set -euo pipefail

# deploy_server.sh
# ---------------
# Copies the packaged server archive to the remote host and unpacks it.
# Usage: ./deploy_server.sh [ARCHIVE_PATH] [IDENTITY_KEY] [REMOTE_USER] [REMOTE_HOST]

# default values
DEFAULT_ARCHIVE_PATH="../selfhosted-mtls-webapp.tar.gz"
DEFAULT_IDENTITY_KEY="$HOME/.ssh/app@example.com_ssh_key_id_ed25519"
DEFAULT_REMOTE_USER="username"
DEFAULT_REMOTE_HOST="example.com"

# 1) If positional args were provided, seed the defaults from them:
ARCHIVE_PATH="${1:-$DEFAULT_ARCHIVE_PATH}"
IDENTITY_KEY="${2:-$DEFAULT_IDENTITY_KEY}"
REMOTE_USER="${3:-$DEFAULT_REMOTE_USER}"
REMOTE_HOST="${4:-$DEFAULT_REMOTE_HOST}"

# 2) Now prompt the user, showing the current value as the default
read -p "Archive path [$ARCHIVE_PATH]: " input
ARCHIVE_PATH="${input:-$ARCHIVE_PATH}"

read -p "SSH identity key path [$IDENTITY_KEY]: " input
IDENTITY_KEY="${input:-$IDENTITY_KEY}"

read -p "Remote user [$REMOTE_USER]: " input
REMOTE_USER="${input:-$REMOTE_USER}"

read -p "Remote host (no https://) [$REMOTE_HOST]: " input
REMOTE_HOST="${input:-$REMOTE_HOST}"

# Export or echo the final values, or use them directly below
echo "Using:"
echo "  ARCHIVE_PATH  = $ARCHIVE_PATH"
echo "  IDENTITY_KEY  = $IDENTITY_KEY"
echo "  REMOTE_USER   = $REMOTE_USER"
echo "  REMOTE_HOST   = $REMOTE_HOST"

# Derive archive name
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"

# Determine remote home directory dynamically
REMOTE_HOME=$(ssh -i "$IDENTITY_KEY" -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" 'echo $HOME')
if [[ -z "$REMOTE_HOME" ]]; then
  echo "[!] Could not determine remote home directory"
  exit 1
fi
REMOTE_ARCHIVE="$REMOTE_HOME/$ARCHIVE_NAME"
REMOTE_DIR="$REMOTE_HOME/selfhosted-mtls-webapp"

# Copy archive
echo "[+] Deploying $ARCHIVE_PATH to $REMOTE_USER@$REMOTE_HOST:$REMOTE_ARCHIVE"
scp -i "$IDENTITY_KEY" -o BatchMode=yes "$ARCHIVE_PATH" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_ARCHIVE"

# SSH in and extract
echo "[+] Connecting to remote server to extract archive"
ssh -i "$IDENTITY_KEY" -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" bash <<EOF
  set -eu
  if command -v lsb_release >/dev/null 2>&1; then
    OS_VER="\$(lsb_release -d -s)"
  elif [ -r /etc/os-release ]; then
    OS_VER="\$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '\"')"
  else
    echo "[!] Could not detect remote OS version"
    exit 1
  fi
  echo "[+] Detected OS: \$OS_VER"
  rm -rf "${REMOTE_DIR}"
  mkdir -p "${REMOTE_DIR}"
  tar --strip-components=1 -xzf "${REMOTE_ARCHIVE}" -C "${REMOTE_DIR}"
  rm "${REMOTE_ARCHIVE}"
  echo "[+] Extracted ${ARCHIVE_NAME} into ${REMOTE_DIR}"
  echo "[+] Deploy Docker application"
  sudo rsync -a --delete "${REMOTE_DIR}/srv/docker/" /srv/docker/

  echo "[+] Deploy Let’s Encrypt files"
  sudo rsync -a --delete ~/selfhosted-mtls-webapp/etc/letsencrypt/ /etc/letsencrypt/
  if [[ "\$OS_VER" == Ubuntu\ 22.* ]]; then
    echo "[+] Installing prerequisite packages"
    sudo "${REMOTE_DIR}/ubuntu22-installer.sh"

    echo "[+] Requesting certs & starting server"
    sudo "${REMOTE_DIR}/request_le_cert.sh"
  else
    echo "[!] Unsupported OS: \$OS_VER"
    echo "    Please install prerequisites manually and rerun request_le_cert.sh"
    exit 1
  fi
  sudo sync -a --delete "${REMOTE_DIR}/request_le_cert.sh" /srv/
  sudo ln -s /srv/request_le_cert.sh /etc/cron.weekly/request_le_cert
  sudo sync -a --delete "${REMOTE_DIR}/docker_container_update.sh" /srv/
  sudo ln -s /srv/docker_container_update.sh /etc/cron.daily/docker_container_update
  sudo sync -a --delete "${REMOTE_DIR}/openvpn-as-setup.sh" /srv/
  sudo "${REMOTE_DIR}/openvpn-as-setup.sh"
EOF

echo "Deployment complete."
