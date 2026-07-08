from pathlib import Path
import shutil

from storage_agent.classify import classify_file


def classify_folder(path: str, execute: bool = False):
    root = Path(path).resolve()
    classified_root = root / "_classified"

    if not root.exists() or not root.is_dir():
        raise NotADirectoryError(f"Invalid folder: {root}")

    moved = 0
    skipped = 0

    for file_path in root.rglob("*"):
        if not file_path.is_file():
            continue

        if "_classified" in file_path.parts:
            continue

        category = classify_file(str(file_path), file_path.suffix)
        relative_path = file_path.relative_to(root)
        target = classified_root / category / relative_path

        print(f"{'[MOVE]' if execute else '[DRY-RUN]'} {file_path} -> {target}")

        if execute:
            target.parent.mkdir(parents=True, exist_ok=True)

            if target.exists():
                skipped += 1
                print(f"[SKIP] target exists: {target}")
                continue

            shutil.move(str(file_path), str(target))

        moved += 1

    print()
    print(f"Folder       : {root}")
    print(f"Classified   : {classified_root}")
    print(f"Processed    : {moved:,}")
    print(f"Skipped      : {skipped:,}")
    print(f"Execute      : {execute}")
