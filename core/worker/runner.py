from abc import ABC, abstractmethod


class Runner(ABC):
    @abstractmethod
    def run(self, command: list[str]) -> str:
        pass
