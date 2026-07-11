#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
PREVIEW="${PROJECT_ROOT}/reports/storage-agent/latest-hash-db-apply-preview.json"
BACKUP_DIR="${PROJECT_ROOT}/agents/storage-agent/data/backups"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/storage-before-hash-${STAMP}.db"
REPORT_FILE="${REPORT_DIR}/hash-db-apply-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-db-apply.json"

MAX_FILES="${1:-10}"

mkdir -p "${BACKUP_DIR}" "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

if [[ ! -f "${PREVIEW}" ]]; then
    echo "Apply preview not found: ${PREVIEW}" >&2
    exit 1
fi

if ! [[ "${MAX_FILES}" =~ ^[0-9]+$ ]] ||
   (( MAX_FILES < 1 || MAX_FILES > 10 )); then
    echo "MAX_FILES must be between 1 and 10." >&2
    exit 2
fi

python3 - \
    "${DB}" \
    "${PREVIEW}" \
    "${BACKUP_FILE}" \
    "${REPORT_FILE}" \
    "${MAX_FILES}" <<'PYTHON'
from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
preview_path = Path(sys.argv[2]).resolve()
backup_path = Path(sys.argv[3]).resolve()
report_path = Path(sys.argv[4]).resolve()
max_files = int(sys.argv[5])

preview = json.loads(
    preview_path.read_text(encoding="utf-8")
)

ready_items = preview.get("ready_items", [])[:max_files]

if not ready_items:
    raise SystemExit("No ready items found in apply preview.")

backup_path.parent.mkdir(parents=True, exist_ok=True)

source = sqlite3.connect(database_path)
destination = sqlite3.connect(backup_path)

try:
    source.backup(destination)
finally:
    destination.close()
    source.close()

connection = sqlite3.connect(
    database_path,
    timeout=10.0,
)

connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("PRAGMA busy_timeout = 10000")

started_at = datetime.now(timezone.utc).isoformat()
finished_at = None
hash_run_id = None
updated_items = []
status = "failed"
error_message = None

try:
    connection.execute("BEGIN IMMEDIATE")

    cursor = connection.execute(
        """
        INSERT INTO hash_runs (
            started_at,
            status,
            files_hashed
        )
        VALUES (?, 'running', 0)
        """,
        (started_at,),
    )

    hash_run_id = int(cursor.lastrowid)

    for item in ready_items:
        file_id = int(item["file_id"])
        proposed = item["proposed"]
        calculated_sha256 = proposed["sha256"]

        current = connection.execute(
            """
            SELECT
                id,
                path,
                size_bytes,
                sha256,
                hash_status,
                is_missing
            FROM files
            WHERE id = ?
            """,
            (file_id,),
        ).fetchone()

        if current is None:
            raise RuntimeError(
                f"Database record missing: file_id={file_id}"
            )

        if current["hash_status"] != "pending":
            raise RuntimeError(
                f"Status changed: file_id={file_id}, "
                f"status={current['hash_status']}"
            )

        if current["sha256"] not in (None, ""):
            raise RuntimeError(
                f"Existing SHA256 detected: file_id={file_id}"
            )

        if int(current["is_missing"]) != 0:
            raise RuntimeError(
                f"Record marked missing: file_id={file_id}"
            )

        if current["path"] != item["path"]:
            raise RuntimeError(
                f"Path changed: file_id={file_id}"
            )

        updated_at = datetime.now(timezone.utc).isoformat()

        update_cursor = connection.execute(
            """
            UPDATE files
            SET sha256 = ?,
                hash_status = 'done',
                hash_updated_at = ?
            WHERE id = ?
              AND hash_status = 'pending'
              AND (
                  sha256 IS NULL
                  OR length(trim(sha256)) = 0
              )
              AND is_missing = 0
            """,
            (
                calculated_sha256,
                updated_at,
                file_id,
            ),
        )

        if update_cursor.rowcount != 1:
            raise RuntimeError(
                f"Atomic update rejected: file_id={file_id}"
            )

        updated_items.append(
            {
                "file_id": file_id,
                "path": current["path"],
                "sha256": calculated_sha256,
                "hash_updated_at": updated_at,
            }
        )

    finished_at = datetime.now(timezone.utc).isoformat()

    connection.execute(
        """
        UPDATE hash_runs
        SET finished_at = ?,
            status = 'completed',
            files_hashed = ?,
            error_message = NULL
        WHERE id = ?
        """,
        (
            finished_at,
            len(updated_items),
            hash_run_id,
        ),
    )

    connection.commit()
    status = "completed"

except Exception as error:
    connection.rollback()
    error_message = f"{type(error).__name__}: {error}"
    finished_at = datetime.now(timezone.utc).isoformat()

    try:
        connection.execute(
            """
            INSERT INTO hash_runs (
                started_at,
                finished_at,
                status,
                files_hashed,
                error_message
            )
            VALUES (?, ?, 'failed', 0, ?)
            """,
            (
                started_at,
                finished_at,
                error_message,
            ),
        )
        connection.commit()
    except sqlite3.Error:
        connection.rollback()

finally:
    integrity = connection.execute(
        "PRAGMA integrity_check"
    ).fetchone()[0]

    connection.close()

payload = {
    "mode": "transaction-apply-pilot",
    "status": status,
    "database": str(database_path),
    "backup": str(backup_path),
    "hash_run_id": hash_run_id,
    "summary": {
        "requested_files": len(ready_items),
        "updated_files": len(updated_items),
        "failed_files": (
            0 if status == "completed"
            else len(ready_items)
        ),
    },
    "updated_items": updated_items,
    "error": error_message,
    "database_integrity": integrity,
    "safety": {
        "maximum_files": max_files,
        "single_transaction": True,
        "rollback_on_error": True,
        "existing_sha256_overwritten": False,
        "files_modified": False,
        "automatic_deletion": False,
    },
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
            "status": status,
            "backup": str(backup_path),
            "summary": payload["summary"],
            "database_integrity": integrity,
            "error": error_message,
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)

if status != "completed":
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Hash apply report: ${REPORT_FILE}" >&2
