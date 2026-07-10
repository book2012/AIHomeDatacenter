#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="/opt/aihomedatacenter/reports/summary"

mkdir -p "$REPORT_DIR"

INPUT="$REPORT_DIR/latest.txt"
OUTPUT="$REPORT_DIR/latest.json"

python3 - <<PYTHON
import json
from pathlib import Path

report = Path("$INPUT")

result = {
    "overall_status": "UNKNOWN",
    "health_score": 0,
    "summary": {
        "success": 0,
        "failed": 0,
        "total": 0
    }
}

if report.exists():
    success = failed = total = 0

    for line in report.read_text().splitlines():
        if " OK " in line:
            success += 1
            total += 1
        elif "FAILED" in line:
            failed += 1
            total += 1

    score = max(0, 100 - failed * 15)

    if score >= 90:
        status = "HEALTHY"
    elif score >= 70:
        status = "WARNING"
    else:
        status = "CRITICAL"

    result = {
        "overall_status": status,
        "health_score": score,
        "summary": {
            "success": success,
            "failed": failed,
            "total": total
        }
    }

Path("$OUTPUT").write_text(
    json.dumps(result, indent=2),
    encoding="utf-8"
)

print(Path("$OUTPUT").read_text())
PYTHON
