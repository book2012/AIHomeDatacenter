#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

CONFIG_FILE="${PROJECT_ROOT}/config/storage-agent.env"
PILOT_CONFIG="${PROJECT_ROOT}/config/archive-pilot.env"
REPORT_DIR="${PROJECT_ROOT}/reports/archive"
REPORT_FILE="${REPORT_DIR}/pilot-plan-$(date '+%Y%m%d-%H%M%S').txt"
LATEST_LINK="${REPORT_DIR}/latest-pilot-plan.txt"

if [[ -r "${CONFIG_FILE}" ]]; then
    set -a
    source "${CONFIG_FILE}"
    set +a
fi

ARCHIVE_ROOT="${SCAN_ROOT_ARCHIVE:-/mnt/storage/Archive}"

if [[ ! -d "${ARCHIVE_ROOT}" ]]; then
    echo "Archive root not found: ${ARCHIVE_ROOT}" >&2
    exit 1
fi

select_candidate() {
    local preferred=(
        "Import"
        "Documents"
        "Works"
        "Record"
        "Cartoon"
        "Share_Movies"
    )

    local name

    for name in "${preferred[@]}"; do
        if [[ -d "${ARCHIVE_ROOT}/${name}" ]]; then
            printf '%s\n' "${ARCHIVE_ROOT}/${name}"
            return
        fi
    done

    find "${ARCHIVE_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        ! -name "Immich" \
        ! -name "Nextcloud" \
        -print \
        2>/dev/null |
    sort |
    head -n 1
}

PILOT_ROOT="$(select_candidate)"

if [[ -z "${PILOT_ROOT}" ]]; then
    echo "No Archive pilot candidate found." >&2
    exit 1
fi

DIRECT_FILES="$(
    find "${PILOT_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -print \
        2>/dev/null |
    wc -l
)"

DIRECT_DIRS="$(
    find "${PILOT_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -print \
        2>/dev/null |
    wc -l
)"

cat > "${PILOT_CONFIG}" <<CONFIG
ARCHIVE_PILOT_ROOT="${PILOT_ROOT}"
ENABLE_ARCHIVE_PILOT="false"
ARCHIVE_PILOT_MAX_FILES="1000"
ARCHIVE_PILOT_TIMEOUT_SECONDS="60"
CONFIG

{
    echo "# AI Home Datacenter Archive Pilot Plan"
    echo
    echo "Generated: $(date --iso-8601=seconds)"
    echo "Archive root: ${ARCHIVE_ROOT}"
    echo "Pilot candidate: ${PILOT_ROOT}"
    echo "Direct files: ${DIRECT_FILES}"
    echo "Direct directories: ${DIRECT_DIRS}"
    echo "Pilot enabled: false"
    echo "Maximum pilot files: 1000"
    echo "Pilot timeout: 60 seconds"
    echo
    echo "## Direct Children"
    find "${PILOT_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -printf '%y | %f\n' \
        2>/dev/null |
    sort |
    head -n 100
    echo
    echo "## Safety"
    echo "Archive full scan remains disabled."
    echo "Pilot scan remains disabled."
    echo "No file content was read."
    echo "No file was modified."
} | tee "${REPORT_FILE}"

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo
echo "Pilot config: ${PILOT_CONFIG}"
