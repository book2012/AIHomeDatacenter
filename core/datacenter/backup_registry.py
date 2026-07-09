from pathlib import Path
from typing import Dict, Any

import yaml


class BackupRegistry:
    def __init__(self, config_path: str = "config/backup.yaml"):
        with open(config_path, "r") as f:
            self.config = yaml.safe_load(f)

        self.root = Path(self.config["backup"]["root"])
        self.categories = self.config["backup"]["categories"]

    def exists(self) -> bool:
        return self.root.exists() and self.root.is_dir()

    def category_path(self, name: str) -> Path:
        if name not in self.categories:
            raise KeyError(f"Unknown backup category: {name}")

        return self.root / self.categories[name]

    def category_status(self, name: str) -> Dict[str, Any]:
        path = self.category_path(name)

        files = []
        directories = []

        if path.exists():
            for item in path.iterdir():
                if item.is_file():
                    files.append(item.name)
                elif item.is_dir():
                    directories.append(item.name)

        return {
            "name": name,
            "path": str(path),
            "exists": path.exists(),
            "files": sorted(files),
            "directories": sorted(directories),
            "file_count": len(files),
            "directory_count": len(directories),
        }

    def summary(self) -> Dict[str, Any]:
        return {
            "root": str(self.root),
            "exists": self.exists(),
            "categories": {
                name: self.category_status(name)
                for name in self.categories
            },
        }
