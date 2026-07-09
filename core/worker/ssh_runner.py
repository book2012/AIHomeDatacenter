from core.worker.runner import Runner


class SSHRunner(Runner):
    def __init__(self, host: str):
        self.host = host

    def run(self, command: list[str]) -> str:
        raise NotImplementedError("SSHRunner is not implemented yet")
