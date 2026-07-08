#!/usr/bin/env bash
set -u

OUT="/mnt/tempdisk/runtime/worker-recovery.json"
NOW="$(date -Iseconds)"
HOSTNAME="$(hostname)"

mkdir -p /mnt/tempdisk/runtime

check_mount() {
  local path="$1"
  if mountpoint -q "$path"; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "MISSING"
  elif docker info >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

check_container_count() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker ps --format '{{.Names}}' | wc -l
  else
    echo "0"
  fi
}

STORAGE="$(check_mount /mnt/storage)"
BACKUPDISK="$(check_mount /mnt/backupdisk)"
TEMPDISK="$(check_mount /mnt/tempdisk)"
EXHDD1="$(check_mount /mnt/exHDD1)"
EXHDD2="$(check_mount /mnt/exHDD2)"
DOCKER="$(check_docker)"
CONTAINERS="$(check_container_count)"

ISSUES=()

[ "$STORAGE" != "OK" ] && ISSUES+=("storage_mount_failed")
[ "$BACKUPDISK" != "OK" ] && ISSUES+=("backupdisk_mount_failed")
[ "$TEMPDISK" != "OK" ] && ISSUES+=("tempdisk_mount_failed")
[ "$DOCKER" != "OK" ] && ISSUES+=("docker_unhealthy")

STATE="OK"
if [ "${#ISSUES[@]}" -gt 0 ]; then
  STATE="ATTENTION_REQUIRED"
fi

ISSUES_JSON=""
for issue in "${ISSUES[@]}"; do
  if [ -z "$ISSUES_JSON" ]; then
    ISSUES_JSON="\"$issue\""
  else
    ISSUES_JSON="$ISSUES_JSON, \"$issue\""
  fi
done

cat > "$OUT" <<EOF
{
  "worker": "ubuntu-storage-worker",
  "hostname": "$HOSTNAME",
  "timestamp": "$NOW",
  "state": "$STATE",
  "checks": {
    "storage": "$STORAGE",
    "backupdisk": "$BACKUPDISK",
    "tempdisk": "$TEMPDISK",
    "exHDD1": "$EXHDD1",
    "exHDD2": "$EXHDD2",
    "docker": "$DOCKER",
    "running_containers": "$CONTAINERS"
  },
  "issues": [$ISSUES_JSON],
  "mode": "detect_only",
  "recommended_action": "$([ "$STATE" = "OK" ] && echo "none" || echo "manual_review_required")"
}
EOF

cat "$OUT"
