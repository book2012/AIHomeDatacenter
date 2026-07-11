#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"

REPORT_FILE="${REPORT_DIR}/storage-freshness-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-storage-freshness.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

python3 - "${DB}" "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()

targets = [
    {
        "name": "exhdd2",
        "path": "/mnt/exHDD2",
        "root_path": "/mnt/exHDD2",
    },
    {
        "name": "archive",
        "path": "/mnt/storage/Archive",
        "root_path": "/mnt/storage/Archive",
    },
]

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)

connection.row_factory = sqlite3.Row

results = []

for target in targets:
    path = target["path"]
    root_path = target["root_path"]

    mounted = subprocess.run(
        ["mountpoint", "-q", path],
        check=False,
    ).returncode == 0

    mount_source = None
    filesystem = None

    if mounted:
        mount_source_result = subprocess.run(
            [
                "findmnt",
                "-n",
                "-o",
                "SOURCE",
                "-T",
                path,
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        filesystem_result = subprocess.run(
            [
                "findmnt",
                "-n",
                "-o",
                "FSTYPE",
                "-T",
                path,
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        mount_source = mount_source_result.stdout.strip() or None
        filesystem = filesystem_result.stdout.strip() or None

    started = time.monotonic()
    actual_files = None
    count_error = None

    if mounted and os.path.isdir(path):
        try:
            count_process = subprocess.run(
                [
                    "find",
                    path,
                    "-type",
                    "f",
                    "-printf",
                    ".",
                ],
                check=False,
                capture_output=True,
                timeout=300,
            )

            if count_process.returncode == 0:
                actual_files = len(count_process.stdout)
            else:
                count_error = (
                    f"find exit={count_process.returncode}"
                )

        except subprocess.TimeoutExpired:
            count_error = "timeout"

    elif not mounted:
        count_error = "not_mounted"

    else:
        count_error = "path_missing"

    elapsed = round(
        time.monotonic() - started,
        3,
    )

    inventory = connection.execute(
        """
        SELECT
            COUNT(*) AS total,
            SUM(
                CASE
                    WHEN is_missing = 0
                    THEN 1
                    ELSE 0
                END
            ) AS present,
            SUM(
                CASE
                    WHEN is_missing = 1
                    THEN 1
                    ELSE 0
                END
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
        (root_path,),
    ).fetchone()

    inventory_total = int(inventory["total"] or 0)
    inventory_present = int(inventory["present"] or 0)
    inventory_missing = int(inventory["missing"] or 0)
    with_sha256 = int(inventory["with_sha256"] or 0)

    difference = (
        actual_files - inventory_present
        if actual_files is not None
        else None
    )

    if actual_files is None:
        status = "UNKNOWN"
        recommendation = "VERIFY_MOUNT_OR_COUNT"

    elif actual_files == inventory_present:
        status = "FRESH"
        recommendation = "NO_ACTION"

    elif actual_files < inventory_present:
        status = "STALE_DELETIONS"
        recommendation = "RECONCILE_REQUIRED"

    else:
        status = "STALE_ADDITIONS"
        recommendation = "SCAN_REQUIRED"

    results.append(
        {
            "name": target["name"],
            "path": path,
            "mounted": mounted,
            "mount_source": mount_source,
            "filesystem": filesystem,
            "actual_files": actual_files,
            "count_error": count_error,
            "count_elapsed_seconds": elapsed,
            "inventory": {
                "total": inventory_total,
                "present": inventory_present,
                "missing": inventory_missing,
                "with_sha256": with_sha256,
            },
            "difference_actual_minus_present": difference,
            "status": status,
            "recommendation": recommendation,
        }
    )

archive_service_counts = {
    "immich": connection.execute(
        """
        SELECT COUNT(*)
        FROM files
        WHERE path LIKE '/mnt/storage/Archive/Immich/%'
          AND is_missing = 0
        """
    ).fetchone()[0],
    "nextcloud": connection.execute(
        """
        SELECT COUNT(*)
        FROM files
        WHERE path LIKE '/mnt/storage/Archive/Nextcloud/%'
          AND is_missing = 0
        """
    ).fetchone()[0],
}

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

connection.close()

payload = {
    "mode": "read-only-storage-freshness-audit",
    "database_integrity": integrity,
    "targets": results,
    "archive_service_inventory": archive_service_counts,
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "missing_flags_modified": False,
        "hash_queue_modified": False,
        "duplicate_queue_modified": False,
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
            "database_integrity": integrity,
            "targets": results,
            "archive_service_inventory":
                archive_service_counts,
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Storage freshness report: ${REPORT_FILE}" >&2
