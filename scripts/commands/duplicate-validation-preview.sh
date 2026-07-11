#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/duplicate-validation-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-duplicate-validation.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

python3 - "${DB}" "${REPORT_FILE}" <<'PYTHON'
import json
import os
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()

connection = sqlite3.connect(
    f"file:{db_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

size_mismatches = [
    dict(row)
    for row in connection.execute(
        """
        SELECT
            substr(sha256, 1, 16) AS sha256_prefix,
            COUNT(*) AS file_count,
            COUNT(DISTINCT size_bytes) AS size_variants,
            MIN(size_bytes) AS min_size,
            MAX(size_bytes) AS max_size
        FROM files
        WHERE sha256 IS NOT NULL
          AND length(trim(sha256)) > 0
          AND is_missing = 0
        GROUP BY sha256
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT size_bytes) > 1
        ORDER BY file_count DESC
        LIMIT 500
        """
    )
]

rows = connection.execute(
    """
    WITH archive_hashes AS (
        SELECT
            sha256,
            MIN(path) AS archive_path,
            MAX(size_bytes) AS archive_size
        FROM files
        WHERE root_path = '/mnt/storage/Archive'
          AND sha256 IS NOT NULL
          AND length(trim(sha256)) > 0
          AND is_missing = 0
          AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
          AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
        GROUP BY sha256
    )
    SELECT
        files.sha256,
        files.root_path AS candidate_root,
        files.path AS candidate_path,
        files.size_bytes AS candidate_db_size,
        archive_hashes.archive_path,
        archive_hashes.archive_size
    FROM files
    JOIN archive_hashes
      ON archive_hashes.sha256 = files.sha256
    WHERE files.root_path IN ('/mnt/exHDD1', '/mnt/exHDD2')
      AND files.is_missing = 0
    ORDER BY files.size_bytes DESC
    LIMIT 200
    """
).fetchall()

connection.close()

samples = []

for row in rows:
    candidate_path = row["candidate_path"]
    archive_path = row["archive_path"]

    candidate_exists = os.path.isfile(candidate_path)
    archive_exists = os.path.isfile(archive_path)

    candidate_actual_size = (
        os.path.getsize(candidate_path)
        if candidate_exists
        else None
    )

    archive_actual_size = (
        os.path.getsize(archive_path)
        if archive_exists
        else None
    )

    samples.append(
        {
            "sha256_prefix": row["sha256"][:16],
            "candidate_root": row["candidate_root"],
            "candidate_path": candidate_path,
            "archive_path": archive_path,
            "candidate_exists": candidate_exists,
            "archive_exists": archive_exists,
            "db_size_match": (
                row["candidate_db_size"]
                == row["archive_size"]
            ),
            "actual_size_match": (
                candidate_exists
                and archive_exists
                and candidate_actual_size
                == archive_actual_size
            ),
        }
    )

summary = {
    "sample_count": len(samples),
    "candidate_exists": sum(
        item["candidate_exists"] for item in samples
    ),
    "archive_exists": sum(
        item["archive_exists"] for item in samples
    ),
    "both_exist": sum(
        item["candidate_exists"] and item["archive_exists"]
        for item in samples
    ),
    "db_size_match": sum(
        item["db_size_match"] for item in samples
    ),
    "actual_size_match": sum(
        item["actual_size_match"] for item in samples
    ),
    "invalid_samples": sum(
        not item["candidate_exists"]
        or not item["archive_exists"]
        or not item["db_size_match"]
        or not item["actual_size_match"]
        for item in samples
    ),
}

payload = {
    "mode": "read-only-validation",
    "database_modified": False,
    "files_modified": False,
    "database_size_mismatch_group_count": len(size_mismatches),
    "database_size_mismatch_groups": size_mismatches,
    "summary": summary,
    "samples": samples,
    "policy": {
        "archive_is_master": True,
        "immich_excluded": True,
        "nextcloud_excluded": True,
        "automatic_delete": False,
        "user_approval_required": True,
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

print(json.dumps(summary, ensure_ascii=False, indent=2))
print("Size mismatch groups:", len(size_mismatches))
print("Database modified: False")
print("Files modified: False")
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
