#!/bin/bash
set -e

DATE=$(date +%F_%H-%M)
BACKUP_ROOT="/mnt/storage/Backup/server-backup/$DATE"

mkdir -p "$BACKUP_ROOT"

echo "=================================="
echo " AI Home Datacenter Backup"
echo "=================================="

echo "[1/6] Backup compose..."
tar czf "$BACKUP_ROOT/compose.tar.gz" /opt/aihomedatacenter/compose

echo "[2/6] Backup scripts..."
tar czf "$BACKUP_ROOT/scripts.tar.gz" /opt/aihomedatacenter/scripts

echo "[3/6] Backup docs..."
tar czf "$BACKUP_ROOT/docs.tar.gz" /opt/aihomedatacenter/docs

echo "[4/6] Backup Homepage config..."
tar czf "$BACKUP_ROOT/homepage-config.tar.gz" \
	/opt/aihomedatacenter/docker-data/homepage/config

echo "[5/6] Docker info..."
docker ps -a > "$BACKUP_ROOT/docker-ps.txt"
docker images > "$BACKUP_ROOT/docker-images.txt"

echo "[6/6] Git status..."
git -C /opt/aihomedatacenter status > "$BACKUP_ROOT/git-status.txt"

echo ""
echo "Backup completed!"
echo "$BACKUP_ROOT"
