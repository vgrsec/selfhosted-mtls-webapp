#!/usr/bin/env bash
set -euo pipefail

# 1. Enable IPv4 forwarding permanently
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# 2. Load necessary kernel modules (IPsec/xfrm)
sudo modprobe af_key
sudo modprobe xfrm_user
sudo modprobe xfrm4_tunnel
sudo modprobe xfrm4_mode_tunnel

# 3. Open UDP 500/4500 in firewall
sudo ufw allow 500/udp
sudo ufw allow 4500/udp
# or, if using iptables directly:
# sudo iptables -I INPUT -p udp --dport 500 -j ACCEPT
# sudo iptables -I INPUT -p udp --dport 4500 -j ACCEPT