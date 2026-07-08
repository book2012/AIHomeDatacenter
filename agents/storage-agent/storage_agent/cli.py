import argparse

from storage_agent.config import load_config, get_enabled_scan_roots
from storage_agent.db import init_db
from storage_agent.scanner import scan_root


def run_scan():
    config = load_config()

    exclude_dirs = config.get("scan", {}).get("exclude", {}).get("directories", [])
    exclude_exts = config.get("scan", {}).get("exclude", {}).get("extensions", [])
    exclude_exts = [ext.lower() for ext in exclude_exts]

    roots = get_enabled_scan_roots(config)

    init_db()

    total_files = 0

    for root in roots:
        print(f"Scan root: {root['name']} -> {root['path']}")
        files_found = scan_root(root, exclude_dirs, exclude_exts)
        total_files += files_found
        print(f"Files found: {files_found}")

    print(f"Scan completed. Total files: {total_files}")


def run_hash(args):
    from storage_agent.hasher import hash_pending

    hash_pending(
        limit=args.limit,
        loop=args.loop,
        sleep_seconds=args.sleep,
    )


def run_duplicates():
    from storage_agent.duplicate import generate_duplicate_report

    generate_duplicate_report()


def main():
    parser = argparse.ArgumentParser(
        description="AI Home Datacenter Storage Agent"
    )

    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("scan", help="Run inventory scan")

    hash_parser = subparsers.add_parser("hash", help="Run SHA256 hash worker")
    hash_parser.add_argument("--limit", type=int, default=100)
    hash_parser.add_argument("--loop", action="store_true")
    hash_parser.add_argument("--sleep", type=float, default=0.0)

    subparsers.add_parser("duplicates", help="Generate duplicate candidate report")
    stats_parser = subparsers.add_parser("stats", help="Generate storage statistics")
    stats_parser.add_argument("--root", type=str, default=None)
    stats_parser.add_argument("--top", type=int, default=30)

    cleanup_parser = subparsers.add_parser("cleanup", help="Move cleanup candidates to trash")
    cleanup_parser.add_argument("--execute", action="store_true")

    classify_parser = subparsers.add_parser(
            "classify-folder",
                help="Classify files in a folder by extension"
                )
    classify_parser.add_argument("--path", required=True)
    classify_parser.add_argument("--execute", action="store_true")

    args = parser.parse_args()

    if args.command == "scan":
        run_scan()
    elif args.command == "hash":
        run_hash(args)
    elif args.command == "duplicates":
        run_duplicates()
    elif args.command == "stats":
        from storage_agent.stats import generate_stats
        generate_stats()
    elif args.command == "cleanup":
        from storage_agent.cleanup import move_candidates
        move_candidates(dry_run=not args.execute)
    elif args.command == "classify-folder":
        from storage_agent.folder_classifier import classify_folder
        classify_folder(path=args.path, execute=args.execute)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
