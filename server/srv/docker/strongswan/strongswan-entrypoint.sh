#!/bin/sh
set -eux

# 1) Install StrongSwan if not already present
#    (each container start will re-run this; small overhead on cold start)
if ! command -v ipsec >/dev/null; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
  	iproute2 \
  	iptables \
    libcharon-extauth-plugins \
    libcharon-extra-plugins \
    libstrongswan-extra-plugins \
    strongswan \
    strongswan-charon \
    strongswan-starter \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  rm -rf /var/lib/apt/lists/*
fi

# 2) Enable packet forwarding
sysctl -w net.ipv4.ip_forward=1

# 3) Link/move them into the default ipsec dirs
#    (StrongSwan expects /etc/ipsec.d/{certs,cacerts})
mkdir -p /etc/ipsec.d/certs /etc/ipsec.d/cacerts

# 4) Drop into the CMD (which will be: ipsec start --nofork)
exec "$@"