import json
import subprocess
from dataclasses import dataclass
from typing import Any, Dict


@dataclass
class CommandResult:
    ok: bool
    stdout: str
    stderr: str
    returncode: int


def run_command(command: list[str]) -> CommandResult:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )

    return CommandResult(
        ok=result.returncode == 0,
        stdout=result.stdout.strip(),
        stderr=result.stderr.strip(),
        returncode=result.returncode,
    )


def run_json_script(script_path: str) -> Dict[str, Any]:
    result = run_command(["bash", script_path])

    if not result.ok:
        raise RuntimeError(f"Command failed: {script_path}\n{result.stderr}")

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON from {script_path}: {exc}") from exc


def get_worker_ready() -> Dict[str, Any]:
    return run_json_script("scripts/worker-ready.sh")


def get_worker_heartbeat() -> Dict[str, Any]:
    return run_json_script("scripts/worker-heartbeat.sh")


def get_worker_recovery() -> Dict[str, Any]:
    return run_json_script("scripts/worker-recovery.sh")


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


def get_worker_status() -> Dict[str, Any]:
    ready = get_worker_ready()
    heartbeat = get_worker_heartbeat()
    recovery = get_worker_recovery()

    status = decide_worker_status(ready, heartbeat, recovery)

    return {
        "worker": ready.get("worker"),
        "hostname": ready.get("hostname"),
        "status": status,
        "ready": ready,
        "heartbeat": heartbeat,
        "recovery": recovery,
    }
