import subprocess

from core.worker.runner import Runner


class SSHRunner(Runner):

    def __init__(
        self,
        host,
        user=None,
        port=None,
        identity_file=None,
    ):
        self.host = host
        self.user = user
        self.port = port
        self.identity_file = identity_file

    def run(self, command):

        if isinstance(command, list):
            command = " ".join(command)

        target = self.host

        if self.user:
            target = f"{self.user}@{self.host}"

        ssh = ["ssh"]

        if self.port:
            ssh.extend(["-p", str(self.port)])

        if self.identity_file:
            ssh.extend(
                [
                    "-i",
                    self.identity_file,
                    "-o",
                    "IdentitiesOnly=yes",
                ]
            )

        ssh.extend([target, command])

        result = subprocess.run(
            ssh,
            capture_output=True,
            text=True,
            check=True,
        )

        return result.stdout.strip()
