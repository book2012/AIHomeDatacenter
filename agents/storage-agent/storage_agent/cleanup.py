from pathlib import Path
import shutil
from datetime import datetime

from storage_agent.db import get_connection
from storage_agent.classify import classify_file


ROOT = "/mnt/exHDD1"
TRASH_DIR = "/mnt/exHDD1/_cleanup_trash"

KEEP_CATEGORIES = {
    "photos",
    "documents",
    "source_code",
}


def safe_target_path(src: Path, trash_root: Path) -> Path:
    rel = src.relative_to(ROOT)
    target = trash_root / rel

    if not target.exists():
        return target

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return target.with_name(f"{target.name}.moved.{timestamp}")


def generate_cleanup_plan():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT path, extension, size_bytes
        FROM files
        WHERE root_path = ?
          AND is_missing = 0
        ORDER BY path
        """,
        (ROOT,),
    )

    rows = cur.fetchall()
    conn.close()

    keep = []
    move = []

    for row in rows:
        category = classify_file(row["path"], row["extension"])

        item = {
            "path": row["path"],
            "category": category,
            "size_bytes": row["size_bytes"],
        }

        if category in KEEP_CATEGORIES:
            keep.append(item)
        else:
            move.append(item)

    print(f"KEEP files: {len(keep):,}")
    print(f"MOVE candidates: {len(move):,}")

    return keep, move


def move_candidates(dry_run: bool = True):
    keep, move = generate_cleanup_plan()

    trash_root = Path(TRASH_DIR)
    moved = 0
    skipped = 0

    if not dry_run:
        trash_root.mkdir(parents=True, exist_ok=True)

    for item in move:
        src = Path(item["path"])

        if not src.exists():
            skipped += 1
            continue

        target = safe_target_path(src, trash_root)

        print(f"{'[DRY-RUN]' if dry_run else '[MOVE]'} {src} -> {target}")

        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(target))

        moved += 1

    print()
    print(f"Moved candidates: {moved:,}")
    print(f"Skipped missing : {skipped:,}")
    print(f"Trash dir       : {TRASH_DIR}")
