#!/usr/bin/env bash
set -euo pipefail

MAX_ATTEMPTS=5
DELAY=5

retry() {
  local cmd="$*"
  local attempt=1

  until eval "$cmd"; do
    if (( attempt >= MAX_ATTEMPTS )); then
      echo "Command failed after $attempt attempts: $cmd" >&2
      return 1
    fi
    echo "$attempt/$MAX_ATTEMPTS failed. Retrying in $DELAY seconds..."
    sleep $DELAY
    (( attempt++ ))
    # optional: exponential back-off
    (( DELAY *= 2 ))
  done
}

cd /srv/docker

retry docker compose down
retry "docker network prune -f"
retry "docker compose pull"
retry "docker compose up -d --force-recreate --remove-orphans --pull always"

echo "Service Up"