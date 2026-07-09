import subprocess
import shlex

from core.worker.runner import Runner


class LocalRunner(Runner):

    def run(self, command) -> str:

        if isinstance(command, str):
            command = shlex.split(command)

        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True,
        )

        return result.stdout.strip()
