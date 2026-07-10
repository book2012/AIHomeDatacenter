#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMAND_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/git"
REPORT_FILE="${REPORT_DIRECTORY}/git-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

section() {
    local title="$1"

    printf '\n'
    printf '========================================\n'
    printf '%s\n' "${title}"
    printf '========================================\n\n'
}

repository_available() {
    git -C "${PROJECT_ROOT}" \
        rev-parse \
        --is-inside-work-tree \
        >/dev/null 2>&1
}

print_repository_info() {
    section "Repository"

    printf 'Path: %s\n' "${PROJECT_ROOT}"
    printf 'Top level: '

    git -C "${PROJECT_ROOT}" \
        rev-parse \
        --show-toplevel \
        2>/dev/null || true

    printf 'Current branch: '

    git -C "${PROJECT_ROOT}" \
        branch \
        --show-current \
        2>/dev/null || true

    printf 'Current commit: '

    git -C "${PROJECT_ROOT}" \
        rev-parse \
        --short HEAD \
        2>/dev/null || true
}

print_remotes() {
    section "Remotes"

    git -C "${PROJECT_ROOT}" \
        remote \
        -v \
        2>&1 || true
}

print_upstream_status() {
    section "Upstream Status"

    local upstream
    local counts
    local ahead
    local behind

    upstream="$(
        git -C "${PROJECT_ROOT}" \
            rev-parse \
            --abbrev-ref \
            --symbolic-full-name \
            '@{upstream}' \
            2>/dev/null || true
    )"

    if [[ -z "${upstream}" ]]; then
        printf 'Upstream: not-configured\n'
        return
    fi

    printf 'Upstream: %s\n' "${upstream}"

    counts="$(
        git -C "${PROJECT_ROOT}" \
            rev-list \
            --left-right \
            --count \
            "${upstream}...HEAD" \
            2>/dev/null || true
    )"

    if [[ -z "${counts}" ]]; then
        printf 'Comparison: unavailable\n'
        return
    fi

    behind="$(awk '{print $1}' <<< "${counts}")"
    ahead="$(awk '{print $2}' <<< "${counts}")"

    printf 'Ahead: %s\n' "${ahead}"
    printf 'Behind: %s\n' "${behind}"

    if [[ "${ahead}" -eq 0 && "${behind}" -eq 0 ]]; then
        printf 'Status: synchronized\n'
    elif [[ "${ahead}" -gt 0 && "${behind}" -eq 0 ]]; then
        printf 'Status: local-ahead\n'
    elif [[ "${ahead}" -eq 0 && "${behind}" -gt 0 ]]; then
        printf 'Status: remote-ahead\n'
    else
        printf 'Status: diverged\n'
    fi
}

print_worktree_status() {
    section "Working Tree Status"

    git -C "${PROJECT_ROOT}" \
        status \
        --short \
        --branch \
        2>&1 || true
}

print_staged_changes() {
    section "Staged Changes"

    if git -C "${PROJECT_ROOT}" \
        diff \
        --cached \
        --quiet; then
        printf 'No staged changes.\n'
    else
        git -C "${PROJECT_ROOT}" \
            diff \
            --cached \
            --stat \
            2>&1 || true
    fi
}

print_unstaged_changes() {
    section "Unstaged Changes"

    if git -C "${PROJECT_ROOT}" \
        diff \
        --quiet; then
        printf 'No unstaged changes.\n'
    else
        git -C "${PROJECT_ROOT}" \
            diff \
            --stat \
            2>&1 || true
    fi
}

print_untracked_files() {
    section "Untracked Files"

    local output

    output="$(
        git -C "${PROJECT_ROOT}" \
            ls-files \
            --others \
            --exclude-standard \
            2>/dev/null || true
    )"

    if [[ -z "${output}" ]]; then
        printf 'No untracked files.\n'
    else
        printf '%s\n' "${output}"
    fi
}

print_recent_commits() {
    section "Recent Commits"

    git -C "${PROJECT_ROOT}" \
        log \
        -n 10 \
        --date=iso \
        --pretty=format:'%h | %ad | %an | %s' \
        2>&1 || true

    printf '\n'
}

print_recent_tags() {
    section "Recent Tags"

    local tags

    tags="$(
        git -C "${PROJECT_ROOT}" \
            tag \
            --sort=-creatordate \
            2>/dev/null |
        head -n 10
    )"

    if [[ -z "${tags}" ]]; then
        printf 'No tags found.\n'
    else
        printf '%s\n' "${tags}"
    fi
}

print_repository_size() {
    section "Repository Size"

    git -C "${PROJECT_ROOT}" \
        count-objects \
        -vH \
        2>&1 || true
}

main() {
    {
        printf '# AI Home Datacenter Git Status\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        if ! command_exists git; then
            section "Git Error"
            printf 'Git is not installed.\n'
            exit 0
        fi

        if ! repository_available; then
            section "Git Error"
            printf 'Not a Git repository: %s\n' "${PROJECT_ROOT}"
            exit 0
        fi

        print_repository_info
        print_remotes
        print_upstream_status
        print_worktree_status
        print_staged_changes
        print_unstaged_changes
        print_untracked_files
        print_recent_commits
        print_recent_tags
        print_repository_size
    } | tee "${REPORT_FILE}"

    write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

    log_info "Git 상태 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
