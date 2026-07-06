#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
MODE="${1:-nightly}"

case "$MODE" in
  nightly)
    echo "AI Home Datacenter Nightly Job"
    echo "=============================="
    "$PROJECT/scripts/healthcheck.sh" || true
    "$PROJECT/scripts/backup.sh"
    "$PROJECT/scripts/report.sh"
    "$PROJECT/scripts/cleanup.sh"
    ;;
  weekly)
    echo "AI Home Datacenter Weekly Job"
    echo "============================="
    "$PROJECT/scripts/doctor.sh" || true
    "$PROJECT/scripts/inventory.sh"
    "$PROJECT/scripts/backup.sh"
    "$PROJECT/scripts/report.sh"
    ;;
  *)
    echo "Usage: scheduler.sh nightly|weekly"
    exit 1
    ;;
esac
