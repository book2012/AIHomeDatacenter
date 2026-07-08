from pathlib import Path


PHOTO_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif",
    ".raw", ".cr2", ".nef", ".arw", ".dng", ".tiff", ".tif"
}

DOCUMENT_EXTENSIONS = {
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".txt", ".rtf", ".odt", ".ods", ".odp", ".hwp", ".hwpx"
}

VIDEO_EXTENSIONS = {
    ".mp4", ".mov", ".avi", ".mkv", ".wmv", ".flv", ".webm", ".m4v"
}

AUDIO_EXTENSIONS = {
    ".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma"
}

ARCHIVE_EXTENSIONS = {
    ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz"
}

INSTALLER_EXTENSIONS = {
    ".exe", ".msi", ".dmg", ".pkg", ".apk", ".deb", ".rpm", ".iso"
}

TEMP_EXTENSIONS = {
    ".tmp", ".temp", ".part", ".crdownload", ".bak", ".old"
}

SOURCE_CODE_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx",
    ".html", ".css", ".scss",
    ".java", ".c", ".cpp", ".h", ".hpp",
    ".cs", ".go", ".rs", ".php", ".rb",
    ".swift", ".kt",
    ".sh", ".bash", ".zsh", ".ps1",
    ".sql", ".json", ".yaml", ".yml",
    ".toml", ".xml", ".md",
}

SOURCE_CODE_FILENAMES = {
    "Dockerfile",
    "docker-compose.yml",
    "compose.yml",
    "Makefile",
    "package.json",
    "requirements.txt",
    "pyproject.toml",
    "go.mod",
    "Cargo.toml",
}


def classify_file(path: str, extension: str | None = None) -> str:
    p = Path(path)
    name = p.name
    ext = (extension or p.suffix).lower()

    if name in SOURCE_CODE_FILENAMES:
        return "source_code"

    if ext in PHOTO_EXTENSIONS:
        return "photos"
    if ext in DOCUMENT_EXTENSIONS:
        return "documents"
    if ext in VIDEO_EXTENSIONS:
        return "videos"
    if ext in AUDIO_EXTENSIONS:
        return "audio"
    if ext in ARCHIVE_EXTENSIONS:
        return "archives"
    if ext in INSTALLER_EXTENSIONS:
        return "installers"
    if ext in TEMP_EXTENSIONS:
        return "temporary"
    if ext in SOURCE_CODE_EXTENSIONS:
        return "source_code"

    return "others"
