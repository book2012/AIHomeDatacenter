#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

VALIDATION_REPORT="${PROJECT_ROOT}/reports/storage-agent/latest-hash-queue-validation.json"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-dry-run-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-dry-run.json"

MAX_FILES="${1:-10}"
MAX_BYTES="${2:-104857600}"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${VALIDATION_REPORT}" ]]; then
    echo "Hash queue validation report not found." >&2
    echo "Run: scripts/runtime.sh hash-queue-validate" >&2
    exit 1
fi

if ! [[ "${MAX_FILES}" =~ ^[0-9]+$ ]] ||
   (( MAX_FILES < 1 || MAX_FILES > 100 )); then
    echo "MAX_FILES must be between 1 and 100." >&2
    exit 2
fi

if ! [[ "${MAX_BYTES}" =~ ^[0-9]+$ ]] ||
   (( MAX_BYTES < 1 || MAX_BYTES > 1073741824 )); then
    echo "MAX_BYTES must be between 1 and 1073741824." >&2
    exit 2
fi

python3 - \
    "${VALIDATION_REPORT}" \
    "${REPORT_FILE}" \
    "${MAX_FILES}" \
    "${MAX_BYTES}" <<'PYTHON'
from __future__ import annotations

import hashlib
import json
import sys
import time
from pathlib import Path


validation_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
max_files = int(sys.argv[3])
max_bytes = int(sys.argv[4])

validation = json.loads(
    validation_path.read_text(encoding="utf-8")
)

valid_queue = validation.get("valid_queue", [])

selected = []
selected_bytes = 0

for item in valid_queue:
    size_bytes = int(item["db_size"])

    if len(selected) >= max_files:
        break

    if selected_bytes + size_bytes > max_bytes:
        continue

    selected.append(item)
    selected_bytes += size_bytes

results = []
total_started = time.monotonic()

for item in selected:
    path = Path(item["path"])
    started = time.monotonic()
    digest = hashlib.sha256()

    error = None
    calculated_sha256 = None
    bytes_read = 0

    try:
        with path.open("rb") as handle:
            while True:
                block = handle.read(1024 * 1024)

                if not block:
                    break

                digest.update(block)
                bytes_read += len(block)

        calculated_sha256 = digest.hexdigest()

    except OSError as exc:
        error = f"{type(exc).__name__}: {exc}"

    elapsed = round(time.monotonic() - started, 4)

    results.append(
        {
            "file_id": item["file_id"],
            "root_path": item["root_path"],
            "path": str(path),
            "expected_size": item["db_size"],
            "bytes_read": bytes_read,
            "calculated_sha256": calculated_sha256,
            "elapsed_seconds": elapsed,
            "success": error is None,
            "error": error,
        }
    )

total_elapsed = round(
    time.monotonic() - total_started,
    4,
)

success_count = sum(
    item["success"] for item in results
)

payload = {
    "mode": "dry-run",
    "limits": {
        "max_files": max_files,
        "max_bytes": max_bytes,
    },
    "summary": {
        "selected_files": len(selected),
        "selected_bytes": selected_bytes,
        "processed_files": len(results),
        "successful_files": success_count,
        "failed_files": len(results) - success_count,
        "bytes_read": sum(
            item["bytes_read"] for item in results
        ),
        "elapsed_seconds": total_elapsed,
    },
    "results": results,
    "safety": {
        "database_modified": False,
        "files_modified": False,
        "hashes_persisted": False,
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

echo "Hash dry-run report: ${REPORT_FILE}" >&2
