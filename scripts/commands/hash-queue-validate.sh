#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

QUEUE_REPORT="${PROJECT_ROOT}/reports/storage-agent/latest-hash-queue-preview.json"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-queue-validation-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-queue-validation.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${QUEUE_REPORT}" ]]; then
    echo "Hash queue preview not found." >&2
    echo "Run: scripts/runtime.sh hash-queue-preview 1000" >&2
    exit 1
fi

python3 - "${QUEUE_REPORT}" "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
from pathlib import Path


queue_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])

queue_data = json.loads(
    queue_path.read_text(encoding="utf-8")
)

items = queue_data.get("queue", [])

validated = []
root_summary: dict[str, dict[str, int]] = defaultdict(
    lambda: {
        "checked": 0,
        "exists": 0,
        "size_match": 0,
        "valid": 0,
        "missing": 0,
        "size_mismatch": 0,
    }
)

excluded_detected = 0

for item in items:
    path = item["path"]
    root = item["root_path"]
    db_size = int(item["size_bytes"])

    excluded = (
        path.startswith("/mnt/storage/Archive/Immich/")
        or path.startswith("/mnt/storage/Archive/Nextcloud/")
    )

    exists = os.path.isfile(path)
    actual_size = os.path.getsize(path) if exists else None
    size_match = exists and actual_size == db_size
    valid = exists and size_match and not excluded

    root_summary[root]["checked"] += 1
    root_summary[root]["exists"] += int(exists)
    root_summary[root]["size_match"] += int(size_match)
    root_summary[root]["valid"] += int(valid)
    root_summary[root]["missing"] += int(not exists)
    root_summary[root]["size_mismatch"] += int(
        exists and not size_match
    )

    excluded_detected += int(excluded)

    validated.append(
        {
            "file_id": item["file_id"],
            "root_path": root,
            "path": path,
            "db_size": db_size,
            "actual_size": actual_size,
            "exists": exists,
            "size_match": size_match,
            "excluded": excluded,
            "valid_for_hash": valid,
        }
    )

valid_items = [
    item for item in validated
    if item["valid_for_hash"]
]

payload = {
    "mode": "read-only-validation",
    "source_queue": str(queue_path),
    "summary": {
        "checked": len(validated),
        "exists": sum(item["exists"] for item in validated),
        "size_match": sum(
            item["size_match"] for item in validated
        ),
        "valid_for_hash": len(valid_items),
        "missing": sum(
            not item["exists"] for item in validated
        ),
        "size_mismatch": sum(
            item["exists"] and not item["size_match"]
            for item in validated
        ),
        "excluded_detected": excluded_detected,
        "valid_bytes": sum(
            item["db_size"] for item in valid_items
        ),
    },
    "by_root": dict(root_summary),
    "invalid_items": [
        item for item in validated
        if not item["valid_for_hash"]
    ][:200],
    "valid_queue": valid_items,
    "safety": {
        "sha256_calculated": False,
        "database_modified": False,
        "files_modified": False,
    },
}

payload["summary"]["valid_gb"] = round(
    payload["summary"]["valid_bytes"] / 1073741824,
    4,
)

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
            "summary": payload["summary"],
            "by_root": payload["by_root"],
            "safety": payload["safety"],
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
