#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT_DIR}/storage-agent-rc-audit-${STAMP}.json"
LATEST="${REPORT_DIR}/latest-storage-agent-rc-audit.json"
TEST_LOG="/tmp/storage-agent-rc-test.log"

mkdir -p "${REPORT_DIR}"

FAILED=0

RUNTIME_COUNT="$(
    "${PROJECT_ROOT}/scripts/runtime.sh" list |
    sed '/^[[:space:]]*$/d' |
    wc -l
)"

COMMAND_COUNT="$(
    find "${PROJECT_ROOT}/scripts/commands" \
        -maxdepth 1 \
        -type f \
        -name '*.sh' |
    wc -l
)"

RUNTIME_MATCH=true

if [[ "${RUNTIME_COUNT}" -ne "${COMMAND_COUNT}" ]]; then
    RUNTIME_MATCH=false
    FAILED=1
fi

BASH_FAILURES=""

while IFS= read -r FILE
do
    if ! bash -n "${FILE}"; then
        BASH_FAILURES+="${FILE}"$'\n'
        FAILED=1
    fi
done < <(
    find \
        "${PROJECT_ROOT}/scripts" \
        "${PROJECT_ROOT}/agents/storage-agent" \
        -type f \
        -name '*.sh' |
    sort
)

PYTHON_FAILURES=""

while IFS= read -r FILE
do
    if ! python3 -m py_compile "${FILE}"; then
        PYTHON_FAILURES+="${FILE}"$'\n'
        FAILED=1
    fi
done < <(
    find "${PROJECT_ROOT}/agents/storage-agent" \
        -type f \
        -name '*.py' |
    sort
)

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

INTEGRITY="$(
    sqlite3 "${DB}" \
        'PRAGMA integrity_check;'
)"

if [[ "${INTEGRITY}" != "ok" ]]; then
    FAILED=1
fi

SCHEMA_VERSION="$(
    sqlite3 "${DB}" "
        SELECT COALESCE(
            (
                SELECT value
                FROM schema_metadata
                WHERE key='schema_version'
            ),
            'unknown'
        );
    "
)"

V3_TABLE_COUNT="$(
    sqlite3 "${DB}" "
        SELECT COUNT(*)
        FROM sqlite_master
        WHERE type='table'
          AND name IN (
              'hash_batches',
              'duplicate_processing'
          );
    "
)"

V3_INDEX_COUNT="$(
    sqlite3 "${DB}" "
        SELECT COUNT(*)
        FROM sqlite_master
        WHERE type='index'
          AND name IN (
              'idx_duplicate_processing_status',
              'idx_duplicate_processing_group',
              'idx_duplicate_processing_batch',
              'idx_hash_batches_status'
          );
    "
)"

SCHEMA_OK=true

if [[ "${SCHEMA_VERSION}" != "3" ]] ||
   [[ "${V3_TABLE_COUNT}" -ne 2 ]] ||
   [[ "${V3_INDEX_COUNT}" -ne 4 ]]; then
    SCHEMA_OK=false
    FAILED=1
fi

FOREIGN_KEY_ERRORS="$(
    sqlite3 "${DB}" \
        'PRAGMA foreign_key_check;' |
    wc -l
)"

if [[ "${FOREIGN_KEY_ERRORS}" -ne 0 ]]; then
    FAILED=1
fi

TEST_STATUS="failed"

if timeout 300s \
    "${PROJECT_ROOT}/scripts/runtime.sh" \
    incremental-duplicate-test-all \
    >"${TEST_LOG}" 2>&1
then
    TEST_STATUS="passed"
else
    FAILED=1
fi

UNSAFE_TRACKED="$(
    git -C "${PROJECT_ROOT}" ls-files |
    grep -E \
    '(^|/)(storage\.db|.*\.db-(wal|shm)|reports/.+\.(json|txt|csv|md)|data/backups/|data/test/)' \
    || true
)"

GIT_SAFETY=true

if [[ -n "${UNSAFE_TRACKED}" ]]; then
    GIT_SAFETY=false
    FAILED=1
