#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

PREVIEW="${PROJECT_ROOT}/reports/storage-agent/latest-hash-db-apply-preview.json"
APPLY_COMMAND="${COMMAND_DIR}/hash-db-apply-pilot.sh"
DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"

if [[ ! -f "${PREVIEW}" ]]; then
    echo "Apply preview not found: ${PREVIEW}" >&2
    exit 1
fi

if [[ ! -x "${APPLY_COMMAND}" ]]; then
    echo "Apply command not found: ${APPLY_COMMAND}" >&2
    exit 1
fi

READY="$(
    python3 - "${PREVIEW}" <<'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)

print(data["summary"]["ready_for_apply"])
PYTHON
)"

REVIEWED="$(
    python3 - "${PREVIEW}" <<'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)

print(data["summary"]["reviewed_files"])
PYTHON
)"

BLOCKED="$(
    python3 - "${PREVIEW}" <<'PYTHON'
import json
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)

print(data["summary"]["blocked"])
PYTHON
)"

INTEGRITY="$(
    sqlite3 "${DB}" "PRAGMA integrity_check;"
)"

echo "Reviewed: ${REVIEWED}"
echo "Ready: ${READY}"
echo "Blocked: ${BLOCKED}"
echo "Integrity: ${INTEGRITY}"

if [[ "${INTEGRITY}" != "ok" ]]; then
    echo "Pilot blocked: database integrity check failed." >&2
    exit 3
fi

if (( REVIEWED < 1 )); then
    echo "Pilot blocked: no reviewed files." >&2
    exit 4
fi

if (( READY < 1 )); then
    echo "Pilot blocked: no files are ready." >&2
    exit 4
fi

if (( BLOCKED > 0 )); then
    echo "Pilot blocked: preview contains blocked items." >&2
    exit 5
fi

APPLY_COUNT="${READY}"

if (( APPLY_COUNT > 10 )); then
    APPLY_COUNT=10
fi

echo "Applying ${APPLY_COUNT} verified hashes."

exec "${APPLY_COMMAND}" "${APPLY_COUNT}"
