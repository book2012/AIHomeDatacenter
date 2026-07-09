import yaml

from core.worker.local_runner import LocalRunner
from core.worker.ssh_runner import SSHRunner
from core.worker.ubuntu import UbuntuWorkerClient


class WorkerFactory:

    def __init__(self, config_path="config/workers.yaml"):
        with open(config_path, "r") as f:
            self.config = yaml.safe_load(f)

    def create(self, worker_name):

        cfg = self.config["workers"][worker_name]

        if cfg["mode"] == "local":
            runner = LocalRunner()

        else:
            runner = SSHRunner(
                host=cfg["host"],
                user=cfg["user"],
                port=cfg["port"],
            )

        return UbuntuWorkerClient(
            scripts_path=cfg["scripts"],
            runner=runner,
        )
