#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-audit-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-audit.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

python3 - "${DB}" "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

total_files = connection.execute(
    "SELECT COUNT(*) FROM files"
).fetchone()[0]

status_summary = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            COALESCE(hash_status, '[NULL]') AS hash_status,
            COUNT(*) AS files,
            ROUND(
                SUM(size_bytes) / 1073741824.0,
                2
            ) AS size_gb
        FROM files
        GROUP BY hash_status
        ORDER BY files DESC
        """
    )
]

valid_sha256 = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE sha256 GLOB
        '[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*'
      AND length(sha256) = 64
    """
).fetchone()[0]

empty_sha256 = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE sha256 IS NULL
       OR length(trim(sha256)) = 0
    """
).fetchone()[0]

invalid_sha256 = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE sha256 IS NOT NULL
      AND length(trim(sha256)) > 0
      AND (
          length(sha256) != 64
          OR sha256 GLOB '*[^0-9a-fA-F]*'
      )
    """
).fetchone()[0]

done_without_hash = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status IN ('done', 'completed')
      AND (
          sha256 IS NULL
          OR length(trim(sha256)) = 0
      )
    """
).fetchone()[0]

pending_with_hash = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status = 'pending'
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) > 0
    """
).fetchone()[0]

missing_with_hash = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status = 'missing'
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) > 0
    """
).fetchone()[0]

size_mismatch_groups = connection.execute(
    """
    SELECT COUNT(*)
    FROM (
        SELECT sha256
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) = 64
        GROUP BY sha256
        HAVING COUNT(DISTINCT size_bytes) > 1
    )
    """
).fetchone()[0]

duplicate_hash_groups = connection.execute(
    """
    SELECT COUNT(*)
    FROM (
        SELECT sha256
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) = 64
          AND is_missing = 0
        GROUP BY sha256
        HAVING COUNT(*) > 1
    )
    """
).fetchone()[0]

root_progress = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            root_path,
            COUNT(*) AS total_files,
            SUM(
                CASE
                    WHEN sha256 IS NOT NULL
                     AND length(trim(sha256)) = 64
                    THEN 1
                    ELSE 0
                END
            ) AS hashed_files,
            SUM(
                CASE
                    WHEN hash_status = 'pending'
                    THEN 1
                    ELSE 0
                END
            ) AS pending_files,
            ROUND(
                100.0 * SUM(
                    CASE
                        WHEN sha256 IS NOT NULL
                         AND length(trim(sha256)) = 64
                        THEN 1
                        ELSE 0
                    END
                ) / COUNT(*),
                2
            ) AS hashed_percent
        FROM files
        GROUP BY root_path
        ORDER BY total_files DESC
        """
    )
]

pending_priority = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            root_path,
            COUNT(*) AS pending_files,
            ROUND(
                SUM(size_bytes) / 1073741824.0,
                2
            ) AS pending_gb,
            ROUND(
                AVG(size_bytes) / 1048576.0,
                2
            ) AS average_mb
        FROM files
        WHERE hash_status = 'pending'
          AND is_missing = 0
          AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
          AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
        GROUP BY root_path
        ORDER BY pending_gb ASC
        """
    )
]

largest_pending_files = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            root_path,
            path,
            size_bytes,
            ROUND(size_bytes / 1073741824.0, 3) AS size_gb
        FROM files
        WHERE hash_status = 'pending'
          AND is_missing = 0
          AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
          AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
        ORDER BY size_bytes DESC
        LIMIT 30
        """
    )
]

connection.close()

issues = {
    "invalid_sha256": invalid_sha256,
    "done_without_hash": done_without_hash,
    "pending_with_hash": pending_with_hash,
    "missing_with_hash": missing_with_hash,
    "same_sha256_different_size_groups": size_mismatch_groups,
}

issue_count = sum(issues.values())

payload = {
    "mode": "read-only-audit",
    "database_integrity": integrity,
    "database_modified": False,
    "files_modified": False,
    "total_files": total_files,
    "valid_sha256": valid_sha256,
    "empty_sha256": empty_sha256,
    "duplicate_hash_groups": duplicate_hash_groups,
    "status_summary": status_summary,
    "issues": issues,
    "issue_count": issue_count,
    "root_progress": root_progress,
    "pending_priority": pending_priority,
    "largest_pending_files": largest_pending_files,
    "policy": {
        "existing_sha256_preserved": True,
        "immich_excluded": True,
        "nextcloud_excluded": True,
        "automatic_hashing": False,
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
            "database_integrity": integrity,
            "total_files": total_files,
            "valid_sha256": valid_sha256,
            "empty_sha256": empty_sha256,
            "duplicate_hash_groups": duplicate_hash_groups,
            "issues": issues,
            "issue_count": issue_count,
            "database_modified": False,
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
