from enum import Enum

from core.task.registry import TaskRegistry


class WorkerSessionState(str, Enum):
    OFFLINE = "OFFLINE"
    READY = "READY"
    BUSY = "BUSY"
    IDLE = "IDLE"
    SHUTDOWN_ALLOWED = "SHUTDOWN_ALLOWED"


class SessionManager:
    def __init__(self, registry: TaskRegistry):
        self.registry = registry

    def state(self, worker: str | None = None):
        running = self.registry.running(worker)

        if running:
            return WorkerSessionState.BUSY

        return WorkerSessionState.IDLE

    def can_shutdown(self, worker: str | None = None):
        return len(self.registry.running(worker)) == 0

    def summary(self, workers: list[str]):
        return {
            worker: {
                "state": self.state(worker).value,
                "can_shutdown": self.can_shutdown(worker),
                "running_tasks": len(self.registry.running(worker)),
            }
            for worker in workers
        }
