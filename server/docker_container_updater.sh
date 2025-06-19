#!/usr/bin/env bash
set -euo pipefail

cd /srv/docker
docker compose down --remove-orphans
docker network prune -f
docker compose pull
docker compose up -d --force-recreate --remove-orphans --pull always