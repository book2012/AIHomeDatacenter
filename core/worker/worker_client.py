from abc import ABC, abstractmethod
from typing import Any, Dict


class WorkerClient(ABC):

    @abstractmethod
    def ready(self) -> Dict[str, Any]:
        ...

    @abstractmethod
    def heartbeat(self) -> Dict[str, Any]:
        ...

    @abstractmethod
    def recovery(self) -> Dict[str, Any]:
        ...

    @abstractmethod
    def status(self) -> Dict[str, Any]:
        ...

    @abstractmethod
    def execute(self, command: str) -> Dict[str, Any]:
        ...
