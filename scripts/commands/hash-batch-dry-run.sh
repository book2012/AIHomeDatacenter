#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

MAX_FILES="${1:-100}"
MAX_BYTES="${2:-1073741824}"

STAMP="$(date '+%Y%m%d-%H%M%S')"
BATCH_ID="hash-batch-${STAMP}"

REPORT_FILE="${REPORT_DIR}/${BATCH_ID}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-batch-dry-run.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

if ! [[ "${MAX_FILES}" =~ ^[0-9]+$ ]] ||
   (( MAX_FILES < 1 || MAX_FILES > 1000 )); then
    echo "MAX_FILES must be between 1 and 1000." >&2
    exit 2
fi

if ! [[ "${MAX_BYTES}" =~ ^[0-9]+$ ]] ||
   (( MAX_BYTES < 1 || MAX_BYTES > 10737418240 )); then
    echo "MAX_BYTES must be between 1 and 10737418240." >&2
    exit 2
fi

python3 - \
    "${DB}" \
    "${REPORT_FILE}" \
    "${BATCH_ID}" \
    "${MAX_FILES}" \
    "${MAX_BYTES}" <<'PYTHON'
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
report_path = Path(sys.argv[2]).resolve()
batch_id = sys.argv[3]
max_files = int(sys.argv[4])
max_bytes = int(sys.argv[5])

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

rows = connection.execute(
    """
    SELECT
        id,
        root_path,
        path,
        filename,
        size_bytes,
        modified_at
    FROM files
    WHERE hash_status = 'pending'
      AND is_missing = 0
      AND (
          sha256 IS NULL
          OR length(trim(sha256)) = 0
      )
      AND size_bytes > 0
      AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
      AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
    ORDER BY
        size_bytes ASC,
        id ASC
    LIMIT 50000
    """
).fetchall()

connection.close()

selected = []
selected_bytes = 0
skipped_missing = 0
skipped_size_mismatch = 0
skipped_byte_limit = 0

for row in rows:
    if len(selected) >= max_files:
        break

    path = row["path"]
    expected_size = int(row["size_bytes"])

    if not os.path.isfile(path):
        skipped_missing += 1
        continue

    actual_size = os.path.getsize(path)

    if actual_size != expected_size:
        skipped_size_mismatch += 1
        continue

    if selected_bytes + expected_size > max_bytes:
        skipped_byte_limit += 1
        continue

    selected.append(dict(row))
    selected_bytes += expected_size

results = []
batch_started = time.monotonic()
started_at = datetime.now(timezone.utc).isoformat()

for index, item in enumerate(selected, start=1):
    file_started = time.monotonic()
    digest = hashlib.sha256()
    bytes_read = 0
    error = None
    calculated_sha256 = None

    try:
        with Path(item["path"]).open("rb") as handle:
            while True:
                block = handle.read(1024 * 1024)

                if not block:
                    break

                digest.update(block)
                bytes_read += len(block)

        if bytes_read != int(item["size_bytes"]):
            raise RuntimeError(
                f"Bytes read mismatch: "
                f"expected={item['size_bytes']} "
                f"actual={bytes_read}"
            )

        calculated_sha256 = digest.hexdigest()

    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"

    results.append(
        {
            "sequence": index,
            "file_id": item["id"],
            "root_path": item["root_path"],
            "path": item["path"],
            "expected_size": item["size_bytes"],
            "bytes_read": bytes_read,
            "calculated_sha256": calculated_sha256,
            "success": error is None,
            "error": error,
            "elapsed_seconds": round(
                time.monotonic() - file_started,
                4,
            ),
        }
    )

finished_at = datetime.now(timezone.utc).isoformat()
elapsed_seconds = round(
    time.monotonic() - batch_started,
    4,
)

successful = [
    item
    for item in results
    if item["success"]
]

failed = [
    item
    for item in results
    if not item["success"]
]

payload = {
    "schema_version": 1,
    "mode": "batch-dry-run",
    "batch_id": batch_id,
    "started_at": started_at,
    "finished_at": finished_at,
    "limits": {
        "max_files": max_files,
        "max_bytes": max_bytes,
    },
    "selection": {
        "database_candidates_checked": len(rows),
        "selected_files": len(selected),
        "selected_bytes": selected_bytes,
        "skipped_missing": skipped_missing,
        "skipped_size_mismatch": skipped_size_mismatch,
        "skipped_byte_limit": skipped_byte_limit,
    },
    "summary": {
        "processed_files": len(results),
        "successful_files": len(successful),
        "failed_files": len(failed),
        "bytes_read": sum(
            item["bytes_read"]
            for item in results
        ),
        "elapsed_seconds": elapsed_seconds,
    },
    "results": results,
    "resume": {
        "supported": True,
        "strategy": (
            "successful file IDs may be excluded "
            "from a later retry batch"
        ),
        "completed_file_ids": [
            item["file_id"]
            for item in successful
        ],
        "failed_file_ids": [
            item["file_id"]
            for item in failed
        ],
    },
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "hashes_persisted": False,
        "automatic_deletion": False,
        "immich_excluded": True,
        "nextcloud_excluded": True,
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
            "batch_id": batch_id,
            "selection": payload["selection"],
            "summary": payload["summary"],
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)

if failed:
    raise SystemExit(1)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Hash batch dry-run report: ${REPORT_FILE}" >&2
