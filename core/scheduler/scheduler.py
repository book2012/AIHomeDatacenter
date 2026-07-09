from dataclasses import dataclass
from typing import List

from core.task.executor import TaskExecutionManager


@dataclass
class ScheduledJob:
    name: str
    worker: str
    command: str
    enabled: bool = True


class Scheduler:
    def __init__(self, executor: TaskExecutionManager | None = None):
        self.executor = executor or TaskExecutionManager()
        self.jobs: List[ScheduledJob] = []

    def add_job(self, name: str, worker: str, command: str, enabled: bool = True):
        job = ScheduledJob(
            name=name,
            worker=worker,
            command=command,
            enabled=enabled,
        )
        self.jobs.append(job)
        return job

    def list_jobs(self):
        return self.jobs

    def run_job(self, name: str):
        for job in self.jobs:
            if job.name == name:
                if not job.enabled:
                    raise RuntimeError(f"Job is disabled: {name}")
                return self.executor.run(job.worker, job.command)

        raise KeyError(f"Job not found: {name}")
