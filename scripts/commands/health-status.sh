#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"
JSON_REPORT="${PROJECT_ROOT}/reports/summary/latest.json"

if [[ ! -f "${JSON_REPORT}" ]]; then
    "${COMMAND_DIR}/json-summary.sh" >/dev/null
fi

python3 - "${JSON_REPORT}" <<'PYTHON'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

if not path.exists():
    print("Status: UNKNOWN")
    print("Reason: JSON report not found")
    raise SystemExit(1)

data = json.loads(path.read_text(encoding="utf-8"))
summary = data.get("summary", {})

print("AI Home Datacenter Runtime Health")
print("---------------------------------")
print(f"Status: {data.get('overall_status', 'UNKNOWN')}")
print(f"Score: {data.get('health_score', 0)}")
print(f"Success: {summary.get('success', 0)}")
print(f"Failed: {summary.get('failed', 0)}")
print(f"Total: {summary.get('total', 0)}")
PYTHON
