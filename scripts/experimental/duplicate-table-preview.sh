#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/duplicate-table-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-duplicate-table-preview.json"

mkdir -p "${REPORT_DIR}"

python3 - "${DB}" "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()

con = sqlite3.connect(
    f"file:{db_path}?mode=ro",
    uri=True,
    timeout=30,
)

con.row_factory = sqlite3.Row
con.execute("PRAGMA query_only = ON")
con.execute("PRAGMA temp_store = MEMORY")
con.execute("PRAGMA cache_size = -200000")

eligible = """
sha256 IS NOT NULL
AND length(trim(sha256)) = 64
AND is_missing = 0
AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
"""

integrity = con.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

summary = con.execute(
    f"""
    SELECT
        COUNT(*) AS duplicate_groups,
        COALESCE(SUM(file_count), 0) AS duplicate_files,
        COALESCE(SUM(reclaimable_bytes), 0) AS reclaimable_bytes
    FROM (
        SELECT
            sha256,
            COUNT(*) AS file_count,
            MAX(size_bytes) * (COUNT(*) - 1)
                AS reclaimable_bytes
        FROM files
        WHERE {eligible}
        GROUP BY sha256
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT size_bytes) = 1
    )
    """
).fetchone()

size_mismatch_count = con.execute(
    f"""
    SELECT COUNT(*)
    FROM (
        SELECT sha256
        FROM files
        WHERE {eligible}
        GROUP BY sha256
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT size_bytes) > 1
    )
    """
).fetchone()[0]

largest_groups = [
    dict(row)
    for row in con.execute(
        f"""
        SELECT
            sha256,
            substr(sha256, 1, 16) AS sha256_prefix,
            COUNT(*) AS file_count,
            MAX(size_bytes) AS file_size_bytes,
            MAX(size_bytes) * COUNT(*) AS total_size_bytes,
            MAX(size_bytes) * (COUNT(*) - 1)
                AS reclaimable_bytes,
            COUNT(DISTINCT root_path) AS root_count
        FROM files
        WHERE {eligible}
        GROUP BY sha256
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT size_bytes) = 1
        ORDER BY reclaimable_bytes DESC
        LIMIT 100
        """
    )
]

detail_groups = []

for group in largest_groups[:20]:
    files = [
        dict(row)
        for row in con.execute(
            """
            SELECT
                id AS file_id,
                root_path,
                path,
                size_bytes
            FROM files
            WHERE sha256 = ?
              AND is_missing = 0
              AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
              AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
            ORDER BY root_path, path
            LIMIT 100
            """,
            (group["sha256"],),
        )
    ]

    detail_groups.append(
        {
            **group,
            "files": files,
        }
    )

con.close()

reclaimable_bytes = int(summary["reclaimable_bytes"])

payload = {
    "mode": "fast-read-only-preview",
    "database_integrity": integrity,
    "summary": {
        "duplicate_groups": int(summary["duplicate_groups"]),
        "duplicate_files": int(summary["duplicate_files"]),
        "reclaimable_bytes": reclaimable_bytes,
        "reclaimable_gb": round(
            reclaimable_bytes / 1073741824,
            2,
        ),
        "size_mismatch_groups": int(size_mismatch_count),
    },
    "largest_groups": largest_groups,
    "detailed_groups": detail_groups,
    "limits": {
        "largest_groups": 100,
        "detailed_groups": 20,
        "files_per_detailed_group": 100,
    },
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "duplicate_tables_modified": False,
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

print(json.dumps(payload["summary"], indent=2))
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Preview report: ${REPORT_FILE}"
