#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_DIR="${SCRIPT_ROOT}/commands"

usage() {
    local exit_code="${1:-0}"

    cat <<'USAGE'

AI Home Datacenter Runtime

Usage:
  runtime.sh <command> [arguments]
  runtime.sh list
  runtime.sh help

Commands:
USAGE

    if [[ -d "${COMMAND_DIR}" ]]; then
        find "${COMMAND_DIR}" \
            -maxdepth 1 \
            -type f \
            -name '*.sh' \
            -perm -u+x \
            -printf '%f\n' \
            2>/dev/null |
        sed 's/\.sh$//' |
        sort |
        sed 's/^/  /'
    else
        printf '  No command directory found.\n'
    fi

    printf '\n'

    exit "${exit_code}"
}

list_commands() {
    if [[ ! -d "${COMMAND_DIR}" ]]; then
        printf 'Command directory not found: %s\n' \
            "${COMMAND_DIR}" >&2
        return 1
    fi

    find "${COMMAND_DIR}" \
        -maxdepth 1 \
        -type f \
        -name '*.sh' \
        -perm -u+x \
        -printf '%f\n' \
        2>/dev/null |
    sed 's/\.sh$//' |
    sort
}

validate_command_name() {
    local command_name="$1"

    [[ "${command_name}" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

main() {
    local command_name="${1:-help}"
    local target

    case "${command_name}" in
        help|-h|--help)
            usage 0
            ;;

        list|--list)
            list_commands
            return
            ;;
    esac

    if ! validate_command_name "${command_name}"; then
        printf 'Invalid command name: %s\n' \
            "${command_name}" >&2
        usage 2
    fi

    target="${COMMAND_DIR}/${command_name}.sh"

    if [[ ! -f "${target}" ]]; then
        printf 'Unknown command: %s\n' \
            "${command_name}" >&2
        usage 2
    fi

    if [[ ! -x "${target}" ]]; then
        printf 'Command is not executable: %s\n' \
            "${target}" >&2
        return 126
    fi

    shift

    exec "${target}" "$@"
}

main "$@"
