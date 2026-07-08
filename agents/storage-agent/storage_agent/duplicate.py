import json
from pathlib import Path
from datetime import datetime, timezone

from storage_agent.db import get_connection


ARCHIVE_PREFIX = "/mnt/storage/Archive"
HDD_PREFIXES = [
    "/mnt/exHDD1",
    "/mnt/exHDD2",
]

REPORT_DIR = Path("reports")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def human_size(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(size_bytes)

    for unit in units:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024

    return f"{size:.2f} PB"


def is_archive(path: str) -> bool:
    return path.startswith(ARCHIVE_PREFIX)


def is_hdd(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in HDD_PREFIXES)


def find_duplicate_candidates():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT sha256
        FROM files
        WHERE sha256 IS NOT NULL
          AND hash_status = 'done'
        GROUP BY sha256
        HAVING COUNT(*) > 1
        """
    )

    hashes = [row["sha256"] for row in cur.fetchall()]

    results = []
    total_candidates = 0
    total_reclaim_bytes = 0

    for sha256 in hashes:
        cur.execute(
            """
            SELECT id, path, size_bytes, root_path
            FROM files
            WHERE sha256 = ?
            ORDER BY path
            """,
            (sha256,),
        )

        files = [dict(row) for row in cur.fetchall()]

        archive_files = [f for f in files if is_archive(f["path"])]
        hdd_files = [f for f in files if is_hdd(f["path"])]

        if not archive_files or not hdd_files:
            continue

        candidates = hdd_files
        reclaim_bytes = sum(f["size_bytes"] for f in candidates)

        results.append(
            {
                "sha256": sha256,
                "keep": archive_files,
                "delete_candidates": candidates,
                "reclaim_bytes": reclaim_bytes,
            }
        )

        total_candidates += len(candidates)
        total_reclaim_bytes += reclaim_bytes

    conn.close()

    return {
        "generated_at": utc_now(),
        "policy": {
            "keep": ARCHIVE_PREFIX,
            "delete_candidates": HDD_PREFIXES,
            "auto_delete": False,
            "requires_human_approval": True,
        },
        "summary": {
            "duplicate_groups": len(results),
            "delete_candidates": total_candidates,
            "potential_reclaim_bytes": total_reclaim_bytes,
            "potential_reclaim_human": human_size(total_reclaim_bytes),
        },
        "groups": results,
    }


def write_json_report(report: dict) -> Path:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = REPORT_DIR / "duplicate_candidates.json"

    with path.open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    return path


def write_markdown_report(report: dict) -> Path:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = REPORT_DIR / "duplicate_candidates.md"

    summary = report["summary"]

    lines = []
    lines.append("# Duplicate Candidates Report")
    lines.append("")
    lines.append(f"Generated at: `{report['generated_at']}`")
    lines.append("")
    lines.append("## Policy")
    lines.append("")
    lines.append("- Archive files are treated as original files.")
    lines.append("- HDD files with the same SHA256 as Archive files are delete candidates.")
    lines.append("- No automatic deletion is performed.")
    lines.append("- Human approval is required before deleting anything.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- Duplicate groups: `{summary['duplicate_groups']}`")
    lines.append(f"- Delete candidates: `{summary['delete_candidates']}`")
    lines.append(f"- Potential reclaim: `{summary['potential_reclaim_human']}`")
    lines.append("")

    for index, group in enumerate(report["groups"], start=1):
        lines.append(f"## Group {index}")
        lines.append("")
        lines.append(f"SHA256: `{group['sha256']}`")
        lines.append(f"Potential reclaim: `{human_size(group['reclaim_bytes'])}`")
        lines.append("")
        lines.append("### KEEP")
        lines.append("")
        for item in group["keep"]:
            lines.append(f"- `{item['path']}` ({human_size(item['size_bytes'])})")
        lines.append("")
        lines.append("### DELETE CANDIDATES")
        lines.append("")
        for item in group["delete_candidates"]:
            lines.append(f"- `{item['path']}` ({human_size(item['size_bytes'])})")
        lines.append("")

    with path.open("w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return path


def generate_duplicate_report():
    report = find_duplicate_candidates()

    json_path = write_json_report(report)
    md_path = write_markdown_report(report)

    summary = report["summary"]

    print(f"Duplicate groups found: {summary['duplicate_groups']}")
    print(f"Delete candidates: {summary['delete_candidates']}")
    print(f"Potential reclaim: {summary['potential_reclaim_human']}")
    print(f"JSON report: {json_path}")
    print(f"Markdown report: {md_path}")
