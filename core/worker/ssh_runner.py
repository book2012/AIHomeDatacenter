import subprocess

from core.worker.runner import Runner


class SSHRunner(Runner):
    def __init__(
        self,
        host: str,
        user: str | None = None,
        port: int | None = None,
        identity_file: str | None = None,
    ):
        self.host = host
        self.user = user if user else None
        self.port = port
        self.identity_file = identity_file

    def run(self, command: list[str]) -> str:
        remote = " ".join(command)

        target = self.host
        if self.user:
            target = f"{self.user}@{self.host}"

        ssh_command = ["ssh"]

        if self.port:
            ssh_command.extend(["-p", str(self.port)])

        if self.identity_file:
            ssh_command.extend([
                "-i",
                self.identity_file,
                "-o",
                "IdentitiesOnly=yes",
            ])

        ssh_command.extend([target, remote])

        result = subprocess.run(
            ssh_command,
            capture_output=True,
            text=True,
            check=True,
        )

        return result.stdout.strip()
