from core.task.registry import TaskRegistry
from core.worker.factory import WorkerFactory


class TaskExecutionManager:
    def __init__(
        self,
        registry: TaskRegistry | None = None,
        worker_factory: WorkerFactory | None = None,
    ):
        self.registry = registry or TaskRegistry()
        self.worker_factory = worker_factory or WorkerFactory()

    def run(self, worker_name: str, command: str):
        task = self.registry.start(worker_name, command)

        try:
            worker = self.worker_factory.create(worker_name)
            result = worker.execute(command)
            return self.registry.finish(task.id, result=result)

        except Exception as exc:
            return self.registry.fail(task.id, error=exc)
