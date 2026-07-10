#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMAND_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/disk"
REPORT_FILE="${REPORT_DIRECTORY}/disk-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

section() {
    local title="$1"

    printf '\n'
    printf '========================================\n'
    printf '%s\n'
    printf '========================================\n\n'
}

print_filesystem_usage() {
    section "Filesystem Usage"

    df -hT 2>&1 || true
}

print_disk_warnings() {
    section "Filesystem Warnings"

    df -P 2>/dev/null |
    awk '
        NR == 1 {
            printf "%-36s %-10s %s\n",
                "MOUNTPOINT", "USAGE", "STATUS"
            next
        }

        {
            usage = $5
            mountpoint = $6
            gsub("%", "", usage)

            if (usage + 0 >= 90) {
                status = "CRITICAL"
            } else if (usage + 0 >= 80) {
                status = "WARNING"
            } else {
                status = "OK"
            }

            printf "%-36s %-10s %s\n",
                mountpoint, usage "%", status
        }
    ' || true
}

print_inode_usage() {
    section "Inode Usage"

    df -hi 2>&1 || true
}

print_block_devices() {
    section "Block Devices"

    if ! command_exists lsblk; then
        printf 'lsblk: unavailable\n'
        return
    fi

    lsblk \
        -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL \
        2>&1 || true
}

print_physical_disks() {
    section "Physical Disks"

    if ! command_exists lsblk; then
        printf 'lsblk: unavailable\n'
        return
    fi

    lsblk \
        --nodeps \
        -o NAME,PATH,SIZE,MODEL,TRAN,ROTA,TYPE \
        2>&1 || true
}

print_path_status() {
    local path="$1"

    printf '\nPath: %s\n' "${path}"

    if [[ ! -e "${path}" ]]; then
        printf 'Status: not-found\n'
        return
    fi

    printf 'Status: available\n'

    if [[ -r "${path}" ]]; then
        printf 'Readable: yes\n'
    else
        printf 'Readable: no\n'
    fi

    if [[ -w "${path}" ]]; then
        printf 'Writable: yes\n'
    else
        printf 'Writable: no\n'
    fi

    printf 'Filesystem:\n'
    df -hT "${path}" 2>&1 || true

    if command_exists findmnt; then
        printf 'Mount:\n'
        findmnt -T "${path}" 2>&1 || true
    fi
}

print_key_paths() {
    section "Key Paths"

    print_path_status "/opt/aihomedatacenter"
    print_path_status "/var/lib/docker"
    print_path_status "/mnt/storage"
    print_path_status "/mnt/storage/Archive"
}

print_mounts() {
    section "Mounted Filesystems"

    if command_exists findmnt; then
        findmnt \
            -o TARGET,SOURCE,FSTYPE,OPTIONS \
            2>&1 || true
    else
        mount 2>&1 || true
    fi
}

print_smart_tool_status() {
    section "SMART Tool Status"

    if command_exists smartctl; then
        printf 'smartctl: installed\n'
        smartctl --version 2>&1 |
            sed -n '1,3p' || true
    else
        printf 'smartctl: not-installed\n'
    fi
}

main() {
    {
        printf '# AI Home Datacenter Disk Status\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        print_filesystem_usage
        print_disk_warnings
        print_inode_usage
        print_block_devices
        print_physical_disks
        print_key_paths
        print_mounts
        print_smart_tool_status
    } | tee "${REPORT_FILE}"

    write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

    log_info "Disk 상태 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
