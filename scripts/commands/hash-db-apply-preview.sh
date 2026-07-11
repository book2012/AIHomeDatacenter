#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
DRY_RUN_REPORT="${PROJECT_ROOT}/reports/storage-agent/latest-hash-dry-run.json"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-db-apply-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-db-apply-preview.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Inventory database not found: ${DB}" >&2
    exit 1
fi

if [[ ! -f "${DRY_RUN_REPORT}" ]]; then
    echo "Hash dry-run report not found." >&2
    echo "Run: scripts/runtime.sh hash-worker-dry-run 10 104857600" >&2
    exit 1
fi

python3 - \
    "${DB}" \
    "${DRY_RUN_REPORT}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1]).resolve()
dry_run_path = Path(sys.argv[2]).resolve()
report_path = Path(sys.argv[3]).resolve()

dry_run = json.loads(
    dry_run_path.read_text(encoding="utf-8")
)

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

items = []

for result in dry_run.get("results", []):
    file_id = result.get("file_id")
    calculated_sha256 = result.get("calculated_sha256")
    dry_run_success = bool(result.get("success"))
    bytes_read = int(result.get("bytes_read", 0))
    expected_size = int(result.get("expected_size", 0))

    row = connection.execute(
        """
        SELECT
            id,
            path,
            size_bytes,
            modified_at,
            sha256,
            hash_status,
            hash_updated_at,
            is_missing
        FROM files
        WHERE id = ?
        """,
        (file_id,),
    ).fetchone()

    reasons = []

    if not dry_run_success:
        reasons.append("dry_run_failed")

    if not calculated_sha256:
        reasons.append("calculated_sha256_missing")

    if row is None:
        reasons.append("database_record_missing")
    else:
        if row["hash_status"] != "pending":
            reasons.append(
                f"hash_status_is_{row['hash_status']}"
            )

        if row["sha256"] not in (None, ""):
            reasons.append("existing_sha256_present")

        if int(row["size_bytes"]) != expected_size:
            reasons.append("database_size_changed")

        if bytes_read != expected_size:
            reasons.append("bytes_read_mismatch")

        if int(row["is_missing"]) != 0:
            reasons.append("record_marked_missing")

        if row["path"] != result.get("path"):
            reasons.append("database_path_changed")

    ready_for_apply = len(reasons) == 0

    items.append(
        {
            "file_id": file_id,
            "path": result.get("path"),
            "ready_for_apply": ready_for_apply,
            "reasons": reasons,
            "current": (
                {
                    "hash_status": row["hash_status"],
                    "sha256": row["sha256"],
                    "size_bytes": row["size_bytes"],
                    "modified_at": row["modified_at"],
                    "is_missing": row["is_missing"],
                }
                if row is not None
                else None
            ),
            "proposed": (
                {
                    "sha256": calculated_sha256,
                    "hash_status": "done",
                    "hash_updated_at": (
                        datetime.now(timezone.utc).isoformat()
                    ),
                }
                if ready_for_apply
                else None
            ),
        }
    )

connection.close()

ready_items = [
    item for item in items
    if item["ready_for_apply"]
]

blocked_items = [
    item for item in items
    if not item["ready_for_apply"]
]

payload = {
    "mode": "database-apply-preview",
    "source_dry_run": str(dry_run_path),
    "summary": {
        "reviewed_files": len(items),
        "ready_for_apply": len(ready_items),
        "blocked": len(blocked_items),
    },
    "ready_items": ready_items,
    "blocked_items": blocked_items,
    "proposed_update": {
        "sha256": "calculated SHA256",
        "hash_status": "done",
        "hash_updated_at": "current UTC timestamp",
    },
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "transaction_executed": False,
        "existing_sha256_overwritten": False,
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
            "mode": payload["mode"],
            "summary": payload["summary"],
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"

echo "Hash DB apply preview: ${REPORT_FILE}" >&2
