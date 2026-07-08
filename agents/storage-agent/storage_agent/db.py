from pathlib import Path
import sqlite3

DB_PATH = Path("data/storage.db")


def get_connection():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")

    return conn


def init_db():
    conn = get_connection()

    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS scan_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_path TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            status TEXT NOT NULL DEFAULT 'running',
            files_found INTEGER NOT NULL DEFAULT 0,
            error_message TEXT
        );

        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            root_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            extension TEXT,
            size_bytes INTEGER NOT NULL,
            modified_at TEXT,
            scanned_at TEXT NOT NULL,
            scan_run_id INTEGER,
            sha256 TEXT,
            hash_status TEXT NOT NULL DEFAULT 'pending',
            hash_updated_at TEXT,
            is_missing INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (scan_run_id) REFERENCES scan_runs(id)
        );

        CREATE INDEX IF NOT EXISTS idx_files_root_path
        ON files(root_path);

        CREATE INDEX IF NOT EXISTS idx_files_sha256
        ON files(sha256);

        CREATE INDEX IF NOT EXISTS idx_files_hash_status
        ON files(hash_status);

        CREATE TABLE IF NOT EXISTS hash_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            status TEXT NOT NULL DEFAULT 'running',
            files_hashed INTEGER NOT NULL DEFAULT 0,
            error_message TEXT
        );

        CREATE TABLE IF NOT EXISTS duplicate_groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sha256 TEXT NOT NULL UNIQUE,
            file_count INTEGER NOT NULL,
            total_size_bytes INTEGER NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS duplicate_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            duplicate_group_id INTEGER NOT NULL,
            file_id INTEGER NOT NULL,
            path TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            FOREIGN KEY (duplicate_group_id) REFERENCES duplicate_groups(id),
            FOREIGN KEY (file_id) REFERENCES files(id)
        );

        CREATE TABLE IF NOT EXISTS agent_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """
    )

    conn.commit()
    conn.close()


if __name__ == "__main__":
    init_db()
    print(f"Initialized database: {DB_PATH}")
