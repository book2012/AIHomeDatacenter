#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
LIMIT="${1:-1000}"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/incremental-duplicate-queue-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-incremental-duplicate-queue.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

if ! [[ "${LIMIT}" =~ ^[0-9]+$ ]] ||
   (( LIMIT < 1 || LIMIT > 10000 )); then
    echo "LIMIT must be between 1 and 10000." >&2
    exit 2
fi

python3 - "${DB}" "${REPORT_FILE}" "${LIMIT}" <<'PYTHON'
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
connection.execute("PRAGMA query_only = ON")

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

schema_row = connection.execute(
    """
    SELECT value
    FROM schema_metadata
    WHERE key = 'schema_version'
    """
).fetchone()

schema_version = (
    schema_row["value"]
    if schema_row
    else "unknown"
)

required_tables = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (
              'files',
              'duplicate_processing',
              'duplicate_groups'
          )
        """
    )
}

missing_tables = sorted(
    {
        "files",
        "duplicate_processing",
        "duplicate_groups",
    } - required_tables
)

if missing_tables:
    connection.close()
    raise SystemExit(
        "Required tables missing: "
        + ", ".join(missing_tables)
    )

eligible_filter = """
files.hash_status IN ('done', 'completed')
AND files.sha256 IS NOT NULL
AND length(trim(files.sha256)) = 64
AND files.sha256 NOT GLOB '*[^0-9a-fA-F]*'
AND files.is_missing = 0
AND files.path NOT LIKE '/mnt/storage/Archive/Immich/%'
AND files.path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
AND files.path NOT LIKE '/opt/aihomedatacenter/tests/%'
"""

eligible_files = connection.execute(
    f"""
    SELECT COUNT(*)
    FROM files
    WHERE {eligible_filter}
    """
).fetchone()[0]

already_tracked = connection.execute(
    f"""
    SELECT COUNT(*)
    FROM files
    JOIN duplicate_processing
      ON duplicate_processing.file_id = files.id
    WHERE {eligible_filter}
    """
).fetchone()[0]

queue_candidates = connection.execute(
    f"""
    SELECT COUNT(*)
    FROM files
    LEFT JOIN duplicate_processing
      ON duplicate_processing.file_id = files.id
    WHERE {eligible_filter}
      AND duplicate_processing.file_id IS NULL
    """
).fetchone()[0]

excluded_immich = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status IN ('done', 'completed')
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) = 64
      AND is_missing = 0
      AND path LIKE '/mnt/storage/Archive/Immich/%'
    """
).fetchone()[0]

excluded_nextcloud = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status IN ('done', 'completed')
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) = 64
      AND is_missing = 0
      AND path LIKE '/mnt/storage/Archive/Nextcloud/%'
    """
).fetchone()[0]

by_root = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            files.root_path,
            COUNT(*) AS queue_files,
            ROUND(
                SUM(files.size_bytes) / 1073741824.0,
                2
            ) AS queue_gb
        FROM files
        LEFT JOIN duplicate_processing
          ON duplicate_processing.file_id = files.id
        WHERE {eligible_filter}
          AND duplicate_processing.file_id IS NULL
        GROUP BY files.root_path
        ORDER BY queue_files DESC
        """
    )
]

queue = [
    dict(row)
    for row in connection.execute(
        f"""
        SELECT
            files.id AS file_id,
            files.root_path,
            files.path,
            files.size_bytes,
            files.sha256,
            files.hash_updated_at
        FROM files
        LEFT JOIN duplicate_processing
          ON duplicate_processing.file_id = files.id
        WHERE {eligible_filter}
          AND duplicate_processing.file_id IS NULL
        ORDER BY files.id ASC
        LIMIT ?
        """,
        (limit,),
    )
]

existing_duplicate_groups = connection.execute(
    "SELECT COUNT(*) FROM duplicate_groups"
).fetchone()[0]

connection.close()

payload = {
    "mode": "read-only-incremental-queue-preview",
    "schema_version": schema_version,
    "database_integrity": integrity,
    "summary": {
        "eligible_files": eligible_files,
        "already_tracked": already_tracked,
        "queue_candidates": queue_candidates,
        "preview_files": len(queue),
        "existing_duplicate_groups": (
            existing_duplicate_groups
        ),
        "excluded_immich": excluded_immich,
        "excluded_nextcloud": excluded_nextcloud,
    },
    "by_root": by_root,
    "queue": queue,
    "policy": {
        "limit": limit,
        "order": "file_id_ascending",
        "initial_backfill_required": (
            queue_candidates > 0
        ),
        "incremental_after_backfill": True,
        "automatic_deletion": False,
    },
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "processing_rows_created": False,
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
            "schema_version": schema_version,
            "database_integrity": integrity,
            "summary": payload["summary"],
            "policy": payload["policy"],
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Incremental queue preview: ${REPORT_FILE}" >&2
