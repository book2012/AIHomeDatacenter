from typing import Any, Dict

from core.worker.health import (
    decide_worker_status,
    run_json_script,
)
from core.worker.worker_client import WorkerClient


class UbuntuWorkerClient(WorkerClient):
    def __init__(self, scripts_path: str = "scripts"):
        self.scripts_path = scripts_path

    def _script(self, name: str) -> str:
        return f"{self.scripts_path}/{name}"

    def ready(self) -> Dict[str, Any]:
        return run_json_script(self._script("worker-ready.sh"))

    def heartbeat(self) -> Dict[str, Any]:
        return run_json_script(self._script("worker-heartbeat.sh"))

    def recovery(self) -> Dict[str, Any]:
        return run_json_script(self._script("worker-recovery.sh"))

    def status(self) -> Dict[str, Any]:
        ready = self.ready()
        heartbeat = self.heartbeat()
        recovery = self.recovery()

        return {
            "worker": ready.get("worker"),
            "hostname": ready.get("hostname"),
            "status": decide_worker_status(ready, heartbeat, recovery),
            "ready": ready,
            "heartbeat": heartbeat,
            "recovery": recovery,
        }
