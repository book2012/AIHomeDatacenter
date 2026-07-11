#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

CONFIG_FILE="${PROJECT_ROOT}/config/storage-agent.env"
ARCHIVE_PATH="/mnt/storage/Archive"
REPORT_DIR="${PROJECT_ROOT}/reports/archive"
REPORT_FILE="${REPORT_DIR}/readiness-$(date '+%Y%m%d-%H%M%S').txt"
LATEST_LINK="${REPORT_DIR}/latest-readiness.txt"

mkdir -p "${REPORT_DIR}"

if [[ -r "${CONFIG_FILE}" ]]; then
    set -a
    source "${CONFIG_FILE}"
    set +a
fi

ARCHIVE_PATH="${SCAN_ROOT_ARCHIVE:-${ARCHIVE_PATH}}"
ARCHIVE_ENABLED="${ENABLE_SCAN_ARCHIVE:-false}"

{
    echo "# AI Home Datacenter Archive Readiness"
    echo
    echo "Generated: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo "Archive path: ${ARCHIVE_PATH}"
    echo "Archive scan enabled: ${ARCHIVE_ENABLED}"
    echo

    echo "## Path Status"
    if [[ -d "${ARCHIVE_PATH}" ]]; then
        echo "Exists: yes"
    else
        echo "Exists: no"
    fi

    if [[ -r "${ARCHIVE_PATH}" ]]; then
        echo "Readable: yes"
    else
        echo "Readable: no"
    fi

    if [[ -w "${ARCHIVE_PATH}" ]]; then
        echo "Writable: yes"
    else
        echo "Writable: no"
    fi

    echo
    echo "## Filesystem"
    if [[ -e "${ARCHIVE_PATH}" ]]; then
        df -hT "${ARCHIVE_PATH}" || true
    else
        echo "Archive path unavailable"
    fi

    echo
    echo "## Mount"
    if command -v findmnt >/dev/null 2>&1 &&
       [[ -e "${ARCHIVE_PATH}" ]]; then
        findmnt -T "${ARCHIVE_PATH}" || true
    else
        echo "Mount information unavailable"
    fi

    echo
    echo "## Top-Level Directories"
    if [[ -d "${ARCHIVE_PATH}" ]]; then
        find "${ARCHIVE_PATH}" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' \
            2>/dev/null |
        sort
    else
        echo "Archive path unavailable"
    fi

    echo
    echo "## Safety"
    if [[ "${ARCHIVE_ENABLED}" == "true" ]]; then
        echo "WARNING: Archive scan is enabled"
    else
        echo "OK: Archive scan remains disabled"
    fi
} | tee "${REPORT_FILE}"

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo
echo "Archive readiness report: ${REPORT_FILE}"
