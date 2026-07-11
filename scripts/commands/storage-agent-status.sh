#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB_FILE="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
CONFIG_FILE="${PROJECT_ROOT}/config/storage-agent.env"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"
REPORT_FILE="${REPORT_DIR}/status-$(date '+%Y%m%d-%H%M%S').json"
LATEST_LINK="${REPORT_DIR}/latest-status.json"

mkdir -p "${REPORT_DIR}"

python3 - \
    "${DB_FILE}" \
    "${CONFIG_FILE}" \
    "${REPORT_FILE}" <<'PYTHON'
from __future__ import annotations

import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


database_path = Path(sys.argv[1])
config_path = Path(sys.argv[2])
report_path = Path(sys.argv[3])

payload = {
    "schema_version": 1,
    "generated_at": datetime.now(
        timezone.utc
    ).astimezone().isoformat(),
    "database": {
        "path": str(database_path),
        "exists": database_path.exists(),
        "integrity": "unknown",
        "schema_version": None,
    },
    "inventory": {
        "files": 0,
        "missing_files": 0,
        "scan_runs": 0,
        "scan_errors": 0,
    },
    "latest_scan": None,
    "config": {
        "path": str(config_path),
        "exists": config_path.exists(),
    },
}

if database_path.exists():
    connection = sqlite3.connect(database_path)
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

    payload["database"]["integrity"] = integrity
    payload["database"]["schema_version"] = (
        schema_row["value"]
        if schema_row
        else None
    )

    payload["inventory"]["files"] = connection.execute(
        "SELECT COUNT(*) FROM files"
    ).fetchone()[0]

    payload["inventory"]["missing_files"] = connection.execute(
        """
        SELECT COUNT(*)
        FROM files
        WHERE is_missing = 1
        """
    ).fetchone()[0]

    payload["inventory"]["scan_runs"] = connection.execute(
        "SELECT COUNT(*) FROM scan_runs"
    ).fetchone()[0]

    error_table = connection.execute(
        """
        SELECT COUNT(*)
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'scan_errors'
        """
    ).fetchone()[0]

    if error_table:
        payload["inventory"]["scan_errors"] = connection.execute(
            "SELECT COUNT(*) FROM scan_errors"
        ).fetchone()[0]

    latest_scan = connection.execute(
        """
        SELECT
            id,
            root_path,
            status,
            files_found,
            started_at,
            finished_at,
            error_message
        FROM scan_runs
        ORDER BY id DESC
        LIMIT 1
        """
    ).fetchone()

    if latest_scan:
        payload["latest_scan"] = dict(latest_scan)

    connection.close()

payload["overall_status"] = (
    "HEALTHY"
    if (
        payload["database"]["exists"]
        and payload["database"]["integrity"] == "ok"
    )
    else "ATTENTION"
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
        payload,
        ensure_ascii=False,
        indent=2,
    )
)
PYTHON

ln -sfn "${REPORT_FILE}" "${LATEST_LINK}"
