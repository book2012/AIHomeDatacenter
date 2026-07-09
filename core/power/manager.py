from core.session.session import SessionManager
from core.task.registry import TaskRegistry


class PowerManager:
    def __init__(self, registry: TaskRegistry):
        self.registry = registry
        self.session = SessionManager(registry)

    def can_shutdown(self, worker: str) -> bool:
        return self.session.can_shutdown(worker)

    def shutdown_status(self, worker: str):
        return {
            "worker": worker,
            "can_shutdown": self.can_shutdown(worker),
            "running_tasks": len(self.registry.running(worker)),
        }
