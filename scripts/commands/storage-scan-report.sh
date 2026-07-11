#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
SCAN_NAME="${1:-test}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/scan-${SCAN_NAME}-${TIMESTAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-scan.json"

mkdir -p "${REPORT_DIR}"

"${COMMAND_DIR}/storage-scan.sh" "${SCAN_NAME}" |
    tee "${REPORT_FILE}"

python3 -m json.tool "${REPORT_FILE}" >/dev/null

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Storage scan report: ${REPORT_FILE}" >&2
