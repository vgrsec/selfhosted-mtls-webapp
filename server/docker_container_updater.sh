#!/usr/bin/env bash
set -euo pipefail

cd /srv/docker
docker compose down
docker compose pull
docker compose up -d --force-recreate --remove-orphans --pull always