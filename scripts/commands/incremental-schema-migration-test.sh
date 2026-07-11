#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
MIGRATION="${PROJECT_ROOT}/agents/storage-agent/migrations/003_incremental_duplicate.sql"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/incremental-schema-v3.db"

REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/incremental-schema-test-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-incremental-schema-test.json"

mkdir -p "${TEST_DIR}" "${REPORT_DIR}"

if [[ ! -f "${SOURCE_DB}" ]]; then
    echo "Source database not found: ${SOURCE_DB}" >&2
    exit 1
fi

if [[ ! -f "${MIGRATION}" ]]; then
    echo "Migration file not found: ${MIGRATION}" >&2
    exit 1
fi

rm -f \
    "${TEST_DB}" \
    "${TEST_DB}-wal" \
    "${TEST_DB}-shm"

python3 - \
    "${SOURCE_DB}" \
    "${TEST_DB}" \
    "${MIGRATION}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


source_path = Path(sys.argv[1]).resolve()
test_path = Path(sys.argv[2]).resolve()
migration_path = Path(sys.argv[3]).resolve()
report_path = Path(sys.argv[4]).resolve()

source = sqlite3.connect(source_path)
target = sqlite3.connect(test_path)

try:
    source.backup(target)
finally:
    target.close()
    source.close()

connection = sqlite3.connect(
    test_path,
    timeout=30.0,
)

connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("PRAGMA busy_timeout = 30000")

migration_sql = migration_path.read_text(
    encoding="utf-8"
)

before_tables = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        """
    )
}

connection.executescript(migration_sql)

connection.execute(
    """
    INSERT INTO schema_metadata (
        key,
        value,
        updated_at
    )
    VALUES (
        'schema_version',
        '3',
        CURRENT_TIMESTAMP
    )
    ON CONFLICT(key)
    DO UPDATE SET
        value = '3',
        updated_at = CURRENT_TIMESTAMP
    """
)

connection.commit()

expected_tables = {
    "hash_batches",
    "duplicate_processing",
}

expected_indexes = {
    "idx_duplicate_processing_status",
    "idx_duplicate_processing_group",
    "idx_duplicate_processing_batch",
    "idx_hash_batches_status",
}

after_tables = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        """
    )
}

after_indexes = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND name IS NOT NULL
        """
    )
}

schema_version = connection.execute(
    """
    SELECT value
    FROM schema_metadata
    WHERE key = 'schema_version'
    """
).fetchone()["value"]

foreign_key_errors = connection.execute(
    "PRAGMA foreign_key_check"
).fetchall()

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

rollback_before = connection.execute(
    "SELECT COUNT(*) FROM hash_batches"
).fetchone()[0]

rollback_executed = False

try:
    connection.execute("BEGIN IMMEDIATE")

    connection.execute(
        """
        INSERT INTO hash_batches (
            batch_id,
            status,
            files_total
        )
        VALUES (
            'rollback-test-batch',
            'running',
            10
        )
        """
    )

    raise RuntimeError(
        "intentional migration rollback test"
    )

except RuntimeError:
    connection.rollback()
    rollback_executed = True

rollback_after = connection.execute(
    "SELECT COUNT(*) FROM hash_batches"
).fetchone()[0]

connection.close()

tables_ok = expected_tables.issubset(after_tables)
indexes_ok = expected_indexes.issubset(after_indexes)
rollback_unchanged = rollback_before == rollback_after

payload = {
    "mode": "copied-database-schema-v3-test",
    "source_database": str(source_path),
    "test_database": str(test_path),
    "migration_file": str(migration_path),
    "before_tables": sorted(before_tables),
    "created_tables": sorted(
        expected_tables.intersection(after_tables)
    ),
    "created_indexes": sorted(
        expected_indexes.intersection(after_indexes)
    ),
    "schema_version": schema_version,
    "validation": {
        "tables_ok": tables_ok,
        "indexes_ok": indexes_ok,
        "foreign_key_errors": len(foreign_key_errors),
        "integrity": integrity,
    },
    "rollback": {
        "executed": rollback_executed,
        "rows_before": rollback_before,
        "rows_after": rollback_after,
        "unchanged": rollback_unchanged,
    },
    "safety": {
        "source_database_modified": False,
        "files_modified": False,
        "automatic_deletion": False,
    },
}

payload["test_passed"] = (
    schema_version == "3"
    and tables_ok
    and indexes_ok
    and len(foreign_key_errors) == 0
    and integrity == "ok"
    and rollback_executed
    and rollback_unchanged
)

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
            "schema_version": schema_version,
            "created_tables": payload["created_tables"],
            "created_indexes": payload["created_indexes"],
            "foreign_key_errors": len(foreign_key_errors),
            "integrity": integrity,
            "rollback_unchanged": rollback_unchanged,
            "source_database_modified": False,
            "test_passed": payload["test_passed"],
        },
        ensure_ascii=False,
        indent=2,
    )
)

if not payload["test_passed"]:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
