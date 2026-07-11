#!/usr/bin/env bash

set -Eeuo pipefail

DB="agents/storage-agent/data/storage.db"

if [[ ! -f "$DB" ]]; then
    echo "Inventory database not found."
    exit 1
fi

echo
echo "========== Duplicate Summary =========="
echo

sqlite3 "$DB" <<SQL
.headers on
.mode column

SELECT
COUNT(*) AS duplicate_groups
FROM duplicate_groups;

SELECT
COUNT(*) AS duplicate_files
FROM duplicate_files;

SELECT
ROUND(SUM(size_bytes)/1073741824.0,2)
AS duplicate_gb
FROM duplicate_files;

SELECT
id,
file_count,
ROUND(total_size_bytes/1073741824.0,2)
AS total_gb
FROM duplicate_groups
ORDER BY total_size_bytes DESC
LIMIT 20;
SQL

echo
echo "Database"

du -sh "$DB"
