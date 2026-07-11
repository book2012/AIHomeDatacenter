#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/duplicate-rebuild.db"

REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/duplicate-rebuild-test-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-duplicate-rebuild-test.json"

mkdir -p "${TEST_DIR}" "${REPORT_DIR}"

rm -f \
  "${TEST_DB}" \
  "${TEST_DB}-wal" \
  "${TEST_DB}-shm"

python3 - \
  "${SOURCE_DB}" \
  "${TEST_DB}" \
  "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
import time
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

connection = sqlite3.connect(
    test_path,
    timeout=60.0,
)

connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("PRAGMA busy_timeout = 60000")
connection.execute("PRAGMA temp_store = MEMORY")

before_groups = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

before_files = connection.execute(
    "SELECT COUNT(*) FROM duplicate_files"
).fetchone()[0]

started = time.monotonic()

try:
    connection.execute("BEGIN IMMEDIATE")

    connection.execute(
        "DELETE FROM duplicate_files"
    )

    connection.execute(
        "DELETE FROM duplicate_groups"
    )

    groups = connection.execute(
        """
        SELECT
            sha256,
            COUNT(*) AS file_count,
            MAX(size_bytes) * COUNT(*) AS total_size_bytes
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) = 64
          AND is_missing = 0
          AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
          AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
        GROUP BY sha256
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT size_bytes) = 1
        """
    ).fetchall()

    inserted_groups = 0
    inserted_files = 0

    for group in groups:
        cursor = connection.execute(
            """
            INSERT INTO duplicate_groups (
                sha256,
                file_count,
                total_size_bytes,
                created_at
            )
            VALUES (
                ?,
                ?,
                ?,
                CURRENT_TIMESTAMP
            )
            """,
            (
                group["sha256"],
                group["file_count"],
                group["total_size_bytes"],
            ),
        )

        group_id = int(cursor.lastrowid)

        file_rows = connection.execute(
            """
            SELECT
                id,
                path,
                size_bytes
            FROM files
            WHERE sha256 = ?
              AND is_missing = 0
              AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
              AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
            ORDER BY id
            """,
            (group["sha256"],),
        ).fetchall()

        if len(file_rows) != group["file_count"]:
            raise RuntimeError(
                "Duplicate group changed during rebuild"
            )

        connection.executemany(
            """
            INSERT INTO duplicate_files (
                duplicate_group_id,
                file_id,
                path,
                size_bytes
            )
            VALUES (?, ?, ?, ?)
            """,
            [
                (
                    group_id,
                    row["id"],
                    row["path"],
                    row["size_bytes"],
                )
                for row in file_rows
            ],
        )

        inserted_groups += 1
        inserted_files += len(file_rows)

    connection.commit()
    rebuild_status = "completed"

except Exception:
    connection.rollback()
    raise

elapsed = round(
    time.monotonic() - started,
    3,
)

after_groups = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

after_files = connection.execute(
    "SELECT COUNT(*) FROM duplicate_files"
).fetchone()[0]

relationship_errors = connection.execute(
    """
    SELECT COUNT(*)
    FROM (
        SELECT
            duplicate_groups.id
        FROM duplicate_groups
        LEFT JOIN duplicate_files
          ON duplicate_files.duplicate_group_id =
             duplicate_groups.id
        GROUP BY duplicate_groups.id
        HAVING duplicate_groups.file_count !=
               COUNT(duplicate_files.id)
    )
    """
).fetchone()[0]

foreign_key_errors = connection.execute(
    "PRAGMA foreign_key_check"
).fetchall()

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

rollback_before = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

rollback_executed = False

try:
    connection.execute("BEGIN IMMEDIATE")

    connection.execute(
        """
        DELETE FROM duplicate_files
        WHERE duplicate_group_id = (
            SELECT id
            FROM duplicate_groups
            ORDER BY id
            LIMIT 1
        )
        """
    )

    connection.execute(
        """
        DELETE FROM duplicate_groups
        WHERE id = (
            SELECT id
            FROM duplicate_groups
            ORDER BY id
            LIMIT 1
        )
        """
    )

    raise RuntimeError(
        "intentional duplicate rollback test"
    )

except RuntimeError:
    connection.rollback()
    rollback_executed = True

rollback_after = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

connection.close()

payload = {
    "mode": "copied-database-full-rebuild-test",
    "source_database": str(source_path),
    "test_database": str(test_path),
    "before": {
        "duplicate_groups": before_groups,
        "duplicate_files": before_files,
    },
    "after": {
        "duplicate_groups": after_groups,
        "duplicate_files": after_files,
    },
    "rebuild": {
        "status": rebuild_status,
        "inserted_groups": inserted_groups,
        "inserted_files": inserted_files,
        "elapsed_seconds": elapsed,
    },
    "validation": {
        "relationship_errors": relationship_errors,
        "foreign_key_errors": len(foreign_key_errors),
        "integrity": integrity,
    },
    "rollback": {
        "executed": rollback_executed,
        "groups_before": rollback_before,
        "groups_after": rollback_after,
        "unchanged": rollback_before == rollback_after,
    },
    "safety": {
        "source_database_modified": False,
        "files_modified": False,
        "automatic_deletion": False,
        "immich_excluded": True,
        "nextcloud_excluded": True,
    },
}

payload["test_passed"] = (
    rebuild_status == "completed"
    and inserted_groups == after_groups
    and inserted_files == after_files
    and relationship_errors == 0
    and len(foreign_key_errors) == 0
    and integrity == "ok"
    and rollback_executed
    and rollback_before == rollback_after
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
            "inserted_groups": inserted_groups,
            "inserted_files": inserted_files,
            "elapsed_seconds": elapsed,
            "relationship_errors": relationship_errors,
            "foreign_key_errors": len(foreign_key_errors),
            "integrity": integrity,
            "rollback_unchanged":
                rollback_before == rollback_after,
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
