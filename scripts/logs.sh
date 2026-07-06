#!/bin/bash
set -euo pipefail

SERVICE="${1:-}"
LINES="${2:-80}"

PROJECT="/opt/aihomedatacenter"
COMPOSE="${PROJECT}/compose"

usage() {
  echo "Usage:"
  echo "  logs.sh <service> [lines]"
  echo "  logs.sh all [lines]"
  echo ""
  echo "Available services:"
  find "$COMPOSE" -mindepth 1 -maxdepth 1 -type d -printf "  %f\n" | sort
}

if [ -z "$SERVICE" ]; then
  usage
  exit 1
fi

if [ "$SERVICE" = "all" ]; then
  for dir in "$COMPOSE"/*; do
    [ -f "$dir/compose.yml" ] || continue
    svc=$(basename "$dir")
    echo ""
    echo "===== ${svc} logs ====="
    cd "$dir"
    docker compose logs --tail="$LINES"
  done
  exit 0
fi

if [ ! -f "$COMPOSE/$SERVICE/compose.yml" ]; then
  echo "ERROR: service not found: $SERVICE"
  usage
  exit 1
fi

cd "$COMPOSE/$SERVICE"
docker compose logs --tail="$LINES" -f
