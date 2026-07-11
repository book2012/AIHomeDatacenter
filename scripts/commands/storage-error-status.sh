#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB_FILE="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
REPORT_FILE="${REPORT_DIR}/storage-errors-$(date '+%Y%m%d-%H%M%S').json"
LATEST_LINK="${REPORT_DIR}/latest-errors.json"

mkdir -p "${REPORT_DIR}"

if [[ ! -f "${DB_FILE}" ]]; then
    echo "Storage Agent database not found: ${DB_FILE}" >&2
    exit 1
fi

python3 - "${DB_FILE}" "${REPORT_FILE}" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

database_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])

connection = sqlite3.connect(database_path)
connection.row_factory = sqlite3.Row

table_exists = connection.execute(
    """
    SELECT COUNT(*)
    FROM sqlite_master
    WHERE type = 'table'
      AND name = 'scan_errors'
    """
).fetchone()[0]

if not table_exists:
    raise SystemExit(
        "scan_errors table not found. Run migrate-db first."
    )

rows = connection.execute(
    """
    SELECT
        scan_errors.id,
        scan_errors.scan_run_id,
        scan_errors.path,
        scan_errors.error_type,
        scan_errors.message,
        scan_errors.created_at,
        scan_runs.root_path
    FROM scan_errors
    LEFT JOIN scan_runs
        ON scan_runs.id = scan_errors.scan_run_id
    ORDER BY scan_errors.id DESC
    LIMIT 100
    """
).fetchall()

total_errors = connection.execute(
    "SELECT COUNT(*) FROM scan_errors"
).fetchone()[0]

connection.close()

payload = {
    "schema_version": 1,
    "total_errors": total_errors,
    "returned_errors": len(rows),
    "errors": [
        dict(row)
        for row in rows
    ],
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
        payload,
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
