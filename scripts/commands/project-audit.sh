#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

REPORT_DIR="${PROJECT_ROOT}/reports/audit"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/project-audit-${STAMP}.txt"
LATEST_LINK="${REPORT_DIR}/latest-project-audit.txt"

mkdir -p "${REPORT_DIR}"

section() {
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

{
    echo "# AI Home Datacenter Project Audit"
    echo
    echo "Generated: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo "Project: ${PROJECT_ROOT}"

    section "Git Status"
    git -C "${PROJECT_ROOT}" status --short --branch || true

    section "Runtime Commands"
    "${SCRIPT_ROOT}/runtime.sh" list || true

    section "Bash Syntax"
    bash_failures=0

    while IFS= read -r script; do
        if bash -n "${script}"; then
            echo "OK      ${script#${PROJECT_ROOT}/}"
        else
            echo "FAILED  ${script#${PROJECT_ROOT}/}"
            bash_failures=$((bash_failures + 1))
        fi
    done < <(
        find \
            "${PROJECT_ROOT}/scripts" \
            "${PROJECT_ROOT}/agents" \
            -type f \
            -name '*.sh' \
            2>/dev/null |
        sort
    )

    echo "Bash failures: ${bash_failures}"

    section "Python Syntax"
    python_failures=0

    while IFS= read -r file; do
        if python3 -m py_compile "${file}" 2>/dev/null; then
            echo "OK      ${file#${PROJECT_ROOT}/}"
        else
            echo "FAILED  ${file#${PROJECT_ROOT}/}"
            python_failures=$((python_failures + 1))
        fi
    done < <(
        find "${PROJECT_ROOT}/agents" \
            -type f \
            -name '*.py' \
            2>/dev/null |
        sort
    )

    echo "Python failures: ${python_failures}"

    section "Expected Runtime Commands"

    expected_commands=(
        platform-status
        docker-status
        disk-status
        git-status
        service-status
        backup-status
        inventory-index
        report-all
        json-summary
        health-status
        storage-db-init
        storage-db-status
        storage-db-check
        storage-scan
        storage-scan-report
        storage-error-status
        storage-agent-status
        storage-agent-test
        storage-inventory-status
        storage-migration-preview
        duplicate-preview
        duplicate-root-preview
        duplicate-cleanup-preview
        duplicate-validation-preview
        archive-readiness
        archive-pilot-plan
        project-audit
    )

    for command in "${expected_commands[@]}"; do
        file="${PROJECT_ROOT}/scripts/commands/${command}.sh"

        if [[ -x "${file}" ]]; then
            echo "OK       ${command}"
        else
            echo "MISSING  ${command}"
        fi
    done

    section "Expected Core Files"

    expected_files=(
        config/runtime.env
        config/storage-agent.env
        agents/storage-agent/db.py
        agents/storage-agent/scanner.py
        agents/storage-agent/storage-agent.sh
        scripts/runtime.sh
        scripts/common.sh
        docs/UBUNTU_RUNTIME.md
        docs/STORAGE_AGENT.md
        README.md
        MASTER.md
        ARCHITECTURE.md
        ROADMAP.md
        CHANGELOG.md
        TODO.md
    )

    for file in "${expected_files[@]}"; do
        if [[ -e "${PROJECT_ROOT}/${file}" ]]; then
            echo "OK       ${file}"
        else
            echo "MISSING  ${file}"
        fi
    done

    section "Storage Database Protection"

    DB_REL="agents/storage-agent/data/storage.db"
    DB="${PROJECT_ROOT}/${DB_REL}"

    if [[ -f "${DB}" ]]; then
        echo "Database exists: yes"
        ls -lh "${DB}"
        echo
        echo "Integrity:"
        sqlite3 "${DB}" "PRAGMA integrity_check;" || true
        echo
        echo "Git protection:"

        if git -C "${PROJECT_ROOT}" check-ignore -q "${DB_REL}"; then
            echo "IGNORED  ${DB_REL}"
        else
            echo "REVIEW   ${DB_REL} is not ignored"
        fi
    else
        echo "MISSING  ${DB_REL}"
    fi

    section "Runtime Report Ignore Check"

    samples=(
        reports/platform/latest.txt
        reports/docker/latest.txt
        reports/disk/latest.txt
        reports/git/latest.txt
        reports/service/latest.txt
        reports/summary/latest.txt
        reports/summary/latest.json
        reports/storage-agent/latest-status.json
        reports/storage-agent/latest-scan.json
        reports/storage-agent/latest-duplicate-validation.json
    )

    for sample in "${samples[@]}"; do
        if git -C "${PROJECT_ROOT}" check-ignore -q "${sample}"; then
            echo "IGNORED  ${sample}"
        else
            echo "REVIEW   ${sample}"
        fi
    done

    section "Deferred and Temporary Files"

    find "${PROJECT_ROOT}" \
        -type f \
        \( -path '*/deferred/*' \
           -o -name '*.bak.*' \
           -o -name '*.tmp' \
           -o -name '*legacy*' \) \
        -print \
        2>/dev/null |
    sort || true

    section "Document Keyword Check"

    for file in \
        README.md \
        MASTER.md \
        ARCHITECTURE.md \
        ROADMAP.md \
        TODO.md \
        CHANGELOG.md
    do
        path="${PROJECT_ROOT}/${file}"

        if [[ ! -f "${path}" ]]; then
            echo "MISSING  ${file}"
            continue
        fi

        runtime_count="$(
            grep -Eic 'Ubuntu Runtime|runtime.sh' "${path}" || true
        )"

        agent_count="$(
            grep -Eic 'Storage Agent|storage-agent' "${path}" || true
        )"

        control_count="$(
            grep -Eic 'AIControlCenter|Control Center' "${path}" || true
        )"

        printf '%-22s runtime=%-3s storage-agent=%-3s control-center=%-3s\n' \
            "${file}" \
            "${runtime_count}" \
            "${agent_count}" \
            "${control_count}"
    done

    section "Audit Safety"

    echo "Database modified: no"
    echo "Files deleted: no"
    echo "Services restarted: no"
    echo "Archive scanned: no"

} | tee "${REPORT_FILE}"

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo
echo "Project audit report: ${REPORT_FILE}"
