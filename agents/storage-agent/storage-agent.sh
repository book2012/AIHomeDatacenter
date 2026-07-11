#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_MODULE="${AGENT_ROOT}/db.py"

usage() {
    echo "Usage:"
    echo "  storage-agent.sh init-db"
    echo "  storage-agent.sh db-status"
    echo "  storage-agent.sh integrity-check"
    echo "  storage-agent.sh migrate-db"
    echo "  storage-agent.sh scan <path>"
}

case "${1:-help}" in
    init-db)
        python3 "${DB_MODULE}"
        ;;

    db-status)
        python3 - "${DB_MODULE}" <<'PYTHON'
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "storage_agent_db",
    module_path,
)

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(
    json.dumps(
        module.get_status(),
        indent=2,
        ensure_ascii=False,
    )
)
PYTHON
        ;;

    scan)
        if [[ -z "${2:-}" ]]; then
            echo "Scan path is required." >&2
            exit 2
        fi

        python3 "${AGENT_ROOT}/scanner.py" "$2"
        ;;

    migrate-db)
        python3 - "${DB_MODULE}" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "storage_agent_db",
    module_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

version = module.migrate_db()
print(f"Schema version: {version}")
PY
        ;;

    integrity-check)
        python3 - "${DB_MODULE}" <<'PYTHON'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "storage_agent_db",
    module_path,
)

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.init_db()

with module.get_connection() as connection:
    result = connection.execute(
        "PRAGMA integrity_check"
    ).fetchone()[0]

print(result)

if result != "ok":
    raise SystemExit(1)
PYTHON
        ;;

    help|-h|--help)
        usage
        ;;

    *)
        echo "Unknown command: $1" >&2
        usage >&2
        exit 2
        ;;
esac
