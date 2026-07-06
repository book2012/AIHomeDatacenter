#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"

echo "AI Home Datacenter Installer"
echo "============================"

echo "[1/5] Create directories"
sudo mkdir -p "$PROJECT"/{compose,configs,scripts,docker-data,backup,docs}
sudo mkdir -p /mnt/storage/{Photos,CloudData,Backup,Documents,AI}

echo "[2/5] Create Docker network"
docker network inspect homelab >/dev/null 2>&1 || docker network create homelab

echo "[3/5] Check compose files"
find "$PROJECT/compose" -maxdepth 2 -name compose.yml -print

echo "[4/5] Start core services"
for svc in portainer homepage immich nextcloud; do
  if [ -f "$PROJECT/compose/$svc/compose.yml" ]; then
    echo "Starting $svc"
    (cd "$PROJECT/compose/$svc" && docker compose up -d)
  fi
done

echo "[5/5] Health check"
"$PROJECT/scripts/healthcheck.sh" || true

echo ""
echo "Install/bootstrap completed."
