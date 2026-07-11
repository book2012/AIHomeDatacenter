#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
TEST_DB="${TEST_DIR}/incremental-processing.db"

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
        sha256,
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

batch_id = "incremental-processing-test"
groups_created = 0
groups_reused = 0
group_links = 0

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
                duplicate_group_id = NULL,
                error_message = NULL,
                updated_at = CURRENT_TIMESTAMP
            """,
            (row["id"], batch_id),
        )

        matching_files = con.execute(
            """
            SELECT
                id,
                path,
                size_bytes
            FROM files
            WHERE sha256 = ?
              AND size_bytes = ?
              AND is_missing = 0
            ORDER BY id
            """,
            (
                row["sha256"],
                row["size_bytes"],
            ),
        ).fetchall()

        group_id = None

        if len(matching_files) > 1:
            existing_group = con.execute(
                """
                SELECT id
                FROM duplicate_groups
                WHERE sha256 = ?
                ORDER BY id
                LIMIT 1
                """,
                (row["sha256"],),
            ).fetchone()

            if existing_group:
                group_id = int(existing_group["id"])
                groups_reused += 1
            else:
                cursor = con.execute(
                    """
                    INSERT INTO duplicate_groups (
                        sha256,
                        file_count,
                        total_size_bytes,
                        created_at
                    )
                    VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                    """,
                    (
                        row["sha256"],
                        len(matching_files),
                        int(row["size_bytes"])
                        * len(matching_files),
                    ),
                )

                group_id = int(cursor.lastrowid)
                groups_created += 1

            for match in matching_files:
                exists = con.execute(
                    """
                    SELECT 1
                    FROM duplicate_files
                    WHERE duplicate_group_id = ?
                      AND file_id = ?
                    """,
                    (
                        group_id,
                        match["id"],
                    ),
                ).fetchone()

                if not exists:
                    con.execute(
                        """
                        INSERT INTO duplicate_files (
                            duplicate_group_id,
                            file_id,
                            path,
                            size_bytes
                        )
                        VALUES (?, ?, ?, ?)
                        """,
                        (
                            group_id,
                            match["id"],
                            match["path"],
                            match["size_bytes"],
                        ),
                    )

                    group_links += 1

        con.execute(
            """
            UPDATE duplicate_processing
            SET status = 'completed',
                duplicate_group_id = ?,
                checked_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
            WHERE file_id = ?
            """,
            (
                group_id,
                row["id"],
            ),
        )

    con.execute(
        """
        UPDATE hash_batches
        SET status = 'completed',
            files_completed = files_total,
            bytes_completed = bytes_total,
            finished_at = CURRENT_TIMESTAMP
        WHERE batch_id = ?
        """,
        (batch_id,),
    )

    con.commit()

except Exception:
    con.rollback()
    raise

batch = dict(
    con.execute(
        """
        SELECT
            batch_id,
            status,
            files_total,
            files_completed,
            bytes_total,
            bytes_completed
        FROM hash_batches
        WHERE batch_id = ?
        """,
        (batch_id,),
    ).fetchone()
)

processing = [
    dict(row)
    for row in con.execute(
        """
        SELECT
            duplicate_processing.file_id,
            duplicate_processing.status,
            duplicate_processing.duplicate_group_id,
            duplicate_processing.hash_batch_id,
            files.path
        FROM duplicate_processing
        JOIN files
          ON files.id = duplicate_processing.file_id
        WHERE duplicate_processing.hash_batch_id = ?
        ORDER BY duplicate_processing.file_id
        """,
        (batch_id,),
    )
]

duplicate_groups = con.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

duplicate_files = con.execute(
    "SELECT COUNT(*) FROM duplicate_files"
).fetchone()[0]

relationship_errors = con.execute(
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

foreign_key_errors = len(
    con.execute("PRAGMA foreign_key_check").fetchall()
)

integrity = con.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

con.close()

result = {
    "candidate_files": len(candidates),
    "batch": batch,
    "processing_rows": len(processing),
    "completed_files": sum(
        row["status"] == "completed"
        for row in processing
    ),
    "groups_created": groups_created,
    "groups_reused": groups_reused,
    "group_links_created": group_links,
    "duplicate_group_rows": duplicate_groups,
    "duplicate_file_rows": duplicate_files,
    "relationship_errors": relationship_errors,
    "foreign_key_errors": foreign_key_errors,
    "integrity": integrity,
    "source_database_modified": False,
    "processing": processing,
}

print(json.dumps(result, ensure_ascii=False, indent=2))

if (
    batch["status"] != "completed"
    or batch["files_total"] != len(candidates)
    or batch["files_completed"] != len(candidates)
    or len(processing) != len(candidates)
    or result["completed_files"] != len(candidates)
    or relationship_errors != 0
    or foreign_key_errors != 0
    or integrity != "ok"
):
    raise SystemExit(1)
PYTHON
