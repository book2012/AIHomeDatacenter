#!/bin/bash
set -euo pipefail

echo "AI Home Datacenter Cleanup"
echo "=========================="

echo "[1/5] Apt cache cleanup"
sudo apt autoremove -y
sudo apt autoclean -y

echo "[2/5] Docker dangling images cleanup"
docker image prune -f

echo "[3/5] Docker build cache cleanup"
docker builder prune -f

echo "[4/5] Old server backups cleanup: keep 14 days"
find /mnt/storage/Backup/server-backup -mindepth 1 -maxdepth 1 -type d -mtime +14 -print -exec rm -rf {} \; 2>/dev/null || true

echo "[5/5] Journal cleanup: keep 14 days"
sudo journalctl --vacuum-time=14d

echo "Cleanup completed."
