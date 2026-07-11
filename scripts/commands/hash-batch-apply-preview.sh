#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"

DB="${PROJECT_ROOT}/agents/storage-agent/data/storage.db"
DRY_RUN="${PROJECT_ROOT}/reports/storage-agent/latest-hash-batch-dry-run.json"
REPORT_DIR="${PROJECT_ROOT}/reports/storage-agent"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_FILE="${REPORT_DIR}/hash-batch-apply-preview-${STAMP}.json"
LATEST_LINK="${REPORT_DIR}/latest-hash-batch-apply-preview.json"

mkdir -p "${REPORT_DIR}"

python3 - "$DB" "$DRY_RUN" "$REPORT_FILE" <<'PYTHON'
import json
import sqlite3
import sys
from pathlib import Path

db=Path(sys.argv[1])
dry=Path(sys.argv[2])
out=Path(sys.argv[3])

data=json.loads(dry.read_text())

con=sqlite3.connect(f"file:{db}?mode=ro",uri=True)
con.row_factory=sqlite3.Row

integrity=con.execute("PRAGMA integrity_check").fetchone()[0]

ready=[]
blocked=[]

for r in data.get("results",[]):

    row=con.execute("""
    SELECT id,path,size_bytes,sha256,hash_status,is_missing
    FROM files
    WHERE id=?
    """,(r["file_id"],)).fetchone()

    reasons=[]

    if row is None:
        reasons.append("missing_record")
    else:

        if row["hash_status"]!="pending":
            reasons.append("status_changed")

        if row["sha256"] not in (None,""):
            reasons.append("already_hashed")

        if row["is_missing"]!=0:
            reasons.append("missing")

        if row["path"]!=r["path"]:
            reasons.append("path_changed")

        if int(row["size_bytes"])!=int(r["expected_size"]):
            reasons.append("size_changed")

    item={
        "file_id":r["file_id"],
        "path":r["path"],
        "ready":len(reasons)==0,
        "reasons":reasons,
        "sha256":r.get("calculated_sha256")
    }

    if item["ready"]:
        ready.append(item)
    else:
        blocked.append(item)

con.close()

payload={
    "mode":"batch-apply-preview",
    "database_integrity":integrity,
    "summary":{
        "reviewed_files":len(data.get("results",[])),
        "ready_for_apply":len(ready),
        "blocked":len(blocked)
    },
    "ready_items":ready,
    "blocked_items":blocked,
    "database_modified":False
}

out.write_text(json.dumps(payload,indent=2))
print(json.dumps(payload["summary"],indent=2))
PYTHON

ln -sfn "$REPORT_FILE" "$LATEST_LINK"

echo "Batch Apply Preview Ready"
