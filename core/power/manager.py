from core.session.session import SessionManager
from core.task.registry import TaskRegistry
from core.worker.factory import WorkerFactory


class PowerManager:
    def __init__(
        self,
        registry: TaskRegistry,
        worker_factory: WorkerFactory | None = None,
    ):
        self.registry = registry
        self.session = SessionManager(registry)
        self.worker_factory = worker_factory or WorkerFactory()

    def can_shutdown(self, worker: str) -> bool:
        return self.session.can_shutdown(worker)

    def shutdown_status(self, worker: str):
        return {
            "worker": worker,
            "can_shutdown": self.can_shutdown(worker),
            "running_tasks": len(self.registry.running(worker)),
        }

    def power_status(self, worker: str):
        client = self.worker_factory.create(worker)
        return client.execute("power")

    def safe_shutdown_request(self, worker: str):
        if not self.can_shutdown(worker):
            return {
                "worker": worker,
                "approved": False,
                "reason": "running_tasks_exist",
                "running_tasks": len(self.registry.running(worker)),
            }

        return {
            "worker": worker,
            "approved": True,
            "reason": "no_running_tasks",
            "power": self.power_status(worker),
        }
