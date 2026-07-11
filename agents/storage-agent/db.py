from __future__ import annotations

import sqlite3
from pathlib import Path


AGENT_ROOT = Path(__file__).resolve().parent
DB_PATH = AGENT_ROOT / "data" / "storage.db"
SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS scan_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    root_path TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'completed', 'failed')),
    files_found INTEGER NOT NULL DEFAULT 0,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL UNIQUE,
    root_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    extension TEXT,
    size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
    modified_at TEXT,
    scanned_at TEXT NOT NULL,
    scan_run_id INTEGER,
    sha256 TEXT,
    hash_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (
            hash_status IN (
                'pending',
                'processing',
                'completed',
                'failed',
                'skipped'
            )
        ),
    hash_updated_at TEXT,
    is_missing INTEGER NOT NULL DEFAULT 0
        CHECK (is_missing IN (0, 1)),
    FOREIGN KEY (scan_run_id)
        REFERENCES scan_runs(id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_files_root_path
ON files(root_path);

CREATE INDEX IF NOT EXISTS idx_files_sha256
ON files(sha256);

CREATE INDEX IF NOT EXISTS idx_files_hash_status
ON files(hash_status);

CREATE INDEX IF NOT EXISTS idx_files_scan_run_id
ON files(scan_run_id);

CREATE TABLE IF NOT EXISTS hash_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL DEFAULT 'running',
    files_hashed INTEGER NOT NULL DEFAULT 0,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS agent_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
"""


def get_connection(
    database_path: Path = DB_PATH,
) -> sqlite3.Connection:
    database_path.parent.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(
        database_path,
        timeout=5.0,
    )

    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA synchronous = NORMAL")
    connection.execute("PRAGMA busy_timeout = 5000")

    return connection


def init_db(
    database_path: Path = DB_PATH,
) -> Path:
    with get_connection(database_path) as connection:
        connection.executescript(SCHEMA)

        connection.execute(
            """
            INSERT INTO schema_metadata (
                key,
                value,
                updated_at
            )
            VALUES (
                'schema_version',
                ?,
                CURRENT_TIMESTAMP
            )
            ON CONFLICT(key)
            DO UPDATE SET
                value = excluded.value,
                updated_at = CURRENT_TIMESTAMP
            """,
            (str(SCHEMA_VERSION),),
        )

        connection.commit()

    return database_path.resolve()


def get_status(
    database_path: Path = DB_PATH,
) -> dict[str, object]:
    if not database_path.exists():
        return {
            "exists": False,
            "path": str(database_path.resolve()),
            "schema_version": None,
            "files": 0,
            "scan_runs": 0,
        }

    with get_connection(database_path) as connection:
        schema_row = connection.execute(
            """
            SELECT value
            FROM schema_metadata
            WHERE key = 'schema_version'
            """
        ).fetchone()

        files_count = connection.execute(
            "SELECT COUNT(*) FROM files"
        ).fetchone()[0]

        scan_count = connection.execute(
            "SELECT COUNT(*) FROM scan_runs"
        ).fetchone()[0]

    return {
        "exists": True,
        "path": str(database_path.resolve()),
        "schema_version": (
            schema_row["value"]
            if schema_row
            else None
        ),
        "files": files_count,
        "scan_runs": scan_count,
    }


if __name__ == "__main__":
    initialized_path = init_db()
    print(f"Initialized database: {initialized_path}")


def migrate_db(
    database_path: Path = DB_PATH,
) -> int:
    migration_dir = AGENT_ROOT / "migrations"

    init_db(database_path)

    with get_connection(database_path) as connection:
        current_row = connection.execute(
            """
            SELECT value
            FROM schema_metadata
            WHERE key = 'schema_version'
            """
        ).fetchone()

        current_version = (
            int(current_row["value"])
            if current_row
            else 1
        )

        migration_file = migration_dir / "002_scan_errors.sql"

        if current_version < 2:
            connection.executescript(
                migration_file.read_text(encoding="utf-8")
            )

            connection.execute(
                """
                UPDATE schema_metadata
                SET value = '2',
                    updated_at = CURRENT_TIMESTAMP
                WHERE key = 'schema_version'
                """
            )

            connection.commit()
            current_version = 2

    return current_version
