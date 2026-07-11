#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
MIGRATION="${PROJECT_ROOT}/agents/storage-agent/migrations/003_incremental_duplicate.sql"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/incremental-schema-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-incremental-schema-preview.json"

mkdir -p "${REPORT_DIR}"

python3 - "${DB}" "${MIGRATION}" "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1]).resolve()
migration_path = Path(sys.argv[2]).resolve()
report_path = Path(sys.argv[3]).resolve()

connection = sqlite3.connect(
    f"file:{db_path}?mode=ro",
    uri=True,
)
connection.row_factory = sqlite3.Row

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

tables = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        """
    )
}

indexes = {
    row["name"]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND name IS NOT NULL
        """
    )
}

total_files = connection.execute(
    "SELECT COUNT(*) FROM files"
).fetchone()[0]

new_hash_candidates = connection.execute(
    """
    SELECT COUNT(*)
    FROM files
    WHERE hash_status IN ('done', 'completed')
      AND sha256 IS NOT NULL
      AND length(trim(sha256)) = 64
      AND is_missing = 0
      AND path NOT LIKE '/mnt/storage/Archive/Immich/%'
      AND path NOT LIKE '/mnt/storage/Archive/Nextcloud/%'
    """
).fetchone()[0]

connection.close()

expected_tables = [
    "hash_batches",
    "duplicate_processing",
]

expected_indexes = [
    "idx_duplicate_processing_status",
    "idx_duplicate_processing_group",
    "idx_duplicate_processing_batch",
    "idx_hash_batches_status",
]

payload = {
    "mode": "read-only-schema-preview",
    "database_integrity": integrity,
    "total_files": total_files,
    "eligible_existing_hashes": new_hash_candidates,
    "migration_file": str(migration_path),
    "migration_exists": migration_path.exists(),
    "expected_tables": expected_tables,
    "expected_indexes": expected_indexes,
    "already_existing_tables": [
        name for name in expected_tables
        if name in tables
    ],
    "already_existing_indexes": [
        name for name in expected_indexes
        if name in indexes
    ],
    "proposed_architecture": {
        "files_table_rebuild_required": False,
        "existing_sha256_modified": False,
        "incremental_state_stored_separately": True,
        "automatic_deletion": False,
    },
    "safety": {
        "database_modified": False,
        "migration_executed": False,
        "files_modified": False,
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

print(json.dumps(payload, ensure_ascii=False, indent=2))
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
