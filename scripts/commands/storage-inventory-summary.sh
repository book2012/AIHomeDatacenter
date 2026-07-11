#!/usr/bin/env bash

set -Eeuo pipefail

DB="agents/storage-agent/data/storage.db"

if [[ ! -f "$DB" ]]; then
    echo "Inventory DB not found."
    exit 1
fi

echo "========== Inventory Summary =========="

sqlite3 "$DB" <<SQL
.headers on
.mode column

SELECT COUNT(*) AS total_files
FROM files;

SELECT
    hash_status,
    COUNT(*) AS files
FROM files
GROUP BY hash_status
ORDER BY files DESC;

SELECT
    root_path,
    COUNT(*) AS files,
    ROUND(SUM(size_bytes)/1073741824.0,2) AS size_gb
FROM files
GROUP BY root_path
ORDER BY files DESC;
SQL

echo
echo "Database Size"
du -sh "$DB"
