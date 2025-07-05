#!/usr/bin/env bash
set -euo pipefail

# Locate script directory (assumed to be <repo>/server)
SCRIPT_DIR=/srv/docker
cd "$SCRIPT_DIR"

# Paths
OPENVPN_CONFIG="$SCRIPT_DIR/openvpn/etc"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Container
CONTAINER="openvpn-as"
SACLI_CMD="/usr/local/openvpn_as/scripts/sacli"
VPNUSER="vpnuser@example.com"

# Make sure openvpn does a first start
../docker_container_update.sh


if ! timeout --foreground 120s \
     bash -c 'docker compose logs -f openvpn-as 2>&1 | grep -m1 "Server Agent started"'
then
  echo "timed out waiting for Server Agent started" >&2
  exit 1
fi

mkdir -p ./openvpn/etc
docker compose logs openvpn-as \
  | grep 'Auto-generated pass =' \
  | grep -oP '(?<=Auto-generated pass = ")[^"]+' \
  > ./openvpn/etc/adminpassword.txt

echo "admin password written to ./openvpn/etc/adminpassword.txt"

# Internal settings
docker exec "$CONTAINER" $SACLI_CMD \
  --key "run_api.active_profile" \
  --value "Default" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "webui.edit_profile" \
  --value "Default" \
  ConfigPut

# Default profile settings
docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "host.name" \
  --value "example.com/ovpnclient" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "admin_ui.https.ip_address" \
  --value "all" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "admin_ui.https.port" \
  --value "943" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "cs.https.ip_address" \
  --value "all" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "cs.https.port" \
  --value "943" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.daemon.0.listen.ip_address" \
  --value "all" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.daemon.0.server.ip_address" \
  --value "all" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.daemon.0.listen.port" \
  --value "443" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.client.routing.reroute_gw" \
  --value "false" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.client.routing.reroute_dns" \
  --value "false" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.routing.private_access" \
  --value "route" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.daemon.tcp.port" \
  --value "443" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.daemon.tcp.n_daemons" \
  --value "2" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.daemon.udp.n_daemons" \
  --value "2" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.routing.private_network.0" \
  --value "172.20.0.0/24" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.routing.private_network.1" \
  --value "172.27.240.0/20" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vpn.server.routing.allow_private_nets_to_clients" \
  --value "true" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --prof "Default" \
  --key "vvpn.server.tls_cc_security" \
  --value "tls-crypt" \
  ConfigPut

# Create the VPN User (Passwordless)
docker exec "$CONTAINER" $SACLI_CMD \
  --user "vpnuser" \
  --key "type" \
  --value "user_connect" \
  UserPropPut

docker exec "$CONTAINER" $SACLI_CMD \
  --user "$VPNUSER" \
  --key "access_to.0" \
  --value "+NAT:172.20.0.0/24" \
  UserPropPut

docker exec "$CONTAINER" $SACLI_CMD \
  --user "$VPNUSER" \
  --key "access_to.1" \
  --value "+NAT:172.27.0.0/20" \
  UserPropPut

docker exec "$CONTAINER" $SACLI_CMD \
  --user "$VPNUSER" \
  --key "prop_inter_client" \
  --value "true" \
  UserPropPut

docker exec "$CONTAINER" $SACLI_CMD \
  --user "$VPNUSER" \
  --key "prop_autologin" \
  --value "true" \
  UserPropPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "vpn.client.routing.inter_client" \
  --value "true" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "vpn.client.routing.reroute_dns" \
  --value "custom" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "vpn.client.routing.reroute_gw" \
  --value "custom" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "vpn.server.dhcp_option.dns.0" \
  --value "172.20.0.2" \
  ConfigPut

docker exec "$CONTAINER" $SACLI_CMD \
  --key "vpn.server.dhcp_option.domain" \
  --value ".docker, docker, docker." \
  ConfigPut

# Take down service
docker compose down openvpn-as
# Uncomment all lines in docker-compose.yml
# This doesn't do anything yet because external
# certs aren't being loaded.
sed -i 's/^#//g' "$COMPOSE_FILE"

# Restart Services
../docker_container_update.sh

docker compose logs openvpn-as \
  | grep 'Auto-generated pass =' \
  | grep -oP '(?<=Auto-generated pass = ")[^"]+' \
  > ./openvpn/etc/adminpassword.txt

echo "admin password written to ./openvpn/etc/adminpassword.txt"


