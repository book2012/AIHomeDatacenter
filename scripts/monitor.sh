#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"

echo "AI Home Datacenter Monitor"
echo "=========================="
echo ""

echo "[Server]"
hostnamectl --static
uptime
echo ""

echo "[IP]"
hostname -I
echo ""

echo "[Disk]"
df -h / /mnt/storage /home/han/Backup 2>/dev/null || true
echo ""

echo "[Memory]"
free -h
echo ""

echo "[Docker]"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

echo "[Ports]"
ss -tulpn | grep -E "3000|9443|2283|8080|32400" || true
echo ""

echo "[Git]"
cd "$PROJECT"
echo "Branch: $(git branch --show-current)"
git status --short
echo ""

echo "[Recent Disk Errors]"
sudo dmesg -T | grep -i "sdc\|I/O error\|FPDMA\|DID_BAD_TARGET" | tail -10 || true
