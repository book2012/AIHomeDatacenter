import hashlib
import time
from pathlib import Path
from datetime import datetime, timezone

from storage_agent.db import get_connection

CHUNK_SIZE = 1024 * 1024


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256sum(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(CHUNK_SIZE), b""):
            h.update(chunk)
    return h.hexdigest()


def count_pending() -> int:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM files WHERE hash_status='pending'")
    count = cur.fetchone()[0]
    conn.close()
    return count


def hash_pending(limit: int = 100, loop: bool = False, sleep_seconds: float = 0.0):
    total_hashed = 0
    total_errors = 0

    while True:
        pending_before = count_pending()

        if pending_before == 0:
            print("No pending files.")
            break

        conn = get_connection()
        cur = conn.cursor()

        cur.execute(
            """
            SELECT id, path
            FROM files
            WHERE hash_status='pending'
            ORDER BY id
            LIMIT ?
            """,
            (limit,),
        )

        rows = cur.fetchall()

        if not rows:
            conn.close()
            print("No rows selected.")
            break

        print(f"[HASH] batch={len(rows)} pending_before={pending_before}")

        started = time.time()
        batch_done = 0
        batch_errors = 0

        for row in rows:
            file_id = row["id"]
            file_path = Path(row["path"])

            try:
                if not file_path.exists():
                    cur.execute(
                        """
                        UPDATE files
                        SET hash_status='missing',
                            hash_updated_at=?
                        WHERE id=?
                        """,
                        (utc_now(), file_id),
                    )
                    batch_errors += 1
                    continue

                digest = sha256sum(file_path)

                cur.execute(
                    """
                    UPDATE files
                    SET sha256=?,
                        hash_status='done',
                        hash_updated_at=?
                    WHERE id=?
                    """,
                    (digest, utc_now(), file_id),
                )

                batch_done += 1

            except PermissionError:
                cur.execute(
                    """
                    UPDATE files
                    SET hash_status='permission_error',
                        hash_updated_at=?
                    WHERE id=?
                    """,
                    (utc_now(), file_id),
                )
                batch_errors += 1

            except Exception as e:
                cur.execute(
                    """
                    UPDATE files
                    SET hash_status='error',
                        hash_updated_at=?
                    WHERE id=?
                    """,
                    (utc_now(), file_id),
                )
                print(f"[ERROR] {file_path}: {e}")
                batch_errors += 1

        conn.commit()
        conn.close()

        elapsed = max(time.time() - started, 1)
        total_hashed += batch_done
        total_errors += batch_errors

        print(
            f"[DONE] hashed={batch_done} errors={batch_errors} "
            f"rate={batch_done / elapsed:.2f} files/sec"
        )

        if not loop:
            break

        if sleep_seconds > 0:
            time.sleep(sleep_seconds)

    print(f"[SUMMARY] total_hashed={total_hashed} total_errors={total_errors}")
