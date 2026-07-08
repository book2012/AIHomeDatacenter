#!/usr/bin/env bash
set -euo pipefail

ROOT="/opt/aihomedatacenter/scripts"
RUNTIME="/mnt/tempdisk/runtime"

cmd="${1:-help}"

case "$cmd" in
  ready)
    "$ROOT/worker-ready.sh"
    ;;

  heartbeat)
    "$ROOT/worker-heartbeat.sh"
    ;;

  recovery)
    "$ROOT/worker-recovery.sh"
    ;;

  ready-json)
    cat "$RUNTIME/worker-ready.json"
    ;;

  heartbeat-json)
    cat "$RUNTIME/worker-heartbeat.json"
    ;;

  recovery-json)
    cat "$RUNTIME/worker-recovery.json"
    ;;

  status)
    "$ROOT/status.sh"
    ;;

  health)
    "$ROOT/healthcheck.sh"
    ;;

  storage)
    "$ROOT/storage-status.sh"
    ;;

  doctor)
    "$ROOT/doctor.sh"
    ;;

  power)
    "$ROOT/power.sh" "${2:-status}"
    ;;

  *)
    cat <<EOF
AI Home Datacenter Worker Command

Usage:
  worker-command.sh ready
  worker-command.sh heartbeat
  worker-command.sh recovery

  worker-command.sh ready-json
  worker-command.sh heartbeat-json
  worker-command.sh recovery-json

  worker-command.sh status
  worker-command.sh health
  worker-command.sh storage
  worker-command.sh doctor
  worker-command.sh power [status|shutdown]

Approved scripts root:
  $ROOT

Runtime:
  $RUNTIME
EOF
    ;;
esac
