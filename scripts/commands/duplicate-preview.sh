#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
REPORT_FILE="${REPORT_DIR}/duplicate-preview-$(date '+%Y%m%d-%H%M%S').json"
LATEST_LINK="${REPORT_DIR}/latest-duplicate-preview.json"

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

connection = sqlite3.connect(
    f"file:{db_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

hashed_files = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE sha256 IS NOT NULL
      AND length(trim(sha256)) > 0
      AND is_missing = 0
    """
).fetchone()[0]

duplicate_groups = connection.execute(
    """
    SELECT COUNT(*)
    FROM (
        SELECT sha256
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) > 0
          AND is_missing = 0
        GROUP BY sha256
        HAVING COUNT(*) > 1
    )
    """
).fetchone()[0]

summary = connection.execute(
    """
    SELECT
        COALESCE(SUM(file_count), 0) AS duplicate_files,
        COALESCE(SUM(
            size_bytes * (file_count - 1)
        ), 0) AS reclaimable_bytes
    FROM (
        SELECT
            sha256,
            COUNT(*) AS file_count,
            MAX(size_bytes) AS size_bytes
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) > 0
          AND is_missing = 0
        GROUP BY sha256
        HAVING COUNT(*) > 1
    )
    """
).fetchone()

largest_groups = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            substr(sha256, 1, 16) AS sha256_prefix,
            COUNT(*) AS file_count,
            MAX(size_bytes) AS file_size_bytes,
            MAX(size_bytes) * (COUNT(*) - 1)
                AS reclaimable_bytes
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) > 0
          AND is_missing = 0
        GROUP BY sha256
        HAVING COUNT(*) > 1
        ORDER BY reclaimable_bytes DESC
        LIMIT 20
        """
    )
]

connection.close()

reclaimable_bytes = int(summary["reclaimable_bytes"])
duplicate_files = int(summary["duplicate_files"])

payload = {
    "mode": "read-only-preview",
    "hashed_files": hashed_files,
    "duplicate_groups": duplicate_groups,
    "duplicate_files": duplicate_files,
    "reclaimable_bytes": reclaimable_bytes,
    "reclaimable_gb": round(
        reclaimable_bytes / 1073741824,
        2,
    ),
    "largest_groups": largest_groups,
    "safety": {
        "database_modified": False,
        "files_deleted": False,
        "tables_updated": False,
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
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
