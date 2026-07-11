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
CONFIRM_OPTION="${2:-}"

case "${ROOT_NAME}" in
    exhdd1)
        ROOT_PATH="/mnt/exHDD1"
        ;;
    exhdd2)
        ROOT_PATH="/mnt/exHDD2"
        ;;
    archive)
        ROOT_PATH="/mnt/storage/Archive"
        ;;
    *)
        echo "Usage:" >&2
        echo "  storage-reconcile.sh exhdd1 [--confirm-empty]" >&2
        echo "  storage-reconcile.sh exhdd2 [--confirm-empty]" >&2
        echo "  storage-reconcile.sh archive [--confirm-empty]" >&2
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

if ! mountpoint -q "${ROOT_PATH}"; then
    echo "Storage path is not a mountpoint: ${ROOT_PATH}" >&2
    exit 3
fi

MOUNT_SOURCE="$(findmnt -n -o SOURCE -T "${ROOT_PATH}")"
MOUNT_FSTYPE="$(findmnt -n -o FSTYPE -T "${ROOT_PATH}")"

if [[ "${MOUNT_SOURCE}" != /dev/* ]]; then
    echo "Unexpected mount source: ${MOUNT_SOURCE}" >&2
    exit 3
fi

echo "Counting actual files: ${ROOT_PATH}" >&2

ACTUAL_FILES="$(
    find "${ROOT_PATH}" \
        -type f \
        -printf '.' \
        2>/dev/null |
    wc -c
)"

if [[ "${ACTUAL_FILES}" -eq 0 ]] &&
   [[ "${CONFIRM_OPTION}" != "--confirm-empty" ]]; then
    echo "Storage contains zero files." >&2
    echo "Explicit confirmation required: --confirm-empty" >&2
    exit 4
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
    "${ROOT_NAME}" \
    "${ACTUAL_FILES}" \
    "${MOUNT_SOURCE}" \
    "${MOUNT_FSTYPE}" \
    "${BACKUP_FILE}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
root_path = Path(sys.argv[2]).resolve()
root_name = sys.argv[3]
actual_files = int(sys.argv[4])
mount_source = sys.argv[5]
mount_fstype = sys.argv[6]
backup_path = Path(sys.argv[7]).resolve()
report_path = Path(sys.argv[8]).resolve()

connection = sqlite3.connect(
    database_path,
    timeout=60.0,
)

connection.row_factory = sqlite3.Row
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("PRAGMA busy_timeout = 60000")

before = connection.execute(
    """
    SELECT
        COUNT(*) AS total,
        SUM(
            CASE WHEN is_missing = 0 THEN 1 ELSE 0 END
        ) AS present,
        SUM(
            CASE WHEN is_missing = 1 THEN 1 ELSE 0 END
        ) AS missing,
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

inventory_total = int(before["total"] or 0)

if actual_files > inventory_total:
    connection.close()
    raise SystemExit(
        "Actual file count exceeds Inventory count. "
        "Run a metadata scan before reconcile."
    )

started_at = datetime.now(timezone.utc).isoformat()
updated_missing = 0
restored_present = 0

try:
    connection.execute("BEGIN IMMEDIATE")

    if actual_files == 0:
        cursor = connection.execute(
            """
            UPDATE files
            SET is_missing = 1
            WHERE root_path = ?
              AND is_missing = 0
            """,
            (str(root_path),),
        )

        updated_missing = cursor.rowcount

    else:
        for row in connection.execute(
            """
            SELECT id, path, is_missing
            FROM files
            WHERE root_path = ?
            """,
            (str(root_path),),
        ):
            exists = os.path.isfile(row["path"])

            if exists and int(row["is_missing"]) == 1:
                connection.execute(
                    """
                    UPDATE files
                    SET is_missing = 0
                    WHERE id = ?
                    """,
                    (row["id"],),
                )
                restored_present += 1

            elif not exists and int(row["is_missing"]) == 0:
                connection.execute(
                    """
                    UPDATE files
                    SET is_missing = 1
                    WHERE id = ?
                    """,
                    (row["id"],),
                )
                updated_missing += 1

    event_message = (
        f"root={root_path}; "
        f"actual_files={actual_files}; "
        f"marked_missing={updated_missing}; "
        f"restored_present={restored_present}"
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
            event_message,
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
        SUM(
            CASE WHEN is_missing = 0 THEN 1 ELSE 0 END
        ) AS present,
        SUM(
            CASE WHEN is_missing = 1 THEN 1 ELSE 0 END
        ) AS missing,
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

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

connection.close()

payload = {
    "mode": "storage-reconcile",
    "root_name": root_name,
    "root_path": str(root_path),
    "mount": {
        "source": mount_source,
        "filesystem": mount_fstype,
    },
    "actual_files": actual_files,
    "backup": str(backup_path),
    "before": dict(before),
    "changes": {
        "marked_missing": updated_missing,
        "restored_present": restored_present,
    },
    "after": dict(after),
    "database_integrity": integrity,
    "safety": {
        "inventory_records_deleted": False,
        "sha256_values_deleted": False,
        "physical_files_modified": False,
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
        payload,
        ensure_ascii=False,
        indent=2,
    )
)

if integrity != "ok":
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Reconcile report: ${REPORT_FILE}" >&2
