import subprocess

from core.worker.runner import Runner


class SSHRunner(Runner):

    def __init__(
        self,
        host: str,
        user: str,
        port: int = 22,
    ):
        self.host = host
        self.user = user
        self.port = port

    def run(self, command: list[str]) -> str:

        remote = " ".join(command)

        result = subprocess.run(
            [
                "ssh",
                "-p",
                str(self.port),
                f"{self.user}@{self.host}",
                remote,
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        return result.stdout.strip()
