#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
BACKUP_ROOT="/mnt/storage/Backup/server-backup"

echo "AI Home Datacenter Restore"
echo "=========================="
echo ""

echo "Available backups:"
find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d | sort
echo ""

read -rp "Backup path to restore from: " SRC

if [ ! -d "$SRC" ]; then
  echo "ERROR: backup path not found"
  exit 1
fi

echo ""
echo "This will restore compose/scripts/docs/homepage config."
read -rp "Continue? [yes/no]: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Canceled."
  exit 0
fi

mkdir -p "$PROJECT/restore-temp"

[ -f "$SRC/compose.tar.gz" ] && sudo tar xzf "$SRC/compose.tar.gz" -C /
[ -f "$SRC/scripts.tar.gz" ] && sudo tar xzf "$SRC/scripts.tar.gz" -C /
[ -f "$SRC/docs.tar.gz" ] && sudo tar xzf "$SRC/docs.tar.gz" -C /
[ -f "$SRC/homepage-config.tar.gz" ] && sudo tar xzf "$SRC/homepage-config.tar.gz" -C /

echo ""
echo "Restore completed."
echo "Run:"
echo "  ./scripts/service.sh status"
