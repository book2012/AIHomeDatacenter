from core.power.manager import PowerManager
from core.session.session import SessionManager
from core.task.registry import TaskRegistry
from core.worker.factory import WorkerFactory


class MonitoringSnapshot:
    def __init__(
        self,
        registry: TaskRegistry | None = None,
        worker_factory: WorkerFactory | None = None,
    ):
        self.registry = registry or TaskRegistry()
        self.worker_factory = worker_factory or WorkerFactory()
        self.session = SessionManager(self.registry)
        self.power = PowerManager(
            registry=self.registry,
            worker_factory=self.worker_factory,
        )

    def collect(self, workers: list[str]):
        data = {}

        for worker_name in workers:
            try:
                worker = self.worker_factory.create(worker_name)
                worker_status = worker.status()
                error = None
            except Exception as exc:
                worker_status = {
                    "worker": worker_name,
                    "status": "OPTIONAL_UNAVAILABLE",
                    "optional": True,
                }
                error = str(exc)

            data[worker_name] = {
                "worker": worker_status,
                "session": {
                    "state": self.session.state(worker_name).value,
                    "can_shutdown": self.session.can_shutdown(worker_name),
                    "running_tasks": len(self.registry.running(worker_name)),
                },
                "power": self.power.shutdown_status(worker_name),
                "error": error,
            }

        return data
