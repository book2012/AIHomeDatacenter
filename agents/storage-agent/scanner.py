from __future__ import annotations

import argparse
import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from db import get_connection, init_db


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def create_scan_run(
    connection: sqlite3.Connection,
    root_path: Path,
) -> int:
    cursor = connection.execute(
        """
        INSERT INTO scan_runs (
            root_path,
            started_at,
            status
        )
        VALUES (?, ?, 'running')
        """,
        (
            str(root_path),
            utc_now(),
        ),
    )

    return int(cursor.lastrowid)


def update_scan_run(
    connection: sqlite3.Connection,
    scan_run_id: int,
    *,
    status: str,
    files_found: int,
    error_message: str | None = None,
) -> None:
    connection.execute(
        """
        UPDATE scan_runs
        SET finished_at = ?,
            status = ?,
            files_found = ?,
            error_message = ?
        WHERE id = ?
        """,
        (
            utc_now(),
            status,
            files_found,
            error_message,
            scan_run_id,
        ),
    )


def save_scan_error(
    connection: sqlite3.Connection,
    *,
    scan_run_id: int,
    file_path: Path,
    error: Exception,
) -> None:
    connection.execute(
        """
        INSERT INTO scan_errors (
            scan_run_id,
            path,
            error_type,
            message,
            created_at
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            scan_run_id,
            str(file_path),
            type(error).__name__,
            str(error),
            utc_now(),
        ),
    )



def save_file(
    connection: sqlite3.Connection,
    *,
    root_path: Path,
    file_path: Path,
    scan_run_id: int,
    scanned_at: str,
) -> None:
    stat_result = file_path.stat()

    connection.execute(
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
        ON CONFLICT(path)
        DO UPDATE SET
            root_path = excluded.root_path,
            filename = excluded.filename,
            extension = excluded.extension,
            size_bytes = excluded.size_bytes,
            modified_at = excluded.modified_at,
            scanned_at = excluded.scanned_at,
            scan_run_id = excluded.scan_run_id,
            is_missing = 0,
            sha256 = CASE
                WHEN files.size_bytes != excluded.size_bytes
                  OR files.modified_at != excluded.modified_at
                THEN NULL
                ELSE files.sha256
            END,
            hash_status = CASE
                WHEN files.size_bytes != excluded.size_bytes
                  OR files.modified_at != excluded.modified_at
                THEN 'pending'
                ELSE files.hash_status
            END
        """,
        (
            str(file_path),
            str(root_path),
            file_path.name,
            file_path.suffix.lower() or None,
            stat_result.st_size,
            datetime.fromtimestamp(
                stat_result.st_mtime,
                tz=timezone.utc,
            ).isoformat(),
            scanned_at,
            scan_run_id,
        ),
    )


def mark_missing_files(
    connection: sqlite3.Connection,
    *,
    root_path: Path,
    scan_run_id: int,
) -> int:
    cursor = connection.execute(
        """
        UPDATE files
        SET is_missing = 1
        WHERE root_path = ?
          AND scan_run_id != ?
          AND is_missing = 0
        """,
        (
            str(root_path),
            scan_run_id,
        ),
    )

    return cursor.rowcount


def scan_directory(root_path: Path) -> dict[str, int | str]:
    root_path = root_path.resolve()

    if not root_path.exists():
        raise FileNotFoundError(
            f"Scan root does not exist: {root_path}"
        )

    if not root_path.is_dir():
        raise NotADirectoryError(
            f"Scan root is not a directory: {root_path}"
        )

    init_db()

    files_found = 0
    errors_found = 0
    scanned_at = utc_now()

    with get_connection() as connection:
        scan_run_id = create_scan_run(
            connection,
            root_path,
        )

        connection.commit()

        try:
            for directory, subdirectories, filenames in os.walk(
                root_path,
                followlinks=False,
            ):
                subdirectories[:] = [
                    name
                    for name in subdirectories
                    if name not in {
                        ".git",
                        ".venv",
                        "__pycache__",
                    }
                ]

                for filename in filenames:
                    file_path = Path(directory) / filename

                    try:
                        save_file(
                            connection,
                            root_path=root_path,
                            file_path=file_path,
                            scan_run_id=scan_run_id,
                            scanned_at=scanned_at,
                        )
                        files_found += 1
                    except (
                        FileNotFoundError,
                        PermissionError,
                        OSError,
                    ) as error:
                        errors_found += 1

                        save_scan_error(
                            connection,
                            scan_run_id=scan_run_id,
                            file_path=file_path,
                            error=error,
                        )

            missing_files = mark_missing_files(
                connection,
                root_path=root_path,
                scan_run_id=scan_run_id,
            )

            update_scan_run(
                connection,
                scan_run_id,
                status="completed",
                files_found=files_found,
            )

            connection.commit()

        except Exception as exc:
            connection.rollback()

            update_scan_run(
                connection,
                scan_run_id,
                status="failed",
                files_found=files_found,
                error_message=str(exc),
            )

            connection.commit()
            raise

    return {
        "root_path": str(root_path),
        "scan_run_id": scan_run_id,
        "files_found": files_found,
        "files_missing": missing_files,
        "errors_found": errors_found,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Storage Agent metadata scanner",
    )

    parser.add_argument(
        "root",
        type=Path,
        help="Directory to scan",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    result = scan_directory(args.root)

    print(
        json.dumps(
            result,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
