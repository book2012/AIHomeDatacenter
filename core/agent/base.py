from abc import ABC, abstractmethod

from core.task.executor import TaskExecutionManager


class BaseAgent(ABC):
    def __init__(self, executor: TaskExecutionManager | None = None):
        self.executor = executor or TaskExecutionManager()

    @abstractmethod
    def run(self):
        ...
