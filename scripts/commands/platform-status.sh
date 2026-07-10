#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMAND_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/platform"
REPORT_FILE="${REPORT_DIRECTORY}/platform-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

{
    printf '# AI Home Datacenter Platform Status\n\n'
    printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
    printf 'Hostname: %s\n' "$(hostname)"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'Architecture: %s\n' "$(uname -m)"
    printf '\n'

    printf '## Uptime\n\n'
    uptime || true

    printf '\n## Memory\n\n'
    free -h || true

    printf '\n## Root Filesystem\n\n'
    df -h / || true

    printf '\n## Load Average\n\n'
    if [[ -r /proc/loadavg ]]; then
        cat /proc/loadavg
    else
        printf 'Unavailable\n'
    fi

    printf '\n## Docker Service\n\n'
    if command_exists systemctl; then
        systemctl is-active docker 2>/dev/null || true
    else
        printf 'systemctl unavailable\n'
    fi

    printf '\n## SSH Service\n\n'
    if command_exists systemctl; then
        systemctl is-active ssh 2>/dev/null \
            || systemctl is-active sshd 2>/dev/null \
            || true
    else
        printf 'systemctl unavailable\n'
    fi
} | tee "${REPORT_FILE}"

write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

log_info "플랫폼 상태 리포트 생성 완료: ${REPORT_FILE}"
