#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"

case "${1:-}" in

off)

echo "AI Home Datacenter Shutdown"

"$PROJECT/scripts/healthcheck.sh" || true

"$PROJECT/scripts/backup.sh"

echo "Stopping Docker containers..."

docker ps -q | xargs -r docker stop

echo "Shutdown in 30 seconds..."

sudo shutdown -h +0

;;

reboot)

echo "Reboot"

"$PROJECT/scripts/healthcheck.sh" || true

sudo reboot

;;

status)

uptime

;;

*)

echo "Usage:"

echo " power.sh off"

echo " power.sh reboot"

echo " power.sh status"

;;

esac
