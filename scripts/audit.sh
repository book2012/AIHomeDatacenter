#!/usr/bin/env bash

set -u

AUDIT_DIR="$HOME/audit"
REPORT="$AUDIT_DIR/ubuntu_audit_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$AUDIT_DIR"

run_section() {
  local title="$1"
  shift

  echo
  echo "====================================================="
  echo "$title"
  echo "====================================================="

  "$@" 2>&1 || true
}

{
echo "AI HOME DATACENTER - UBUNTU AUDIT"
echo "Generated: $(date)"
echo "Host: $(hostname)"
echo

run_section "HOSTNAMECTL" hostnamectl
run_section "OS RELEASE" lsb_release -a
run_section "KERNEL" uname -a
run_section "CPU" lscpu
run_section "MEMORY" free -h

run_section "BLOCK DEVICES" lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT
run_section "FILESYSTEM USAGE" df -hT
run_section "MOUNTS" mount
run_section "FSTAB" cat /etc/fstab

run_section "DOCKER CONTAINERS" docker ps -a
run_section "DOCKER IMAGES" docker images
run_section "DOCKER VOLUMES" docker volume ls
run_section "DOCKER NETWORKS" docker network ls
run_section "DOCKER DISK USAGE" docker system df

run_section "COMPOSE FILES" find /opt/aihomedatacenter/compose -name compose.yml

run_section "ENABLED SERVICES" systemctl list-unit-files --type=service --state=enabled
run_section "RUNNING SERVICES" systemctl --type=service --state=running

run_section "APACHE STATUS" systemctl status apache2 --no-pager
run_section "APACHE VHOSTS" apache2ctl -S

run_section "NGINX STATUS" systemctl status nginx --no-pager

run_section "PHP VERSION" php -v
run_section "PHP MODULES" php -m

run_section "MARIADB STATUS" systemctl status mariadb --no-pager
run_section "MYSQL STATUS" systemctl status mysql --no-pager
run_section "POSTGRESQL STATUS" systemctl status postgresql --no-pager

run_section "WORDPRESS CONFIGS" find /var/www /opt /srv -name wp-config.php
run_section "OWNCLOUD PATHS" find /var/www /opt /srv -iname "*owncloud*"

run_section "USER CRON" crontab -l
run_section "SYSTEM CRON" ls -lah /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly

run_section "NETWORK ADDR" ip addr
run_section "NETWORK ROUTE" ip route
run_section "LISTENING PORTS" ss -tulpn
run_section "UFW STATUS" ufw status

run_section "STORAGE TREE" tree -L 3 /mnt/storage
run_section "STORAGE USAGE" du -h --max-depth=2 /mnt/storage

run_section "OPT TREE" tree -L 3 /opt
run_section "AIHOMEDATACENTER TREE" tree -L 4 /opt/aihomedatacenter
run_section "HOME TREE" tree -L 2 /home/han

run_section "ENV FILES" find /opt/aihomedatacenter -name ".env"

run_section "LARGE DIRECTORIES ROOT" bash -c 'du -xh / 2>/dev/null | sort -h | tail -80'

} > "$REPORT" 2>&1

echo "Audit completed:"
echo "$REPORT"
