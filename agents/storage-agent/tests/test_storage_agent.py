from __future__ import annotations

import importlib.util
import sqlite3
import tempfile
from pathlib import Path


AGENT_ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)

    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module: {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    return module


db = load_module(
    "storage_agent_db",
    AGENT_ROOT / "db.py",
)

scanner = load_module(
    "storage_agent_scanner",
    AGENT_ROOT / "scanner.py",
)


def test_database_initialization() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        database_path = Path(temp_dir) / "storage.db"

        db.init_db(database_path)

        assert database_path.exists()

        with db.get_connection(database_path) as connection:
            tables = {
                row["name"]
                for row in connection.execute(
                    """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'table'
                    """
                )
            }

        assert "files" in tables
        assert "scan_runs" in tables
        assert "scan_errors" in tables
        assert "schema_metadata" in tables


def test_scan_and_missing_detection() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir) / "scan-root"
        root.mkdir()

        first_file = root / "first.txt"
        second_file = root / "second.json"

        first_file.write_text(
            "first\n",
            encoding="utf-8",
        )

        second_file.write_text(
            '{"status":"test"}\n',
            encoding="utf-8",
        )

        database_path = Path(temp_dir) / "storage.db"

        original_db_path = scanner.DB_PATH

        try:
            scanner.DB_PATH = database_path

            db.init_db(database_path)

            first_result = scanner.scan_directory(root)

            assert first_result["files_found"] == 2
            assert first_result["files_missing"] == 0

            second_file.unlink()

            first_file.write_text(
                "first changed\n",
                encoding="utf-8",
            )

            second_result = scanner.scan_directory(root)

            assert second_result["files_found"] == 1
            assert second_result["files_missing"] == 1

            with db.get_connection(database_path) as connection:
                missing = connection.execute(
                    """
                    SELECT is_missing
                    FROM files
                    WHERE filename = 'second.json'
                    """
                ).fetchone()

                changed = connection.execute(
                    """
                    SELECT hash_status
                    FROM files
                    WHERE filename = 'first.txt'
                    """
                ).fetchone()

            assert missing is not None
            assert missing["is_missing"] == 1

            assert changed is not None
            assert changed["hash_status"] == "pending"

        finally:
            scanner.DB_PATH = original_db_path


def main() -> int:
    tests = [
        test_database_initialization,
        test_scan_and_missing_detection,
    ]

    failures = 0

    for test in tests:
        try:
            test()
            print(f"PASS: {test.__name__}")
        except Exception as error:
            failures += 1
            print(
                f"FAIL: {test.__name__}: "
                f"{type(error).__name__}: {error}"
            )

    print(f"Total: {len(tests)}")
    print(f"Failed: {failures}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
