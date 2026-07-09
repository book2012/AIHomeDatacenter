import json
from typing import Any, Dict

from core.worker.runner import Runner


def run_json_script(runner: Runner, script_path: str) -> Dict[str, Any]:
    output = runner.run(["bash", script_path])

    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON from {script_path}: {exc}") from exc


def run_worker_command(
    runner: Runner,
    script_path: str,
    command: str,
) -> Dict[str, Any]:
    output = runner.run(["bash", script_path, command])

    try:
        parsed = json.loads(output)
        return {
            "command": command,
            "ok": True,
            "format": "json",
            "result": parsed,
        }
    except json.JSONDecodeError:
        return {
            "command": command,
            "ok": True,
            "format": "text",
            "output": output,
        }


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
