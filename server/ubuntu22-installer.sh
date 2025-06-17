#!/bin/bash

## Install prereqs for selfhosted-mtls-webapp on ubuntu22

echo "Updating package lists..."
apt-get update -qq

echo "upgrading host"
apt-get upgrade -qq -y

echo "Installing prerequisite packages..."
apt-get install -qq -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  vim \
  unattended-upgrades \
  rsync \
  certbot

echo "Adding Docker's official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null

echo "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

echo "Updating package lists again..."
apt-get update -qq

echo "Installing Docker Engine, CLI, and containerd..."
apt-get install -qq -y docker-ce docker-ce-cli containerd.io

echo "Checking for Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    apt-get install -qq -y docker-compose
else
    echo "Docker Compose is already installed."
fi


# Define the configuration file for unattended-upgrades.
UNATTENDED_UPGRADES_CONFIG_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"

echo "Configuring unattended-upgrades for automatic reboot if required..."

# Look for an existing Automatic-Reboot directive and modify it.
if grep -q 'Unattended-Upgrade::Automatic-Reboot' "$UNATTENDED_UPGRADES_CONFIG_FILE"; then
  # Uncomment and set to "true" if the line is commented out or set to false.
  sed -i -E 's|^//\s*(Unattended-Upgrade::Automatic-Reboot).*|Unattended-Upgrade::Automatic-Reboot "true";|' "$CONFIG_FILE"
  sed -i -E 's|^(Unattended-Upgrade::Automatic-Reboot\s*).*|Unattended-Upgrade::Automatic-Reboot "true";|' "$CONFIG_FILE"
else
  # Append the directive if it does not exist.
  echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$UNATTENDED_UPGRADES_CONFIG_FILE"
fi

echo "Configuring periodic updates in /etc/apt/apt.conf.d/20auto-upgrades..."
AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
# Backup the original if it exists.
if [ -f "$AUTO_UPGRADES_FILE" ]; then
  BACKUP_AUTO="${AUTO_UPGRADES_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  echo "Creating backup of $AUTO_UPGRADES_FILE at $BACKUP_AUTO..."
  cp "$AUTO_UPGRADES_FILE" "$BACKUP_AUTO"
fi

# Set periodic update directives.
cat > "$AUTO_UPGRADES_FILE" <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "Configuration complete. The unattended-upgrades service is now set to install updates automatically and reboot the system if required."