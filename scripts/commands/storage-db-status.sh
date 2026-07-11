#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

AGENT="${PROJECT_ROOT}/agents/storage-agent/storage-agent.sh"
REPORT_DIRECTORY="${PROJECT_ROOT}/reports/storage-agent"
REPORT_FILE="${REPORT_DIRECTORY}/storage-db-status-$(date '+%Y%m%d-%H%M%S').json"
LATEST_LINK="${REPORT_DIRECTORY}/latest.json"

mkdir -p "${REPORT_DIRECTORY}"

if [[ ! -x "${AGENT}" ]]; then
    echo "Storage Agent executable not found: ${AGENT}" >&2
    exit 1
fi

"${AGENT}" db-status | tee "${REPORT_FILE}"

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
