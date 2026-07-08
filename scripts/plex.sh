#!/bin/bash
set -euo pipefail

case "${1:-}" in
  start)
    sudo systemctl start plexmediaserver
    ;;
  stop)
    sudo systemctl stop plexmediaserver
    ;;
  restart)
    sudo systemctl restart plexmediaserver
    ;;
  status)
    systemctl status plexmediaserver --no-pager
    ;;
  enable)
    sudo systemctl enable plexmediaserver
    ;;
  disable)
    sudo systemctl disable plexmediaserver
    ;;
  *)
    echo "Usage: plex.sh start|stop|restart|status|enable|disable"
    exit 1
    ;;
esac
