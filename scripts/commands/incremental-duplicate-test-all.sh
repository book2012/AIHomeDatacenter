#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT_DIR}/incremental-duplicate-test-${STAMP}.json"
LATEST="${REPORT_DIR}/latest-incremental-duplicate-test.json"

mkdir -p "${REPORT_DIR}"

db_counts() {
    sqlite3 -separator '|' "${DB}" "
        SELECT
            (SELECT COUNT(*) FROM hash_batches),
            (SELECT COUNT(*) FROM duplicate_processing),
            (SELECT COUNT(*) FROM duplicate_groups),
            (SELECT COUNT(*) FROM duplicate_files);
    "
}

run_test() {
    local command="$1"
    local log_file="$2"

    if "${PROJECT_ROOT}/scripts/commands/${command}.sh" \
        >"${log_file}" 2>&1
    then
        echo "passed"
    else
        echo "failed"
    fi
}

BEFORE="$(db_counts)"

PROCESSING_STATUS="$(
    run_test \
        incremental-duplicate-processing-test \
        /tmp/incremental-processing-test.log
)"

RETRY_STATUS="$(
    run_test \
        incremental-duplicate-retry-test \
        /tmp/incremental-retry-test.log
)"

RETRY_LIMIT_STATUS="$(
    run_test \
        incremental-duplicate-retry-limit-test \
        /tmp/incremental-retry-limit-test.log
)"

AFTER="$(db_counts)"
INTEGRITY="$(sqlite3 "${DB}" 'PRAGMA integrity_check;')"

python3 - \
    "${REPORT}" \
    "${PROCESSING_STATUS}" \
    "${RETRY_STATUS}" \
    "${RETRY_LIMIT_STATUS}" \
    "${BEFORE}" \
    "${AFTER}" \
    "${INTEGRITY}" <<'PYTHON'
import json
import sys
from pathlib import Path

report = Path(sys.argv[1])
processing = sys.argv[2]
retry_resume = sys.argv[3]
retry_limit = sys.argv[4]
before_values = sys.argv[5].split("|")
after_values = sys.argv[6].split("|")
integrity = sys.argv[7]

keys = [
    "hash_batches",
    "duplicate_processing",
    "duplicate_groups",
    "duplicate_files",
]

before = dict(zip(keys, map(int, before_values)))
after = dict(zip(keys, map(int, after_values)))

database_unchanged = before == after

payload = {
    "mode": "incremental-duplicate-automated-test",
    "tests": {
        "processing": processing,
        "retry_resume": retry_resume,
        "retry_limit": retry_limit,
    },
    "operating_database": {
        "before": before,
        "after": after,
        "unchanged": database_unchanged,
        "integrity": integrity,
    },
    "safety": {
        "source_database_modified": not database_unchanged,
        "physical_files_modified": False,
        "automatic_deletion": False,
    },
}

payload["test_passed"] = (
    processing == "passed"
    and retry_resume == "passed"
    and retry_limit == "passed"
    and database_unchanged
    and integrity == "ok"
)

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

if not payload["test_passed"]:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT}" "${LATEST}"

echo
echo "===== Processing Log ====="
cat /tmp/incremental-processing-test.log

echo
echo "===== Retry / Resume Log ====="
cat /tmp/incremental-retry-test.log

echo
echo "===== Retry Limit Log ====="
cat /tmp/incremental-retry-limit-test.log
