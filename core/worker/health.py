import json
from typing import Any, Dict

from core.worker.runner import Runner


def run_json_script(runner: Runner, script_path: str) -> Dict[str, Any]:
    output = runner.run(["bash", script_path])

    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON from {script_path}: {exc}") from exc


def decide_worker_status(
    ready: Dict[str, Any],
    heartbeat: Dict[str, Any],
    recovery: Dict[str, Any],
) -> str:
    if not ready.get("ready"):
        return "OFFLINE"

    if recovery.get("issues"):
        return "RECOVERY"

    checks = ready.get("checks", {})
    if any(value != "OK" for value in checks.values()):
        return "WARNING"

    if heartbeat.get("state") == "ONLINE":
        return "ONLINE"

    if ready.get("state") == "READY":
        return "READY"

    return "UNKNOWN"