fi

POLICY_FILE="${PROJECT_ROOT}/config/incremental-duplicate.env"
POLICY_OK=false

if [[ -f "${POLICY_FILE}" ]] &&
   grep -q '^INCREMENTAL_DUPLICATE_ENABLED="false"$' "${POLICY_FILE}" &&
   grep -q '^INITIAL_BACKFILL_ENABLED="false"$' "${POLICY_FILE}" &&
   grep -q '^MAX_RETRY_COUNT="3"$' "${POLICY_FILE}" &&
   grep -q '^AUTOMATIC_DELETE="false"$' "${POLICY_FILE}" &&
   grep -q '^USER_APPROVAL_REQUIRED="true"$' "${POLICY_FILE}"
then
    POLICY_OK=true
else
    FAILED=1
fi

DOCS_OK=true

for FILE in \
    README.md \
    ARCHITECTURE.md \
    MASTER.md \
    ROADMAP.md \
    TODO.md \
    CHANGELOG.md \
    PROJECT_HISTORY.md \
    docs/STORAGE_AGENT.md
do
    if [[ ! -f "${PROJECT_ROOT}/${FILE}" ]]; then
        DOCS_OK=false
        FAILED=1
    fi
done

UNTRACKED="$(
    git -C "${PROJECT_ROOT}" status --short |
    grep '^??' \
    || true
)"

RC_READY=false

if [[ "${FAILED}" -eq 0 ]]; then
    RC_READY=true
fi

python3 - \
    "${REPORT}" \
    "${RUNTIME_COUNT}" \
    "${COMMAND_COUNT}" \
    "${RUNTIME_MATCH}" \
    "${INTEGRITY}" \
    "${SCHEMA_VERSION}" \
    "${V3_TABLE_COUNT}" \
    "${V3_INDEX_COUNT}" \
    "${FOREIGN_KEY_ERRORS}" \
    "${TEST_STATUS}" \
    "${GIT_SAFETY}" \
    "${POLICY_OK}" \
    "${DOCS_OK}" \
    "${RC_READY}" \
    "${UNSAFE_TRACKED}" \
    "${UNTRACKED}" \
    "${BASH_FAILURES}" \
    "${PYTHON_FAILURES}" <<'PYTHON'
import json
import sys
from pathlib import Path

report = Path(sys.argv[1])

payload = {
    "mode": "storage-agent-release-candidate-audit",
    "runtime": {
        "runtime_commands": int(sys.argv[2]),
        "command_files": int(sys.argv[3]),
        "match": sys.argv[4] == "true",
    },
    "database": {
        "integrity": sys.argv[5],
        "schema_version": sys.argv[6],
        "v3_table_count": int(sys.argv[7]),
        "v3_index_count": int(sys.argv[8]),
        "foreign_key_errors": int(sys.argv[9]),
    },
    "tests": {
        "incremental_duplicate_suite": sys.argv[10],
    },
    "git": {
        "runtime_data_safe": sys.argv[11] == "true",
        "unsafe_tracked": [
            line
            for line in sys.argv[15].splitlines()
            if line.strip()
        ],
        "untracked": [
            line
            for line in sys.argv[16].splitlines()
            if line.strip()
        ],
    },
    "policy": {
        "safe_policy_confirmed": sys.argv[12] == "true",
    },
    "documentation": {
        "required_documents_present": sys.argv[13] == "true",
    },
    "syntax": {
        "bash_failures": [
            line
            for line in sys.argv[17].splitlines()
            if line.strip()
        ],
        "python_failures": [
            line
            for line in sys.argv[18].splitlines()
            if line.strip()
        ],
    },
    "rc_ready": sys.argv[14] == "true",
}

report.write_text(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)

print(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    )
)

if not payload["rc_ready"]:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT}" "${LATEST}"

echo
echo "===== Incremental Test Log ====="

if [[ -f "${TEST_LOG}" ]]; then
    cat "${TEST_LOG}"
else
    echo "Test log not created."
fi

if [[ "${FAILED}" -ne 0 ]]; then
    exit 1
fi
