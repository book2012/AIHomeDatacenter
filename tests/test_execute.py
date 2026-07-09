from core.worker.factory import WorkerFactory


def test_execute_status():
    worker = WorkerFactory().create("ubuntu-main")

    result = worker.execute("status")

    assert result["ok"] is True
    assert result["command"] == "status"
    assert result["format"] in ["json", "text"]
