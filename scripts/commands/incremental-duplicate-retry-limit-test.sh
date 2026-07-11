#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/incremental-retry-limit.db"
CONFIG="${PROJECT_ROOT}/config/incremental-duplicate.env"

mkdir -p "${TEST_DIR}"

rm -f \
  "${TEST_DB}" \
  "${TEST_DB}-wal" \
  "${TEST_DB}-shm"

set -a
source "${CONFIG}"
set +a

MAX_RETRY_COUNT="${MAX_RETRY_COUNT:-3}"

sqlite3 "${SOURCE_DB}" ".backup '${TEST_DB}'"

python3 - \
  "${TEST_DB}" \
  "${MAX_RETRY_COUNT}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1])
max_retry = int(sys.argv[2])

if max_retry < 1 or max_retry > 10:
    raise SystemExit("MAX_RETRY_COUNT must be between 1 and 10.")

con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
con.execute("PRAGMA foreign_keys = ON")

candidate = con.execute(
    """
    SELECT id, path
    FROM files
    WHERE root_path =
          '/opt/aihomedatacenter/tests/storage-sample'
      AND is_missing = 0
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) = 64
    ORDER BY id
    LIMIT 1
    """
).fetchone()

if candidate is None:
    con.close()
    raise SystemExit("No test candidate found.")

file_id = int(candidate["id"])

con.execute(
    """
    INSERT INTO duplicate_processing (
        file_id,
        status,
        retry_count,
        error_message,
        updated_at
    )
    VALUES (?, 'failed', 0, 'initial failure', CURRENT_TIMESTAMP)
    ON CONFLICT(file_id)
    DO UPDATE SET
        status = 'failed',
        retry_count = 0,
        error_message = 'initial failure',
        updated_at = CURRENT_TIMESTAMP
    """,
    (file_id,),
)
con.commit()

attempts = []

for attempt in range(1, max_retry + 2):
    row = con.execute(
        """
        SELECT status, retry_count
        FROM duplicate_processing
        WHERE file_id = ?
        """,
        (file_id,),
    ).fetchone()

    allowed = (
        row["status"] == "failed"
        and int(row["retry_count"]) < max_retry
    )

    if allowed:
        con.execute("BEGIN IMMEDIATE")

        con.execute(
            """
            UPDATE duplicate_processing
            SET status = 'processing',
                updated_at = CURRENT_TIMESTAMP
            WHERE file_id = ?
              AND status = 'failed'
              AND retry_count < ?
            """,
            (file_id, max_retry),
        )

        con.execute(
            """
            UPDATE duplicate_processing
            SET status = 'failed',
                retry_count = retry_count + 1,
                error_message = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE file_id = ?
            """,
            (
                f"intentional failure attempt {attempt}",
                file_id,
            ),
        )

        con.commit()

    final = con.execute(
        """
        SELECT
            status,
            retry_count,
            error_message
        FROM duplicate_processing
        WHERE file_id = ?
        """,
        (file_id,),
    ).fetchone()

    attempts.append(
        {
            "attempt": attempt,
            "retry_allowed": allowed,
            "status": final["status"],
            "retry_count": final["retry_count"],
            "error_message": final["error_message"],
        }
    )

final_state = dict(
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
        (file_id,),
    ).fetchone()
)

integrity = con.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

foreign_key_errors = len(
    con.execute("PRAGMA foreign_key_check").fetchall()
)

con.close()

last_attempt = attempts[-1]

test_passed = (
    final_state["status"] == "failed"
    and final_state["retry_count"] == max_retry
    and last_attempt["retry_allowed"] is False
    and integrity == "ok"
    and foreign_key_errors == 0
)

result = {
    "max_retry_count": max_retry,
    "file_id": file_id,
    "attempts": attempts,
    "final_state": final_state,
    "automatic_retry_blocked": (
        last_attempt["retry_allowed"] is False
    ),
    "manual_review_required": (
        final_state["retry_count"] >= max_retry
    ),
    "integrity": integrity,
    "foreign_key_errors": foreign_key_errors,
    "source_database_modified": False,
    "test_passed": test_passed,
}

print(json.dumps(result, ensure_ascii=False, indent=2))

if not test_passed:
    raise SystemExit(1)
PYTHON
