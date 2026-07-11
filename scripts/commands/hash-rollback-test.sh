#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/hash-rollback-test.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-rollback-test-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-rollback-test.json"

mkdir -p "${TEST_DIR}" "${REPORT_DIR}"

if [[ ! -f "${SOURCE_DB}" ]]; then
    echo "Source database not found: ${SOURCE_DB}" >&2
    exit 1
fi

rm -f \
    "${TEST_DB}" \
    "${TEST_DB}-wal" \
    "${TEST_DB}-shm"

python3 - \
    "${SOURCE_DB}" \
    "${TEST_DB}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


source_path = Path(sys.argv[1]).resolve()
test_path = Path(sys.argv[2]).resolve()
report_path = Path(sys.argv[3]).resolve()

source = sqlite3.connect(source_path)
target = sqlite3.connect(test_path)

try:
    source.backup(target)
finally:
    target.close()
    source.close()

connection = sqlite3.connect(test_path)
connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")

candidate = connection.execute(
    """
    SELECT
        id,
        path,
        sha256,
        hash_status,
        hash_updated_at
    FROM files
    WHERE hash_status = 'pending'
      AND (
          sha256 IS NULL
          OR length(trim(sha256)) = 0
      )
      AND is_missing = 0
    ORDER BY id
    LIMIT 1
    """
).fetchone()

if candidate is None:
    connection.close()
    raise SystemExit("No pending candidate found for rollback test.")

before = dict(candidate)
intentional_error = None
rollback_executed = False

try:
    connection.execute("BEGIN IMMEDIATE")

    connection.execute(
        """
        UPDATE files
        SET sha256 = ?,
            hash_status = 'done',
            hash_updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
        """,
        (
            "f" * 64,
            candidate["id"],
        ),
    )

    raise RuntimeError(
        "intentional rollback verification failure"
    )

except Exception as error:
    intentional_error = (
        f"{type(error).__name__}: {error}"
    )
    connection.rollback()
    rollback_executed = True

after = connection.execute(
    """
    SELECT
        id,
        path,
        sha256,
        hash_status,
        hash_updated_at
    FROM files
    WHERE id = ?
    """,
    (candidate["id"],),
).fetchone()

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

connection.close()

after_data = dict(after)

record_unchanged = (
    before["sha256"] == after_data["sha256"]
    and before["hash_status"]
        == after_data["hash_status"]
    and before["hash_updated_at"]
        == after_data["hash_updated_at"]
)

payload = {
    "mode": "copied-database-rollback-test",
    "source_database": str(source_path),
    "test_database": str(test_path),
    "candidate": {
        "file_id": before["id"],
        "path": before["path"],
    },
    "before": before,
    "after": after_data,
    "intentional_error": intentional_error,
    "rollback_executed": rollback_executed,
    "record_unchanged": record_unchanged,
    "database_integrity": integrity,
    "source_database_modified": False,
    "test_passed": (
        rollback_executed
        and record_unchanged
        and integrity == "ok"
    ),
}

report_path.write_text(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)

print(
    json.dumps(
        {
            "rollback_executed":
                payload["rollback_executed"],
            "record_unchanged":
                payload["record_unchanged"],
            "database_integrity":
                payload["database_integrity"],
            "source_database_modified":
                payload["source_database_modified"],
            "test_passed":
                payload["test_passed"],
        },
        ensure_ascii=False,
        indent=2,
    )
)

if not payload["test_passed"]:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
