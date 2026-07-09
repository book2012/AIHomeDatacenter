import subprocess

from core.worker.runner import Runner


class LocalRunner(Runner):
    def run(self, command: list[str]) -> str:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
