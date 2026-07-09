from core.agent.base import BaseAgent


class StatusAgent(BaseAgent):
    def __init__(self, worker: str = "ubuntu-main", executor=None):
        super().__init__(executor=executor)
        self.worker = worker

    def run(self):
        return self.executor.run(self.worker, "status")
