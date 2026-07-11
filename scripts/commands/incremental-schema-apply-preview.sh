#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
MIGRATION="${PROJECT_ROOT}/agents/storage-agent/migrations/003_incremental_duplicate.sql"
BACKUP_DIR="${PROJECT_ROOT}/agents/storage-agent/data/backups"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/storage-before-schema-v3-${STAMP}.db"
REPORT_FILE="${REPORT_DIR}/incremental-schema-apply-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-incremental-schema-apply-preview.json"

mkdir -p "${BACKUP_DIR}" "${REPORT_DIR}"

if [[ ! -f "${DB}" ]]; then
    echo "Database not found: ${DB}" >&2
    exit 1
fi

if [[ ! -f "${MIGRATION}" ]]; then
    echo "Migration not found: ${MIGRATION}" >&2
    exit 1
fi

python3 - \
  "${DB}" \
  "${MIGRATION}" \
  "${BACKUP_FILE}" \
  "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

database_path = Path(sys.argv[1]).resolve()
migration_path = Path(sys.argv[2]).resolve()
backup_path = Path(sys.argv[3]).resolve()
report_path = Path(sys.argv[4]).resolve()

connection = sqlite3.connect(
    f"file:{database_path}?mode=ro",
    uri=True,
)

connection.row_factory = sqlite3.Row

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

current_version = (
    schema_row["value"]
    if schema_row
    else "unknown"
)

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

eligible_hashes = connection.execute(
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

expected_tables = {
    "hash_batches",
    "duplicate_processing",
}

expected_indexes = {
    "idx_duplicate_processing_status",
    "idx_duplicate_processing_group",
    "idx_duplicate_processing_batch",
    "idx_hash_batches_status",
}

existing_expected_tables = sorted(
    expected_tables.intersection(tables)
)

existing_expected_indexes = sorted(
    expected_indexes.intersection(indexes)
)

migration_sql = migration_path.read_text(
    encoding="utf-8"
)

required_statements_present = all(
    token in migration_sql
    for token in (
        "CREATE TABLE IF NOT EXISTS hash_batches",
        "CREATE TABLE IF NOT EXISTS duplicate_processing",
        "CREATE INDEX IF NOT EXISTS idx_duplicate_processing_status",
        "CREATE INDEX IF NOT EXISTS idx_hash_batches_status",
    )
)

ready_for_apply = (
    integrity == "ok"
    and current_version in {"1", "2"}
    and required_statements_present
)

payload = {
    "mode": "operational-schema-apply-preview",
    "database": {
        "path": str(database_path),
        "integrity": integrity,
        "current_schema_version": current_version,
        "total_files": total_files,
    },
    "migration": {
        "path": str(migration_path),
        "exists": migration_path.exists(),
        "required_statements_present": required_statements_present,
        "target_schema_version": "3",
    },
    "backup": {
        "planned_path": str(backup_path),
        "will_be_created_during_apply": True,
    },
    "objects": {
        "expected_tables": sorted(expected_tables),
        "expected_indexes": sorted(expected_indexes),
        "already_existing_tables": existing_expected_tables,
        "already_existing_indexes": existing_expected_indexes,
    },
    "inventory": {
        "eligible_existing_hashes": eligible_hashes,
    },
    "ready_for_apply": ready_for_apply,
    "blocking_reasons": [
        reason
        for reason, blocked in (
            (
                "database_integrity_not_ok",
                integrity != "ok",
            ),
            (
                "unsupported_current_schema_version",
                current_version not in {"1", "2"},
            ),
            (
                "migration_sql_incomplete",
                not required_statements_present,
            ),
        )
        if blocked
    ],
    "safety": {
        "database_modified": False,
        "migration_executed": False,
        "backup_created": False,
        "files_modified": False,
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
            "current_schema_version": current_version,
            "target_schema_version": "3",
            "integrity": integrity,
            "ready_for_apply": ready_for_apply,
            "blocking_reasons": payload["blocking_reasons"],
            "planned_backup": str(backup_path),
            "database_modified": False,
        },
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
