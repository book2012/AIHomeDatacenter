#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
REPORT_FILE="${REPORT_DIR}/inventory-status-$(date '+%Y%m%d-%H%M%S').json"
LATEST_LINK="${REPORT_DIR}/latest-inventory-status.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

python3 - "${DB}" "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])

connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
connection.row_factory = sqlite3.Row

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

roots = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            root_path,
            COUNT(*) AS files,
            ROUND(
                SUM(size_bytes) / 1073741824.0,
                2
            ) AS size_gb
        FROM files
        GROUP BY root_path
        ORDER BY files DESC
        """
    )
]

hash_status = {
    row["hash_status"]: row["files"]
    for row in connection.execute(
        """
        SELECT
            COALESCE(hash_status, '[NULL]') AS hash_status,
            COUNT(*) AS files
        FROM files
        GROUP BY hash_status
        """
    )
}

missing_matrix = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            COALESCE(hash_status, '[NULL]') AS hash_status,
            is_missing,
            COUNT(*) AS files
        FROM files
        GROUP BY hash_status, is_missing
        ORDER BY hash_status, is_missing
        """
    )
]

latest_scans = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            id,
            root_path,
            status,
            files_found,
            started_at,
            finished_at,
            error_message
        FROM scan_runs
        ORDER BY id DESC
        LIMIT 10
        """
    )
]

duplicate_groups = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

duplicate_files = connection.execute(
    "SELECT COUNT(*) FROM duplicate_files"
).fetchone()[0]

total_files = connection.execute(
    "SELECT COUNT(*) FROM files"
).fetchone()[0]

connection.close()

payload = {
    "schema_version": 1,
    "database_integrity": integrity,
    "total_files": total_files,
    "roots": roots,
    "hash_status": hash_status,
    "missing_matrix": missing_matrix,
    "duplicates": {
        "groups": duplicate_groups,
        "files": duplicate_files,
    },
    "latest_scans": latest_scans,
    "warnings": [
        "Legacy hash_status values must not be migrated automatically.",
        "Archive, Immich and Nextcloud scans remain disabled.",
    ],
}

report_path.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

print(json.dumps(payload, ensure_ascii=False, indent=2))
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
