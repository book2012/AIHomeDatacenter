#!/usr/bin/env bash
set -euo pipefail

echo "=== DISK USAGE ==="
df -h

echo
echo "=== STORAGE ROOT ==="
tree -L 2 /mnt/storage

echo
echo "=== BACKUP DISK ==="
tree -L 2 /mnt/backupdisk

echo
echo "=== TEMP DISK ==="
tree -L 2 /mnt/tempdisk

echo
echo "=== HASH REPORTS ==="
ls -lh /mnt/tempdisk/hash 2>/dev/null || true
