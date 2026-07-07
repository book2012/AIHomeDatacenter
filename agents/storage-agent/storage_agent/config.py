from pathlib import Path
import yaml


DEFAULT_CONFIG_PATH = Path("config/agent.yaml")


def load_config(config_path: str | Path = DEFAULT_CONFIG_PATH) -> dict:
    path = Path(config_path)

    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")

    with path.open("r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    if not isinstance(config, dict):
        raise ValueError("Config file is empty or invalid")

    return config


def get_enabled_scan_roots(config: dict) -> list[dict]:
    roots = config.get("scan", {}).get("roots", [])
    return [root for root in roots if root.get("enabled") is True]
