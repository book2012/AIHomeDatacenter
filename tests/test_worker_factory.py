from core.worker.factory import WorkerFactory


def test_factory_local():

    factory = WorkerFactory()

    worker = factory.create("ubuntu-main")

    result = worker.status()

    assert result["status"] == "ONLINE"
