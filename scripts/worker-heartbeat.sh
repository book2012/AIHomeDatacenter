#!/usr/bin/env bash
set -u

OUT="/mnt/tempdisk/runtime/worker-heartbeat.json"

cat > "$OUT" <<EOF
{
  "worker": "ubuntu-storage-worker",
  "hostname": "$(hostname)",
  "timestamp": "$(date -Iseconds)",
  "uptime": "$(uptime -p | sed 's/"/\\"/g')",
  "load": "$(cat /proc/loadavg | awk '{print $1, $2, $3}')",
  "storage_usage": "$(df -h /mnt/storage | awk 'NR==2 {print $5}')",
  "backupdisk_usage": "$(df -h /mnt/backupdisk | awk 'NR==2 {print $5}')",
  "tempdisk_usage": "$(df -h /mnt/tempdisk | awk 'NR==2 {print $5}')",
  "state": "ONLINE"
}
EOF

cat "$OUT"
