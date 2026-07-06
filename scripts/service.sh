#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
COMPOSE="${PROJECT}/compose"

COMMAND="${1:-}"
SERVICE="${2:-}"

usage() {
  echo ""
  echo "Usage:"
  echo "  service.sh list"
  echo "  service.sh status"
  echo "  service.sh up <service>"
  echo "  service.sh down <service>"
  echo "  service.sh restart <service>"
  echo "  service.sh logs <service>"
  echo "  service.sh ps <service>"
  echo "  service.sh pull <service>"
  echo "  service.sh update <service>"
  echo ""
}

service_exists() {
  [ -d "${COMPOSE}/${SERVICE}" ] && [ -f "${COMPOSE}/${SERVICE}/compose.yml" ]
}

require_service() {
  if [ -z "${SERVICE}" ]; then
    echo "ERROR: service name is required."
    usage
    exit 1
  fi

  if ! service_exists; then
    echo "ERROR: service not found: ${SERVICE}"
    echo ""
    echo "Available services:"
    find "${COMPOSE}" -mindepth 1 -maxdepth 1 -type d -printf "  %f\n" | sort
    exit 1
  fi
}

case "${COMMAND}" in
  list)
    find "${COMPOSE}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
    ;;

  status)
    for dir in "${COMPOSE}"/*; do
      [ -d "$dir" ] || continue
      svc=$(basename "$dir")
      if [ -f "$dir/compose.yml" ]; then
        echo ""
        echo "===== ${svc} ====="
        (cd "$dir" && docker compose ps)
      fi
    done
    ;;

  up)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose up -d
    ;;

  down)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose down
    ;;

  restart)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose restart
    ;;

  logs)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose logs -f
    ;;

  ps)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose ps
    ;;

  pull)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose pull
    ;;

  update)
    require_service
    cd "${COMPOSE}/${SERVICE}"
    docker compose pull
    docker compose up -d
    ;;

  *)
    usage
    exit 1
    ;;
esac
