from core.worker.ssh_runner import SSHRunner
from core.worker.ubuntu import UbuntuWorkerClient


def test_remote_ready():

    runner = SSHRunner(
        host="localhost",
        user="han",
    )

    client = UbuntuWorkerClient(
        runner=runner,
        scripts_path="/opt/controlcenter/scripts",
    )

    ready = client.ready()

    assert ready["ready"] is True
