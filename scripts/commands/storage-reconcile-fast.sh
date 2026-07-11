#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
BACKUP_DIR="${PROJECT_ROOT}/agents/storage-agent/data/backups"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

ROOT_NAME="${1:-}"

case "${ROOT_NAME}" in
    exhdd2)
        ROOT_PATH="/mnt/exHDD2"
        ;;
    *)
        echo "Usage: storage-reconcile-fast.sh exhdd2" >&2
        exit 2
        ;;
esac

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

if [[ ! -d "${ROOT_PATH}" ]]; then
    echo "Storage path not found: ${ROOT_PATH}" >&2
    exit 1
fi

MOUNT_SOURCE="$(findmnt -n -o SOURCE -T "${ROOT_PATH}" || true)"
MOUNT_FSTYPE="$(findmnt -n -o FSTYPE -T "${ROOT_PATH}" || true)"

if [[ -z "${MOUNT_SOURCE}" || "${MOUNT_SOURCE}" != /dev/* ]]; then
    echo "Unexpected mount source: ${MOUNT_SOURCE:-unknown}" >&2
    exit 3
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/storage-before-reconcile-${ROOT_NAME}-${STAMP}.db"
REPORT_FILE="${REPORT_DIR}/storage-reconcile-${ROOT_NAME}-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-storage-reconcile-${ROOT_NAME}.json"

mkdir -p "${BACKUP_DIR}" "${REPORT_DIR}"

sqlite3 "${DB}" ".backup '${BACKUP_FILE}'"

python3 - \
    "${DB}" \
    "${ROOT_PATH}" \
    "${MOUNT_SOURCE}" \
    "${MOUNT_FSTYPE}" \
    "${BACKUP_FILE}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
root_path = Path(sys.argv[2]).resolve()
mount_source = sys.argv[3]
mount_fstype = sys.argv[4]
backup_path = Path(sys.argv[5]).resolve()
report_path = Path(sys.argv[6]).resolve()

started_at = datetime.now(timezone.utc).isoformat()
started = time.monotonic()

connection = sqlite3.connect(database_path, timeout=120)
connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("PRAGMA busy_timeout = 120000")

before = connection.execute(
    """
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN is_missing = 0 THEN 1 ELSE 0 END) AS present,
        SUM(CASE WHEN is_missing = 1 THEN 1 ELSE 0 END) AS missing,
        SUM(
            CASE
                WHEN sha256 IS NOT NULL
                 AND length(trim(sha256)) = 64
                THEN 1
                ELSE 0
            END
        ) AS with_sha256
    FROM files
    WHERE root_path = ?
    """,
    (str(root_path),),
).fetchone()

connection.execute(
    """
    CREATE TEMP TABLE actual_files (
        path TEXT PRIMARY KEY
    ) WITHOUT ROWID
    """
)

batch: list[tuple[str]] = []
actual_count = 0

for current_root, _, filenames in os.walk(root_path):
    for filename in filenames:
        batch.append(
            (str(Path(current_root) / filename),)
        )
        actual_count += 1

        if len(batch) >= 5000:
            connection.executemany(
                "INSERT OR IGNORE INTO actual_files(path) VALUES (?)",
                batch,
            )
            batch.clear()

if batch:
    connection.executemany(
        "INSERT OR IGNORE INTO actual_files(path) VALUES (?)",
        batch,
    )

# Finish the temporary-table load transaction before
# starting the protected Inventory update transaction.
connection.commit()

try:
    connection.execute("BEGIN IMMEDIATE")

    missing_cursor = connection.execute(
        """
        UPDATE files
        SET is_missing = 1
        WHERE root_path = ?
          AND is_missing = 0
          AND NOT EXISTS (
              SELECT 1
              FROM actual_files
              WHERE actual_files.path = files.path
          )
        """,
        (str(root_path),),
    )

    restore_cursor = connection.execute(
        """
        UPDATE files
        SET is_missing = 0
        WHERE root_path = ?
          AND is_missing = 1
          AND EXISTS (
              SELECT 1
              FROM actual_files
              WHERE actual_files.path = files.path
          )
        """,
        (str(root_path),),
    )

    connection.execute(
        """
        INSERT INTO agent_events (
            event_type,
            message,
            created_at
        )
        VALUES (?, ?, ?)
        """,
        (
            "storage_reconcile",
            (
                f"root={root_path}; "
                f"actual={actual_count}; "
                f"marked_missing={missing_cursor.rowcount}; "
                f"restored_present={restore_cursor.rowcount}"
            ),
            started_at,
        ),
    )

    connection.commit()

except Exception:
    connection.rollback()
    raise

after = connection.execute(
    """
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN is_missing = 0 THEN 1 ELSE 0 END) AS present,
        SUM(CASE WHEN is_missing = 1 THEN 1 ELSE 0 END) AS missing,
        SUM(
            CASE
                WHEN sha256 IS NOT NULL
                 AND length(trim(sha256)) = 64
                THEN 1
                ELSE 0
            END
        ) AS with_sha256
    FROM files
    WHERE root_path = ?
    """,
    (str(root_path),),
).fetchone()

untracked_actual = connection.execute(
    """
    SELECT COUNT(*)
    FROM actual_files
    LEFT JOIN files
      ON files.path = actual_files.path
    WHERE files.id IS NULL
    """
).fetchone()[0]

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

connection.close()

payload = {
    "mode": "fast-storage-reconcile",
    "root_path": str(root_path),
    "mount": {
        "source": mount_source,
        "filesystem": mount_fstype,
    },
    "actual_files": actual_count,
    "before": dict(before),
    "changes": {
        "marked_missing": missing_cursor.rowcount,
        "restored_present": restore_cursor.rowcount,
        "untracked_actual_files": untracked_actual,
    },
    "after": dict(after),
    "elapsed_seconds": round(time.monotonic() - started, 3),
    "backup": str(backup_path),
    "database_integrity": integrity,
    "safety": {
        "inventory_records_deleted": False,
        "sha256_values_deleted": False,
        "physical_files_modified": False,
        "automatic_deletion": False,
    },
}

report_path.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

print(json.dumps(payload, ensure_ascii=False, indent=2))

if integrity != "ok":
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
