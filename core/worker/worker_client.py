from abc import ABC, abstractmethod
from typing import Any, Dict


class WorkerClient(ABC):
    @abstractmethod
    def ready(self) -> Dict[str, Any]:
        pass

    @abstractmethod
    def heartbeat(self) -> Dict[str, Any]:
        pass

    @abstractmethod
    def recovery(self) -> Dict[str, Any]:
        pass

    @abstractmethod
    def status(self) -> Dict[str, Any]:
        pass
