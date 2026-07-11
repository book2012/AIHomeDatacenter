#!/usr/bin/env bash

set -Eeuo pipefail

DB="agents/storage-agent/data/storage.db"
REPORT_DIR="reports/storage-agent"
REPORT="${REPORT_DIR}/latest-migration-preview.json"

python3 <<PYTHON
import json
import sqlite3

conn=sqlite3.connect("${DB}")
conn.row_factory=sqlite3.Row

current={}

for r in conn.execute("""
SELECT
COALESCE(hash_status,'NULL') status,
COUNT(*) cnt
FROM files
GROUP BY hash_status
"""):
    current[r["status"]]=r["cnt"]

current_missing=conn.execute("""
SELECT COUNT(*)
FROM files
WHERE is_missing=1
""").fetchone()[0]

overlap=conn.execute("""
SELECT COUNT(*)
FROM files
WHERE hash_status='missing'
AND is_missing=1
""").fetchone()[0]

total=conn.execute("""
SELECT COUNT(*)
FROM files
""").fetchone()[0]

result={
    "mode":"preview-only",
    "total_files":total,
    "current_status":current,
    "normalized_preview":{
        "completed":current.get("done",0),
        "pending":current.get("pending",0),
        "missing_legacy":current.get("missing",0),
        "failed":current.get("failed",0),
        "skipped":current.get("skipped",0)
    },
    "current_missing":current_missing,
    "overlap":overlap
}

with open("${REPORT}","w") as f:
    json.dump(result,f,indent=2)

print(json.dumps(result,indent=2))
PYTHON
