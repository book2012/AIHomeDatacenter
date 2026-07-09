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

    def state(self):

        running = self.registry.running()

        if running:
            return WorkerSessionState.BUSY

        return WorkerSessionState.IDLE

    def can_shutdown(self):

        return len(self.registry.running()) == 0
