from pathlib import Path
from datetime import datetime, timezone
import os
import time

from storage_agent.db import get_connection


BATCH_SIZE = 1000
PROGRESS_INTERVAL = 5000


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def should_exclude(path: Path, exclude_dirs: list[str], exclude_exts: list[str]) -> bool:
    for part in path.parts:
        if part in exclude_dirs:
            return True

    if path.suffix.lower() in exclude_exts:
        return True

    return False


def start_scan_run(root_path: str) -> int:
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO scan_runs (root_path, started_at, status)
        VALUES (?, ?, ?)
        """,
        (root_path, utc_now(), "running"),
    )

    scan_run_id = cur.lastrowid
    conn.commit()
    conn.close()

    return scan_run_id


def finish_scan_run(
    scan_run_id: int,
    files_found: int,
    status: str = "completed",
    error_message: str | None = None,
):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE scan_runs
        SET finished_at = ?, status = ?, files_found = ?, error_message = ?
        WHERE id = ?
        """,
        (utc_now(), status, files_found, error_message, scan_run_id),
    )

    conn.commit()
    conn.close()


def flush_batch(conn, rows: list[tuple]):
    if not rows:
        return

    conn.executemany(
        """
        INSERT INTO files (
            path,
            root_path,
            filename,
            extension,
            size_bytes,
            modified_at,
            scanned_at,
            scan_run_id,
            hash_status,
            is_missing
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0)
        ON CONFLICT(path) DO UPDATE SET
            root_path = excluded.root_path,
            filename = excluded.filename,
            extension = excluded.extension,
            size_bytes = excluded.size_bytes,
            modified_at = excluded.modified_at,
            scanned_at = excluded.scanned_at,
            scan_run_id = excluded.scan_run_id,
            is_missing = 0,
            hash_status = CASE
                WHEN files.size_bytes != excluded.size_bytes
                  OR files.modified_at != excluded.modified_at
                THEN 'pending'
                ELSE files.hash_status
            END,
            sha256 = CASE
                WHEN files.size_bytes != excluded.size_bytes
                  OR files.modified_at != excluded.modified_at
                THEN NULL
                ELSE files.sha256
            END
        """,
        rows,
    )


def scan_root(root: dict, exclude_dirs: list[str], exclude_exts: list[str]) -> int:
    root_path = root["path"]
    root_name = root.get("name", root_path)
    base_path = Path(root_path)

    if not base_path.exists():
        raise FileNotFoundError(f"Scan root not found: {root_name} ({root_path})")

    scan_run_id = start_scan_run(root_path)
    files_found = 0
    batch = []
    started = time.time()

    conn = get_connection()

    try:
        print(f"[SCAN] {root_name}: {root_path}")

        for current_root, dirs, files in os.walk(base_path):
            dirs[:] = [d for d in dirs if d not in exclude_dirs]

            current_path = Path(current_root)

            for file_name in files:
                file_path = current_path / file_name

                if should_exclude(file_path, exclude_dirs, exclude_exts):
                    continue

                if not file_path.is_file():
                    continue

                try:
                    stat = file_path.stat()
                except FileNotFoundError:
                    continue
                except PermissionError:
                    continue

                scanned_at = utc_now()

                batch.append(
                    (
                        str(file_path),
                        root_path,
                        file_path.name,
                        file_path.suffix.lower(),
                        stat.st_size,
                        datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
                        scanned_at,
                        scan_run_id,
                    )
                )

                files_found += 1

                if len(batch) >= BATCH_SIZE:
                    flush_batch(conn, batch)
                    conn.commit()
                    batch.clear()

                if files_found % PROGRESS_INTERVAL == 0:
                    elapsed = max(time.time() - started, 1)
                    rate = files_found / elapsed
                    print(
                        f"[PROGRESS] {root_name}: {files_found:,} files "
                        f"({rate:.1f} files/sec) current={current_path}"
                    )

        flush_batch(conn, batch)
        conn.commit()

        finish_scan_run(scan_run_id, files_found)

        elapsed = max(time.time() - started, 1)
        rate = files_found / elapsed
        print(f"[DONE] {root_name}: {files_found:,} files, {rate:.1f} files/sec")

        return files_found

    except Exception as e:
        conn.rollback()
        finish_scan_run(scan_run_id, files_found, status="failed", error_message=str(e))
        raise

    finally:
        conn.close()
