#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"

source "${SCRIPT_ROOT}/common.sh"

INVENTORY_ROOT="${INVENTORY_ROOT:-/mnt/storage/Inventory}"
REPORT_DIRECTORY="${REPORT_ROOT}/inventory"
REPORT_FILE="${REPORT_DIRECTORY}/inventory-$(file_timestamp).md"
LATEST_LINK="${REPORT_DIRECTORY}/latest.md"

ensure_directory "${INVENTORY_ROOT}"
ensure_directory "${REPORT_DIRECTORY}"

print_storage_layout() {
    if command_exists tree; then
        timeout 10s tree -L 2 "${STORAGE_ROOT}" 2>&1 || \
            printf 'Storage layout timed out or failed.\n'
    else
        find "${STORAGE_ROOT}" \
            -mindepth 1 \
            -maxdepth 2 \
            -type d \
            -print \
            2>/dev/null |
        sort || true
    fi
}

print_recent_files() {
    local title="$1"
    local path="$2"

    printf '\n## %s\n\n' "${title}"

    if [[ ! -d "${path}" ]]; then
        printf 'Directory not found: `%s`\n' "${path}"
        return
    fi

    find "${path}" \
        -maxdepth 2 \
        -type f \
        -printf '%TY-%Tm-%Td %TH:%TM | %p\n' \
        2>/dev/null |
    sort -r |
    head -n 20 || true
}

main() {
    {
        printf '# AI Home Datacenter Inventory\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        printf '\n## Disk Usage\n\n'
        printf '```text\n'
        df -hT 2>&1 || true
        printf '```\n'

        printf '\n## Storage Layout\n\n'
        printf '```text\n'
        print_storage_layout
        printf '```\n'

        print_recent_files \
            "Recent Audit Files" \
            "${INVENTORY_ROOT}/audit"

        print_recent_files \
            "Recent Nextcloud Logs" \
            "${INVENTORY_ROOT}/nextcloud"

        print_recent_files \
            "Recent Hash Reports" \
            "${INVENTORY_ROOT}/hash"
    } | tee "${REPORT_FILE}"

    cp "${REPORT_FILE}" "${INVENTORY_ROOT}/index.md"
    write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

    log_info "Inventory 인덱스 생성 완료: ${REPORT_FILE}"
}

main "$@"
