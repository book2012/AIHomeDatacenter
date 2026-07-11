#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

SOURCE_DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
TEST_DIR="${PROJECT_ROOT}/agents/storage-agent/data/test"
WORK_DB="${TEST_DIR}/restore-work.db"
BACKUP_DB="${TEST_DIR}/restore-backup.db"

REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/backup-restore-test-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-backup-restore-test.json"

mkdir -p "${TEST_DIR}" "${REPORT_DIR}"

if [[ ! -f "${SOURCE_DB}" ]]; then
    echo "Source database not found: ${SOURCE_DB}" >&2
    exit 1
fi

rm -f \
    "${WORK_DB}" \
    "${WORK_DB}-wal" \
    "${WORK_DB}-shm" \
    "${BACKUP_DB}" \
    "${BACKUP_DB}-wal" \
    "${BACKUP_DB}-shm"

python3 - \
    "${SOURCE_DB}" \
    "${WORK_DB}" \
    "${BACKUP_DB}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from pathlib import Path


source_path = Path(sys.argv[1]).resolve()
work_path = Path(sys.argv[2]).resolve()
backup_path = Path(sys.argv[3]).resolve()
report_path = Path(sys.argv[4]).resolve()


def sqlite_backup(source: Path, target: Path) -> None:
    source_connection = sqlite3.connect(source)
    target_connection = sqlite3.connect(target)

    try:
        source_connection.backup(target_connection)
    finally:
        target_connection.close()
        source_connection.close()


def database_state(database: Path) -> dict[str, object]:
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row

    integrity = connection.execute(
        "PRAGMA integrity_check"
    ).fetchone()[0]

    total_files = connection.execute(
        "SELECT COUNT(*) FROM files"
    ).fetchone()[0]

    done_files = connection.execute(
        """
        SELECT COUNT(*)
        FROM files
        WHERE hash_status = 'done'
        """
    ).fetchone()[0]

    candidate = connection.execute(
        """
        SELECT
            id,
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

    connection.close()

    return {
        "integrity": integrity,
        "total_files": total_files,
        "done_files": done_files,
        "candidate": dict(candidate) if candidate else None,
    }


sqlite_backup(source_path, work_path)
sqlite_backup(work_path, backup_path)

before = database_state(work_path)
candidate = before["candidate"]

if candidate is None:
    raise SystemExit(
        "No pending candidate found for restore test."
    )

connection = sqlite3.connect(work_path)

try:
    connection.execute(
        """
        UPDATE files
        SET sha256 = ?,
            hash_status = 'done',
            hash_updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
        """,
        (
            "e" * 64,
            candidate["id"],
        ),
    )
    connection.commit()
finally:
    connection.close()

modified = database_state(work_path)

work_path.unlink()
shutil.copy2(backup_path, work_path)

restored = database_state(work_path)

test_passed = (
    before["integrity"] == "ok"
    and restored["integrity"] == "ok"
    and before["total_files"] == restored["total_files"]
    and before["done_files"] == restored["done_files"]
    and before["candidate"] == restored["candidate"]
    and modified["done_files"] == before["done_files"] + 1
)

payload = {
    "mode": "copied-database-restore-test",
    "source_database": str(source_path),
    "work_database": str(work_path),
    "backup_database": str(backup_path),
    "before": before,
    "modified": modified,
    "restored": restored,
    "source_database_modified": False,
    "restore_completed": True,
    "test_passed": test_passed,
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
            "before_done": before["done_files"],
            "modified_done": modified["done_files"],
            "restored_done": restored["done_files"],
            "restored_integrity": restored["integrity"],
            "source_database_modified": False,
            "test_passed": test_passed,
        },
        ensure_ascii=False,
        indent=2,
    )
)

if not test_passed:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
