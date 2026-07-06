#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
COMPOSE="${PROJECT}/compose"
SERVICE="${1:-}"

usage() {
  echo "Usage:"
  echo "  docker-update.sh <service>"
  echo "  docker-update.sh all"
  echo ""
  echo "Available services:"
  find "$COMPOSE" -mindepth 1 -maxdepth 1 -type d -printf "  %f\n" | sort
}

update_service() {
  local svc="$1"
  local dir="${COMPOSE}/${svc}"

  if [ ! -f "${dir}/compose.yml" ]; then
    echo "ERROR: service not found: ${svc}"
    exit 1
  fi

  echo ""
  echo "===== Updating ${svc} ====="
  cd "$dir"
  docker compose pull
  docker compose up -d
}

if [ -z "$SERVICE" ]; then
  usage
  exit 1
fi

echo "AI Home Datacenter Docker Update"
echo "================================"

echo "[1/3] Backup current configuration..."
"${PROJECT}/scripts/backup.sh"

echo "[2/3] Update containers..."

if [ "$SERVICE" = "all" ]; then
  for dir in "$COMPOSE"/*; do
    [ -d "$dir" ] || continue
    svc=$(basename "$dir")
    [ -f "$dir/compose.yml" ] || continue
    update_service "$svc"
  done
else
  update_service "$SERVICE"
fi

echo ""
echo "[3/3] Health check..."
"${PROJECT}/scripts/healthcheck.sh"

echo ""
echo "Docker update completed."
