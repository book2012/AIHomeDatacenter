from collections import defaultdict
from pathlib import Path

from storage_agent.db import get_connection
from storage_agent.classify import classify_file


ROOT_ALIASES = {
    "archive": "/mnt/storage/Archive",
    "exhdd1": "/mnt/exHDD1",
    "exhdd2": "/mnt/exHDD2",
}


def human_size(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(size_bytes or 0)

    for unit in units:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024

    return f"{size:.2f} PB"


def resolve_root(root: str | None) -> str | None:
    if not root:
        return None

    key = root.lower()
    return ROOT_ALIASES.get(key, root)


def get_top_folder(path: str, root_path: str) -> str:
    try:
        rel = Path(path).relative_to(root_path)
        if not rel.parts:
            return "."
        return rel.parts[0]
    except Exception:
        return "unknown"


def generate_stats(root: str | None = None, top: int = 30):
    selected_root = resolve_root(root)

    conn = get_connection()
    cur = conn.cursor()

    if selected_root:
        cur.execute(
            """
            SELECT root_path, path, extension, size_bytes
            FROM files
            WHERE is_missing = 0
              AND root_path = ?
            """,
            (selected_root,),
        )
    else:
        cur.execute(
            """
            SELECT root_path, path, extension, size_bytes
            FROM files
            WHERE is_missing = 0
            """
        )

    rows = cur.fetchall()
    conn.close()

    if not rows:
        print("No files found.")
        if selected_root:
            print(f"Root filter: {selected_root}")
        return

    root_stats = defaultdict(lambda: {"files": 0, "size": 0})
    category_stats = defaultdict(lambda: {"files": 0, "size": 0})
    folder_stats = defaultdict(lambda: {"files": 0, "size": 0})
    extension_stats = defaultdict(lambda: {"files": 0, "size": 0})
    largest_files = []

    for row in rows:
        root_path = row["root_path"]
        path = row["path"]
        ext = row["extension"] or ""
        size = row["size_bytes"] or 0

        category = classify_file(path, ext)
        top_folder = get_top_folder(path, root_path)

        root_stats[root_path]["files"] += 1
        root_stats[root_path]["size"] += size

        category_stats[category]["files"] += 1
        category_stats[category]["size"] += size

        folder_key = f"{root_path}/{top_folder}"
        folder_stats[folder_key]["files"] += 1
        folder_stats[folder_key]["size"] += size

        extension_stats[ext or "[no extension]"]["files"] += 1
        extension_stats[ext or "[no extension]"]["size"] += size

        largest_files.append((size, path))

    largest_files.sort(reverse=True, key=lambda item: item[0])

    print("=" * 70)
    print("AI Home Datacenter Storage Statistics")
    print("=" * 70)

    if selected_root:
        print(f"Root filter: {selected_root}")
    else:
        print("Root filter: ALL")

    print()

    print("Storage Roots")
    print("-" * 70)
    for root_path, stat in sorted(root_stats.items()):
        print(root_path)
        print(f"  Size : {human_size(stat['size'])}")
        print(f"  Files: {stat['files']:,}")
        print()

    print("Categories")
    print("-" * 70)
    for category, stat in sorted(
        category_stats.items(),
        key=lambda item: item[1]["size"],
        reverse=True,
    ):
        print(f"{category:15} {human_size(stat['size']):>12}  {stat['files']:>10,} files")
    print()

    print(f"Top {top} Folders")
    print("-" * 70)
    for folder, stat in sorted(
        folder_stats.items(),
        key=lambda item: item[1]["size"],
        reverse=True,
    )[:top]:
        print(f"{human_size(stat['size']):>12}  {stat['files']:>10,} files  {folder}")
    print()

    print(f"Top {top} Extensions")
    print("-" * 70)
    for ext, stat in sorted(
        extension_stats.items(),
        key=lambda item: item[1]["size"],
        reverse=True,
    )[:top]:
        print(f"{ext:15} {human_size(stat['size']):>12}  {stat['files']:>10,} files")
    print()

    print(f"Top {top} Largest Files")
    print("-" * 70)
    for size, path in largest_files[:top]:
        print(f"{human_size(size):>12}  {path}")
