#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"

ok() { echo "OK      $1"; }
warn() { echo "WARNING $1"; }
fail() { echo "FAIL    $1"; }

echo "AI Home Datacenter Doctor"
echo "========================="
echo ""

echo "[Docker]"
if command -v docker >/dev/null 2>&1; then
  ok "Docker installed"
else
  fail "Docker not installed"
fi

if docker info >/dev/null 2>&1; then
  ok "Docker daemon running"
else
  fail "Docker daemon not running"
fi
echo ""

echo "[Services]"
for svc in homepage portainer immich nextcloud; do
  if [ -f "$PROJECT/compose/$svc/compose.yml" ]; then
    if (cd "$PROJECT/compose/$svc" && docker compose ps | grep -q "Up"); then
      ok "$svc running"
    else
      warn "$svc not running"
    fi
  else
    warn "$svc compose missing"
  fi
done
echo ""

echo "[Ports]"
for port in 3000 9443 2283 8080 32400; do
  if ss -tulpn | grep -q ":$port"; then
    ok "port $port listening"
  else
    warn "port $port not listening"
  fi
done
echo ""

echo "[Storage]"
df -h / /mnt/storage /home/han/Backup 2>/dev/null || true
echo ""

ROOT_USE=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
STORAGE_USE=$(df /mnt/storage | awk 'NR==2 {gsub("%","",$5); print $5}')

if [ "$ROOT_USE" -lt 80 ]; then ok "root disk usage ${ROOT_USE}%"; else warn "root disk usage ${ROOT_USE}%"; fi
if [ "$STORAGE_USE" -lt 85 ]; then ok "storage disk usage ${STORAGE_USE}%"; else warn "storage disk usage ${STORAGE_USE}%"; fi
echo ""

echo "[Git]"
cd "$PROJECT"
echo "Branch: $(git branch --show-current)"
if [ -z "$(git status --short)" ]; then
  ok "git working tree clean"
else
  warn "git has uncommitted changes"
  git status --short
fi
echo ""

echo "[Backup]"
LATEST_BACKUP=$(find /mnt/storage/Backup/server-backup -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1 || true)
if [ -n "$LATEST_BACKUP" ]; then
  ok "latest backup: $LATEST_BACKUP"
else
  warn "no server-backup found"
fi
echo ""

echo "[Problem Disk: /dev/sdc]"
if lsblk | grep -q "^sdc"; then
  warn "/dev/sdc detected - known problematic disk"
  sudo dmesg -T | grep -i "sdc\|I/O error\|FPDMA\|DID_BAD_TARGET\|superblock" | tail -10 || true
else
  ok "/dev/sdc not mounted/detected"
fi
