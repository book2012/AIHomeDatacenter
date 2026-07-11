#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

CONFIG_FILE="${PROJECT_ROOT}/config/storage-agent.env"
AGENT="${PROJECT_ROOT}/agents/storage-agent/storage-agent.sh"

if [[ ! -r "${CONFIG_FILE}" ]]; then
    echo "Storage Agent config not found: ${CONFIG_FILE}" >&2
    exit 1
fi

set -a
source "${CONFIG_FILE}"
set +a

SCAN_NAME="${1:-test}"
SCAN_PATH=""
SCAN_ENABLED="false"

case "${SCAN_NAME}" in
    test)
        SCAN_PATH="${SCAN_ROOT_TEST}"
        SCAN_ENABLED="${ENABLE_SCAN_TEST}"
        ;;

    platform)
        SCAN_PATH="${SCAN_ROOT_PLATFORM}"
        SCAN_ENABLED="${ENABLE_SCAN_PLATFORM}"
        ;;

    archive)
        SCAN_PATH="${SCAN_ROOT_ARCHIVE}"
        SCAN_ENABLED="${ENABLE_SCAN_ARCHIVE}"
        ;;

    *)
        echo "Unknown scan root: ${SCAN_NAME}" >&2
        echo "Available roots: test, platform, archive" >&2
        exit 2
        ;;
esac

if [[ "${SCAN_ENABLED}" != "true" ]]; then
    echo "Scan root is disabled: ${SCAN_NAME}" >&2
    exit 3
fi

if [[ ! -d "${SCAN_PATH}" ]]; then
    echo "Scan directory not found: ${SCAN_PATH}" >&2
    exit 4
fi

exec "${AGENT}" scan "${SCAN_PATH}"
