#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"

source "${SCRIPT_ROOT}/common.sh"

BACKUP_ROOT="${BACKUP_ROOT:-/mnt/storage/Backup}"
REPORT_DIRECTORY="${REPORT_ROOT}/backup"
REPORT_FILE="${REPORT_DIRECTORY}/backup-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"

section() {
    local title="$1"

    printf '\n'
    printf '========================================\n'
    printf '%s\n' "${title}"
    printf '========================================\n\n'
}

print_backup_root() {
    section "Backup Root"

    printf 'Path: %s\n' "${BACKUP_ROOT}"

    if [[ ! -e "${BACKUP_ROOT}" ]]; then
        printf 'Status: not-found\n'
        return
    fi

    printf 'Status: available\n'

    if [[ -r "${BACKUP_ROOT}" ]]; then
        printf 'Readable: yes\n'
    else
        printf 'Readable: no\n'
    fi

    if [[ -w "${BACKUP_ROOT}" ]]; then
        printf 'Writable: yes\n'
    else
        printf 'Writable: no\n'
    fi
}

print_filesystem() {
    section "Backup Filesystem"

    if [[ ! -e "${BACKUP_ROOT}" ]]; then
        printf 'Backup root not found.\n'
        return
    fi

    df -hT "${BACKUP_ROOT}" 2>&1 || true

    if command_exists findmnt; then
        printf '\nMount information:\n'
        findmnt -T "${BACKUP_ROOT}" 2>&1 || true
    fi
}

print_usage_warning() {
    section "Backup Usage Warning"

    if [[ ! -e "${BACKUP_ROOT}" ]]; then
        printf 'Status: UNKNOWN\n'
        return
    fi

    local usage

    usage="$(
        df -P "${BACKUP_ROOT}" 2>/dev/null |
        awk 'NR == 2 {
            value = $5
            gsub("%", "", value)
            print value
        }'
    )"

    if [[ -z "${usage}" ]]; then
        printf 'Status: UNKNOWN\n'
    elif (( usage >= 90 )); then
        printf 'Usage: %s%%\n' "${usage}"
        printf 'Status: CRITICAL\n'
    elif (( usage >= 80 )); then
        printf 'Usage: %s%%\n' "${usage}"
        printf 'Status: WARNING\n'
    else
        printf 'Usage: %s%%\n' "${usage}"
        printf 'Status: OK\n'
    fi
}

print_directories() {
    section "Backup Directories"

    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        printf 'Backup root not found.\n'
        return
    fi

    find "${BACKUP_ROOT}" \
        -mindepth 1 \
        -maxdepth 2 \
        -type d \
        -printf '%p\n' \
        2>/dev/null |
    sort |
    head -n 100 || true
}

print_recent_files() {
    section "Recent Backup Files"

    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        printf 'Backup root not found.\n'
        return
    fi

    find "${BACKUP_ROOT}" \
        -maxdepth 4 \
        -type f \
        -printf '%T@|%TY-%Tm-%Td %TH:%TM|%s|%p\n' \
        2>/dev/null |
    sort -t'|' -k1,1nr |
    head -n 30 |
    cut -d'|' -f2- || true
}

print_recent_logs() {
    section "Recent Backup Logs"

    local log_paths=(
        "${BACKUP_ROOT}/logs"
        "${BACKUP_ROOT}/owncloud_backup"
        "/opt/aihomedatacenter/logs"
    )

    local path
    local found=0

    for path in "${log_paths[@]}"; do
        [[ -d "${path}" ]] || continue

        find "${path}" \
            -maxdepth 3 \
            -type f \
            \( -name '*.log' -o -name '*.txt' \) \
            -printf '%T@|%TY-%Tm-%Td %TH:%TM|%p\n' \
            2>/dev/null |
        sort -t'|' -k1,1nr |
        head -n 20 |
        cut -d'|' -f2- || true

        found=1
    done

    if [[ "${found}" -eq 0 ]]; then
        printf 'No backup log directories found.\n'
    fi
}

print_expected_paths() {
    section "Expected Backup Paths"

    local paths=(
        "/mnt/storage/Backup"
        "/mnt/storage/Backup/owncloud_backup"
        "/mnt/storage/Backup/logs"
    )

    local path

    for path in "${paths[@]}"; do
        if [[ -e "${path}" ]]; then
            printf 'OK       %s\n' "${path}"
        else
            printf 'MISSING  %s\n' "${path}"
        fi
    done
}

main() {
    {
        printf '# AI Home Datacenter Backup Status\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        print_backup_root
        print_filesystem
        print_usage_warning
        print_expected_paths
        print_directories
        print_recent_files
        print_recent_logs
    } | tee "${REPORT_FILE}"

    write_latest_link \
        "${REPORT_FILE}" \
        "${LATEST_LINK}"

    log_info \
        "Backup 상태 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
