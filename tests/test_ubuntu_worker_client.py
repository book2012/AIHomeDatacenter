from core.worker.ubuntu import UbuntuWorkerClient


def test_ubuntu_worker_client_status():
    client = UbuntuWorkerClient(scripts_path="scripts")
    result = client.status()

    assert result["worker"] == "ubuntu-storage-worker"
    assert result["hostname"]
    assert result["status"] in ["READY", "ONLINE", "WARNING", "RECOVERY", "OFFLINE", "UNKNOWN"]
