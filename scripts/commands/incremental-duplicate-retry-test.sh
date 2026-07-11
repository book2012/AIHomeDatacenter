#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/incremental-retry.db"

mkdir -p "${TEST_DIR}"

rm -f \
  "${TEST_DB}" \
  "${TEST_DB}-wal" \
  "${TEST_DB}-shm"

sqlite3 "${SOURCE_DB}" ".backup '${TEST_DB}'"

python3 - "${TEST_DB}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1])

con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
con.execute("PRAGMA foreign_keys = ON")
con.execute("PRAGMA busy_timeout = 30000")

candidates = con.execute(
    """
    SELECT
        id,
        path,
        size_bytes
    FROM files
    WHERE root_path =
          '/opt/aihomedatacenter/tests/storage-sample'
      AND is_missing = 0
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) = 64
    ORDER BY id
    LIMIT 10
    """
).fetchall()

if not candidates:
    con.close()
    raise SystemExit("No test candidates found.")

batch_id = "incremental-retry-test"
failed_file_id = int(candidates[0]["id"])

try:
    con.execute("BEGIN IMMEDIATE")

    con.execute(
        """
        INSERT INTO hash_batches (
            batch_id,
            status,
            files_total,
            files_completed,
            bytes_total,
            bytes_completed,
            started_at
        )
        VALUES (?, 'running', ?, 0, ?, 0, CURRENT_TIMESTAMP)
        """,
        (
            batch_id,
            len(candidates),
            sum(int(row["size_bytes"]) for row in candidates),
        ),
    )

    for row in candidates:
        con.execute(
            """
            INSERT INTO duplicate_processing (
                file_id,
                status,
                hash_batch_id,
                retry_count,
                updated_at
            )
            VALUES (?, 'processing', ?, 0, CURRENT_TIMESTAMP)
            ON CONFLICT(file_id)
            DO UPDATE SET
                status = 'processing',
                hash_batch_id = excluded.hash_batch_id,
                retry_count = 0,
                error_message = NULL,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                row["id"],
                batch_id,
            ),
        )

    con.execute(
        """
        UPDATE duplicate_processing
        SET status = 'failed',
            retry_count = retry_count + 1,
            error_message = 'intentional retry test failure',
            updated_at = CURRENT_TIMESTAMP
        WHERE file_id = ?
        """,
        (failed_file_id,),
    )

    con.execute(
        """
        UPDATE duplicate_processing
        SET status = 'completed',
            checked_at = CURRENT_TIMESTAMP,
            error_message = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE hash_batch_id = ?
          AND file_id != ?
        """,
        (
            batch_id,
            failed_file_id,
        ),
    )

    con.execute(
        """
        UPDATE hash_batches
        SET status = 'failed',
            files_completed = ?,
            error_message = 'one file requires retry'
        WHERE batch_id = ?
        """,
        (
            len(candidates) - 1,
            batch_id,
        ),
    )

    con.commit()

except Exception:
    con.rollback()
    raise

failed_state = dict(
    con.execute(
        """
        SELECT
            file_id,
            status,
            retry_count,
            error_message
        FROM duplicate_processing
        WHERE file_id = ?
        """,
        (failed_file_id,),
    ).fetchone()
)

try:
    con.execute("BEGIN IMMEDIATE")

    con.execute(
        """
        UPDATE duplicate_processing
        SET status = 'processing',
            error_message = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE file_id = ?
          AND status = 'failed'
        """,
        (failed_file_id,),
    )

    con.execute(
        """
        UPDATE duplicate_processing
        SET status = 'completed',
            checked_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE file_id = ?
        """,
        (failed_file_id,),
    )

    completed_count = con.execute(
        """
        SELECT COUNT(*)
        FROM duplicate_processing
        WHERE hash_batch_id = ?
          AND status = 'completed'
        """,
        (batch_id,),
    ).fetchone()[0]

    completed_bytes = con.execute(
        """
        SELECT COALESCE(SUM(files.size_bytes), 0)
        FROM duplicate_processing
        JOIN files
          ON files.id = duplicate_processing.file_id
        WHERE duplicate_processing.hash_batch_id = ?
          AND duplicate_processing.status = 'completed'
        """,
        (batch_id,),
    ).fetchone()[0]

    con.execute(
        """
        UPDATE hash_batches
        SET status = 'completed',
            files_completed = ?,
            bytes_completed = ?,
            error_message = NULL,
            finished_at = CURRENT_TIMESTAMP
        WHERE batch_id = ?
        """,
        (
            completed_count,
            completed_bytes,
            batch_id,
        ),
    )

    con.commit()

except Exception:
    con.rollback()
    raise

final_state = dict(
    con.execute(
        """
        SELECT
            file_id,
            status,
            retry_count,
            error_message,
            checked_at
        FROM duplicate_processing
        WHERE file_id = ?
        """,
        (failed_file_id,),
    ).fetchone()
)

batch = dict(
    con.execute(
        """
        SELECT
            batch_id,
            status,
            files_total,
            files_completed,
            bytes_total,
            bytes_completed,
            error_message
        FROM hash_batches
        WHERE batch_id = ?
        """,
        (batch_id,),
    ).fetchone()
)

all_states = [
    dict(row)
    for row in con.execute(
        """
        SELECT
            file_id,
            status,
            retry_count,
            error_message
        FROM duplicate_processing
        WHERE hash_batch_id = ?
        ORDER BY file_id
        """,
        (batch_id,),
    )
]

integrity = con.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

foreign_key_errors = len(
    con.execute("PRAGMA foreign_key_check").fetchall()
)

con.close()

test_passed = (
    failed_state["status"] == "failed"
    and failed_state["retry_count"] == 1
    and final_state["status"] == "completed"
    and final_state["retry_count"] == 1
    and final_state["error_message"] is None
    and batch["status"] == "completed"
    and batch["files_total"] == len(candidates)
    and batch["files_completed"] == len(candidates)
    and integrity == "ok"
    and foreign_key_errors == 0
)

result = {
    "candidate_files": len(candidates),
    "failed_file_id": failed_file_id,
    "failed_state": failed_state,
    "final_state": final_state,
    "batch": batch,
    "states": all_states,
    "integrity": integrity,
    "foreign_key_errors": foreign_key_errors,
    "source_database_modified": False,
    "test_passed": test_passed,
}

print(json.dumps(result, ensure_ascii=False, indent=2))

if not test_passed:
    raise SystemExit(1)
PYTHON
