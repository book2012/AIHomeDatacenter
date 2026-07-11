#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"

JSON_REPORT="${REPORT_DIR}/duplicate-cleanup-preview-${STAMP}.json"
CSV_REPORT="${REPORT_DIR}/duplicate-cleanup-preview-${STAMP}.csv"

LATEST_JSON="${REPORT_DIR}/latest-duplicate-cleanup-preview.json"
LATEST_CSV="${REPORT_DIR}/latest-duplicate-cleanup-preview.csv"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

python3 - \
    "${DB}" \
    "${JSON_REPORT}" \
    "${CSV_REPORT}" <<'PYTHON'
from __future__ import annotations

import csv
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
json_path = Path(sys.argv[2]).resolve()
csv_path = Path(sys.argv[3]).resolve()

archive_root = "/mnt/storage/Archive"
candidate_roots = {
    "/mnt/exHDD1",
    "/mnt/exHDD2",
}

excluded_prefixes = (
    "/mnt/storage/Archive/Immich/",
    "/mnt/storage/Archive/Nextcloud/",
)

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

rows = connection.execute(
    """
    WITH archive_hashes AS (
        SELECT
            sha256,
            MIN(path) AS archive_path,
            MAX(size_bytes) AS size_bytes
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
        files.size_bytes,
        archive_hashes.archive_path
    FROM files
    JOIN archive_hashes
      ON archive_hashes.sha256 = files.sha256
    WHERE files.root_path IN ('/mnt/exHDD1', '/mnt/exHDD2')
      AND files.is_missing = 0
      AND files.sha256 IS NOT NULL
      AND length(trim(files.sha256)) > 0
    ORDER BY
        files.size_bytes DESC,
        files.root_path,
        files.path
    """
).fetchall()

connection.close()

candidates = []

for row in rows:
    candidate_path = row["candidate_path"]
    archive_path = row["archive_path"]

    if candidate_path.startswith(excluded_prefixes):
        continue

    candidates.append(
        {
            "sha256": row["sha256"],
            "sha256_prefix": row["sha256"][:16],
            "candidate_root": row["candidate_root"],
            "candidate_path": candidate_path,
            "archive_keep_path": archive_path,
            "size_bytes": row["size_bytes"],
            "size_mb": round(
                row["size_bytes"] / 1048576,
                2,
            ),
            "recommendation": "REVIEW_CANDIDATE",
            "automatic_delete": False,
        }
    )

root_counts = Counter(
    item["candidate_root"]
    for item in candidates
)

root_bytes = Counter()

for item in candidates:
    root_bytes[item["candidate_root"]] += item["size_bytes"]

total_bytes = sum(
    item["size_bytes"]
    for item in candidates
)

largest_candidates = candidates[:100]

payload = {
    "mode": "read-only-preview",
    "policy": {
        "master_root": archive_root,
        "archive_action": "KEEP",
        "candidate_roots": sorted(candidate_roots),
        "immich_excluded": True,
        "nextcloud_excluded": True,
        "automatic_delete": False,
        "user_approval_required": True,
    },
    "summary": {
        "candidate_files": len(candidates),
        "reclaimable_bytes": total_bytes,
        "reclaimable_gb": round(
            total_bytes / 1073741824,
            2,
        ),
        "by_root": {
            root: {
                "candidate_files": root_counts[root],
                "reclaimable_bytes": root_bytes[root],
                "reclaimable_gb": round(
                    root_bytes[root] / 1073741824,
                    2,
                ),
            }
            for root in sorted(candidate_roots)
        },
    },
    "largest_candidates": largest_candidates,
    "warnings": [
        "This report does not delete files.",
        "Path existence must be verified before approval.",
        "Archive is treated as the master repository.",
        "Immich and Nextcloud paths are excluded.",
    ],
}

json_path.write_text(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)

with csv_path.open(
    "w",
    newline="",
    encoding="utf-8",
) as handle:
    writer = csv.DictWriter(
        handle,
        fieldnames=[
            "sha256",
            "candidate_root",
            "candidate_path",
            "archive_keep_path",
            "size_bytes",
            "size_mb",
            "recommendation",
            "automatic_delete",
        ],
    )

    writer.writeheader()
    writer.writerows(
        {
            key: item[key]
            for key in writer.fieldnames
        }
        for item in candidates
    )

print(
    json.dumps(
        payload["summary"],
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${JSON_REPORT}" "${LATEST_JSON}"
ln -sfn "${CSV_REPORT}" "${LATEST_CSV}"

echo "JSON report: ${JSON_REPORT}"
echo "CSV report: ${CSV_REPORT}"
