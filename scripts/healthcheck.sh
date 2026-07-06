#!/bin/bash
set -euo pipefail

echo "AI Home Datacenter Health Check"
echo "================================"
echo ""

check_url() {
  NAME="$1"
  URL="$2"
  if curl -k -s --max-time 5 -I "$URL" | grep -qE "HTTP/|HTTP/2"; then
    echo "OK   $NAME  $URL"
  else
    echo "FAIL $NAME  $URL"
  fi
}

echo "[Services]"
check_url "Homepage " "http://localhost:3000"
check_url "Portainer" "https://localhost:9443"
check_url "Immich   " "http://localhost:2283"
check_url "Nextcloud" "http://localhost:8080"
check_url "Plex     " "http://localhost:32400/web"
echo ""

echo "[Docker]"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

echo "[Ports]"
ss -tulpn | grep -E "3000|9443|2283|8080|32400" || true
echo ""

echo "[Disk]"
df -h / /mnt/storage /home/han/Backup 2>/dev/null || true
echo ""

echo "[Problem Disk: /dev/sdc]"
sudo dmesg -T | grep -i "sdc\|I/O error\|FPDMA\|DID_BAD_TARGET" | tail -10 || true
