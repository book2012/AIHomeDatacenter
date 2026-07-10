#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT="${PROJECT_ROOT:-/opt/aihomedatacenter}"
RUNTIME_CONFIG="${PROJECT_ROOT}/config/runtime.env"

if [[ -r "${RUNTIME_CONFIG}" ]]; then
    set -a
    source "${RUNTIME_CONFIG}"
    set +a
fi
REPORT_ROOT="${PROJECT_ROOT}/reports"
LOG_ROOT="${PROJECT_ROOT}/logs"

readonly PROJECT_ROOT
readonly REPORT_ROOT
readonly LOG_ROOT

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

file_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

log_info() {
    printf '[%s] INFO  %s\n' "$(timestamp)" "$*"
}

log_warn() {
    printf '[%s] WARN  %s\n' "$(timestamp)" "$*" >&2
}

log_error() {
    printf '[%s] ERROR %s\n' "$(timestamp)" "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ensure_directory() {
    local directory="$1"
    mkdir -p "${directory}"
}

write_latest_link() {
    local report_file="$1"
    local latest_link="$2"

    ln -sfn "${report_file}" "${latest_link}"
}

run_optional() {
    local description="$1"
    shift

    printf '\n## %s\n\n' "${description}"

    if "$@"; then
        return 0
    fi

    local exit_code=$?
    printf 'Command failed with exit code %s\n' "${exit_code}"
    return 0
}
