#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/duplicate-root-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-duplicate-root-preview.json"

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

eligible = """
sha256 IS NOT NULL
AND length(trim(sha256)) > 0
AND is_missing = 0
AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
"""

root_summary = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            root_path,
            COUNT(*) AS hashed_files,
            ROUND(
                SUM(size_bytes) / 1073741824.0,
                2
            ) AS hashed_gb
        FROM files
        WHERE {eligible}
        GROUP BY root_path
        ORDER BY hashed_files DESC
        """
    )
]

internal_duplicates = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            root_path,
            COUNT(*) AS duplicate_groups,
            SUM(file_count) AS duplicate_files,
            ROUND(
                SUM(size_bytes * (file_count - 1))
                / 1073741824.0,
                2
            ) AS reclaimable_gb
        FROM (
            SELECT
                root_path,
                sha256,
                COUNT(*) AS file_count,
                MAX(size_bytes) AS size_bytes
            FROM files
            WHERE {eligible}
            GROUP BY root_path, sha256
            HAVING COUNT(*) > 1
        )
        GROUP BY root_path
        ORDER BY reclaimable_gb DESC
        """
    )
]

cross_root_summary = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            root_count,
            COUNT(*) AS duplicate_groups,
            SUM(file_count) AS duplicate_files,
            ROUND(
                SUM(size_bytes * (file_count - 1))
                / 1073741824.0,
                2
            ) AS reclaimable_gb
        FROM (
            SELECT
                sha256,
                COUNT(DISTINCT root_path) AS root_count,
                COUNT(*) AS file_count,
                MAX(size_bytes) AS size_bytes
            FROM files
            WHERE {eligible}
            GROUP BY sha256
            HAVING COUNT(DISTINCT root_path) > 1
        )
        GROUP BY root_count
        ORDER BY root_count
        """
    )
]

root_pairs = [
    dict(row)
    for row in connection.execute(
        f"""
        WITH hashed AS (
            SELECT
                sha256,
                root_path,
                MAX(size_bytes) AS size_bytes
            FROM files
            WHERE {eligible}
            GROUP BY sha256, root_path
        )
        SELECT
            a.root_path AS root_a,
            b.root_path AS root_b,
            COUNT(*) AS shared_hashes,
            ROUND(
                SUM(a.size_bytes) / 1073741824.0,
                2
            ) AS shared_gb
        FROM hashed a
        JOIN hashed b
          ON a.sha256 = b.sha256
         AND a.root_path < b.root_path
        GROUP BY a.root_path, b.root_path
        ORDER BY shared_gb DESC
        """
    )
]

largest_cross_root_groups = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            substr(sha256, 1, 16) AS sha256_prefix,
            COUNT(*) AS file_count,
            COUNT(DISTINCT root_path) AS root_count,
            MAX(size_bytes) AS file_size_bytes,
            ROUND(
                MAX(size_bytes) * (COUNT(*) - 1)
                / 1073741824.0,
                3
            ) AS reclaimable_gb
        FROM files
        WHERE {eligible}
        GROUP BY sha256
        HAVING COUNT(DISTINCT root_path) > 1
        ORDER BY
            MAX(size_bytes) * (COUNT(*) - 1) DESC
        LIMIT 20
        """
    )
]

connection.close()

payload = {
    "mode": "read-only-preview",
    "policy": {
        "archive_preferred_as_master": True,
        "immich_excluded": True,
        "nextcloud_excluded": True,
        "automatic_deletion": False,
    },
    "root_summary": root_summary,
    "internal_duplicates": internal_duplicates,
    "cross_root_summary": cross_root_summary,
    "root_pairs": root_pairs,
    "largest_cross_root_groups": largest_cross_root_groups,
}

report_path.write_text(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)

print(json.dumps(payload, ensure_ascii=False, indent=2))
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
