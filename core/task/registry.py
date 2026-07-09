from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4


@dataclass
class Task:

    id: str

    worker: str

    command: str

    status: str

    started: datetime


class TaskRegistry:

    def __init__(self):

        self.tasks = {}

    def start(
        self,
        worker,
        command,
    ):

        task = Task(
            id=str(uuid4()),
            worker=worker,
            command=command,
            status="RUNNING",
            started=datetime.utcnow(),
        )

        self.tasks[task.id] = task

        return task

    def finish(
        self,
        task_id,
    ):

        self.tasks[task_id].status = "FINISHED"

    def running(self):

        return [
            t
            for t in self.tasks.values()
            if t.status == "RUNNING"
        ]
