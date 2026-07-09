from core.worker.ssh_runner import SSHRunner


def test_create_runner():

    runner = SSHRunner(
        host="localhost",
        user="han",
    )

    assert runner.host == "localhost"
    assert runner.user == "han"
