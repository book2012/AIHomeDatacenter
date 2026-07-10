#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMAND_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/summary"
REPORT_FILE="${REPORT_DIRECTORY}/summary-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

COMMANDS=(
    "platform-status"
    "docker-status"
    "disk-status"
    "git-status"
    "service-status"
    "inventory-index"
    "backup-status"
)

run_report() {
    local command_name="$1"
    local script_path="${COMMAND_DIR}/${command_name}.sh"
    local started_at
    local finished_at
    local elapsed
    local exit_code
    local status

    started_at="$(date +%s)"

    if [[ ! -x "${script_path}" ]]; then
        printf '%-20s %-10s %-10s %s\n' \
            "${command_name}" \
            "MISSING" \
            "-" \
            "${script_path}"

        return 1
    fi

    if timeout 30s "${script_path}" >/dev/null 2>&1; then
        exit_code=0
        status="OK"
    else
        exit_code=$?

        if [[ "${exit_code}" -eq 124 ]]; then
            status="TIMEOUT"
        else
            status="FAILED"
        fi
    fi

    finished_at="$(date +%s)"
    elapsed="$((finished_at - started_at))"

    printf '%-20s %-10s %-10s %s\n' \
        "${command_name}" \
        "${status}" \
        "${elapsed}s" \
        "exit=${exit_code}"

    [[ "${exit_code}" -eq 0 ]]
}

main() {
    local total_started
    local total_finished
    local total_elapsed
    local success_count=0
    local failure_count=0
    local command_name

    total_started="$(date +%s)"

    {
        printf '# AI Home Datacenter Integrated Report\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"
        printf '\n'

        printf '%-20s %-10s %-10s %s\n' \
            "COMMAND" \
            "STATUS" \
            "TIME" \
            "DETAIL"

        printf '%-20s %-10s %-10s %s\n' \
            "--------------------" \
            "----------" \
            "----------" \
            "--------------------"

        for command_name in "${COMMANDS[@]}"; do
            if run_report "${command_name}"; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        done

        total_finished="$(date +%s)"
        total_elapsed="$((total_finished - total_started))"

        printf '\n'
        printf 'Success: %s\n' "${success_count}"
        printf 'Failed: %s\n' "${failure_count}"
        printf 'Total: %s\n' "${#COMMANDS[@]}"
        printf 'Elapsed: %ss\n' "${total_elapsed}"

        if [[ "${failure_count}" -eq 0 ]]; then
            printf 'Overall status: HEALTHY\n'
        else
            printf 'Overall status: ATTENTION\n'
        fi
    } | tee "${REPORT_FILE}"

    write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

    log_info "통합 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
