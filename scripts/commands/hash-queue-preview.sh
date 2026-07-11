#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-queue-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-queue-preview.json"

LIMIT="${1:-1000}"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

if ! [[ "${LIMIT}" =~ ^[0-9]+$ ]] || (( LIMIT < 1 || LIMIT > 10000 )); then
    echo "Limit must be between 1 and 10000." >&2
    exit 2
fi

python3 - \
    "${DB}" \
    "${REPORT_FILE}" \
    "${LIMIT}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()
limit = int(sys.argv[3])

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

filter_sql = """
hash_status = 'pending'
AND is_missing = 0
AND (
    sha256 IS NULL
    OR length(trim(sha256)) = 0
)
AND size_bytes > 0
AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
"""

eligible_count = connection.execute(
    f"""
    SELECT COUNT(*)
    FROM files
    WHERE {filter_sql}
    """
).fetchone()[0]

eligible_bytes = connection.execute(
    f"""
    SELECT COALESCE(SUM(size_bytes), 0)
    FROM files
    WHERE {filter_sql}
    """
).fetchone()[0]

by_root = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            root_path,
            COUNT(*) AS files,
            ROUND(
                SUM(size_bytes) / 1073741824.0,
                2
            ) AS size_gb,
            ROUND(
                AVG(size_bytes) / 1048576.0,
                2
            ) AS average_mb
        FROM files
        WHERE {filter_sql}
        GROUP BY root_path
        ORDER BY size_gb ASC
        """
    )
]

queue = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            id AS file_id,
            root_path,
            path,
            filename,
            size_bytes,
            modified_at
        FROM files
        WHERE {filter_sql}
        ORDER BY
            size_bytes ASC,
            id ASC
        LIMIT ?
        """,
        (limit,),
    )
]

connection.close()

queue_bytes = sum(
    int(item["size_bytes"])
    for item in queue
)

payload = {
    "mode": "read-only-preview",
    "queue_policy": {
        "order": "smallest-files-first",
        "limit": limit,
        "zero_byte_files_excluded": True,
        "immich_excluded": True,
        "nextcloud_excluded": True,
        "existing_sha256_preserved": True,
        "automatic_hashing": False,
    },
    "eligible": {
        "files": eligible_count,
        "bytes": eligible_bytes,
        "size_gb": round(
            eligible_bytes / 1073741824,
            2,
        ),
    },
    "preview": {
        "files": len(queue),
        "bytes": queue_bytes,
        "size_gb": round(
            queue_bytes / 1073741824,
            4,
        ),
    },
    "by_root": by_root,
    "queue": queue,
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "sha256_calculated": False,
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
            "eligible": payload["eligible"],
            "preview": payload["preview"],
            "by_root": by_root,
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Hash queue preview: ${REPORT_FILE}" >&2
