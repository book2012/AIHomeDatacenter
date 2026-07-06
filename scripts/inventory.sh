#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
OUT="$PROJECT/docs/INVENTORY.md"

mkdir -p "$PROJECT/docs"

cat > "$OUT" <<EOF2
# AI Home Datacenter Inventory

Generated: $(date)

## Role

- Mac mini M4: Brain / AI Control Plane / Always ON
- Ubuntu Server: Worker / Storage / Docker Services / On-demand

## Server

\`\`\`
$(hostnamectl)
\`\`\`

## IP

\`\`\`
$(hostname -I)
\`\`\`

## Disks

\`\`\`
$(lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT)
\`\`\`

## Disk Usage

\`\`\`
$(df -h / /mnt/storage /home/han/Backup 2>/dev/null || true)
\`\`\`

## Docker Containers

\`\`\`
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
\`\`\`

## Compose Services

\`\`\`
$(find "$PROJECT/compose" -maxdepth 2 -name compose.yml -print)
\`\`\`

## Open Ports

\`\`\`
$(ss -tulpn | grep -E "3000|9443|2283|8080|32400" || true)
\`\`\`

## Git

\`\`\`
Branch: $(cd "$PROJECT" && git branch --show-current)
$(cd "$PROJECT" && git status --short)
\`\`\`

## Known Issue

- /dev/sdc Samsung HM641JI: I/O error, FPDMA, DID_BAD_TARGET
- Action: Do not use until SATA cable/port replacement
EOF2

echo "Inventory generated: $OUT"
