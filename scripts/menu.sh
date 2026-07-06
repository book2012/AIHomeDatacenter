#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"

while true; do
  clear
  echo "AI Home Datacenter Console"
  echo "=========================="
  echo "Mac mini : Brain / AI Control Plane"
  echo "Ubuntu   : Worker / Storage Node"
  echo ""
  echo "1) Status"
  echo "2) Health Check"
  echo "3) Monitor"
  echo "4) Doctor"
  echo "5) Backup"
  echo "6) Docker Update"
  echo "7) Git Sync"
  echo "8) Logs"
  echo "9) Plex"
  echo "10) Inventory"
  echo "11) Report"
  echo "12) Cleanup"
  echo "0) Exit"
  echo ""
  read -rp "Select: " CHOICE

  case "$CHOICE" in
    1) "$PROJECT/scripts/status.sh" ;;
    2) "$PROJECT/scripts/healthcheck.sh" ;;
    3) "$PROJECT/scripts/monitor.sh" ;;
    4) "$PROJECT/scripts/doctor.sh" ;;
    5) "$PROJECT/scripts/backup.sh" ;;
    6) read -rp "Service name or all: " SVC; "$PROJECT/scripts/docker-update.sh" "$SVC" ;;
    7) read -rp "Commit message: " MSG; "$PROJECT/scripts/git-sync.sh" "$MSG" ;;
    8) read -rp "Service name or all: " SVC; "$PROJECT/scripts/logs.sh" "$SVC" 80 ;;
    9)
      echo "Plex: start | stop | restart | status | enable | disable"
      read -rp "Command: " CMD
      "$PROJECT/scripts/plex.sh" "$CMD"
      ;;
    10) "$PROJECT/scripts/inventory.sh" ;;
    11) "$PROJECT/scripts/report.sh" ;;
    12) "$PROJECT/scripts/cleanup.sh" ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
  esac

  echo ""
  read -rp "Press Enter to continue..."
done
