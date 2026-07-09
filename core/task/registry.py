from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import uuid4


@dataclass
class Task:
    id: str
    worker: str
    command: str
    status: str
    started: datetime
    finished: datetime | None = None
    result: Any | None = None
    error: str | None = None


class TaskRegistry:
    def __init__(self):
        self.tasks = {}

    def start(self, worker, command):
        task = Task(
            id=str(uuid4()),
            worker=worker,
            command=command,
            status="RUNNING",
            started=datetime.utcnow(),
        )
        self.tasks[task.id] = task
        return task

    def finish(self, task_id, result=None):
        task = self.tasks[task_id]
        task.status = "FINISHED"
        task.finished = datetime.utcnow()
        task.result = result
        return task

    def fail(self, task_id, error):
        task = self.tasks[task_id]
        task.status = "FAILED"
        task.finished = datetime.utcnow()
        task.error = str(error)
        return task

    def get(self, task_id):
        return self.tasks[task_id]

    def running(self, worker: str | None = None):
        tasks = [
            t for t in self.tasks.values()
            if t.status == "RUNNING"
        ]

        if worker:
            tasks = [t for t in tasks if t.worker == worker]

        return tasks
