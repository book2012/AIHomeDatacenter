#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
DATE=$(date +%F)
OUT_DIR="$PROJECT/reports"
OUT="$OUT_DIR/$DATE.md"

mkdir -p "$OUT_DIR"

cat > "$OUT" <<EOF2
# AI Home Datacenter Daily Report

Date: $(date)

## Role Split

- Mac mini M4: AI Agent, OpenClaw, Homepage, n8n, external APIs, personal assistant, Ubuntu controller
- Ubuntu Server: Docker services, storage, backup worker, on-demand boot/shutdown

## Service Status

\`\`\`
$(docker ps --format "table {{.Names}}\t{{.Status}}")
\`\`\`

## Health Check

\`\`\`
$("$PROJECT/scripts/healthcheck.sh" 2>&1 || true)
\`\`\`

## Disk

\`\`\`
$(df -h / /mnt/storage /home/han/Backup 2>/dev/null || true)
\`\`\`

## Backup

\`\`\`
$(find /mnt/storage/Backup/server-backup -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -5 || true)
\`\`\`

## Git

\`\`\`
$(cd "$PROJECT" && git status --short)
\`\`\`

## Notes

- Samsung HDD /dev/sdc remains isolated until SATA cable replacement.
- Data migration from old ownCloud disk is paused.
EOF2

echo "Report generated: $OUT"
