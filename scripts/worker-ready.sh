#!/usr/bin/env bash
set -u

OUT="/mnt/tempdisk/runtime/worker-ready.json"
HOSTNAME="$(hostname)"
NOW="$(date -Iseconds)"
UPTIME="$(uptime -p | sed 's/"/\\"/g')"
IP="$(hostname -I | awk '{print $1}')"

check_mount() {
  if mountpoint -q "$1"; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

DOCKER_STATUS="UNKNOWN"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    DOCKER_STATUS="OK"
  else
    DOCKER_STATUS="FAIL"
  fi
else
  DOCKER_STATUS="MISSING"
fi

STORAGE_STATUS="$(check_mount /mnt/storage)"
BACKUP_STATUS="$(check_mount /mnt/backupdisk)"
TEMP_STATUS="$(check_mount /mnt/tempdisk)"
EXHDD1_STATUS="$(check_mount /mnt/exHDD1)"
EXHDD2_STATUS="$(check_mount /mnt/exHDD2)"

READY="true"

for status in "$STORAGE_STATUS" "$BACKUP_STATUS" "$TEMP_STATUS" "$DOCKER_STATUS"; do
  if [ "$status" != "OK" ]; then
    READY="false"
  fi
done

cat > "$OUT" <<EOF
{
  "worker": "ubuntu-storage-worker",
  "hostname": "$HOSTNAME",
  "ip": "$IP",
  "timestamp": "$NOW",
  "uptime": "$UPTIME",
  "state": "$([ "$READY" = "true" ] && echo "READY" || echo "NOT_READY")",
  "ready": $READY,
  "checks": {
    "storage": "$STORAGE_STATUS",
    "backupdisk": "$BACKUP_STATUS",
    "tempdisk": "$TEMP_STATUS",
    "exHDD1": "$EXHDD1_STATUS",
    "exHDD2": "$EXHDD2_STATUS",
    "docker": "$DOCKER_STATUS",
    "ssh": "OK"
  },
  "capabilities": [
    "storage",
    "backup",
    "restore",
    "nextcloud",
    "immich",
    "plex",
    "docker",
    "power",
    "health"
  ],
  "approved_scripts_root": "/opt/aihomedatacenter/scripts"
}
EOF

cat "$OUT"
