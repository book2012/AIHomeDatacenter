from core.task.registry import TaskRegistry


def test_registry():

    registry = TaskRegistry()

    task = registry.start(
        "ubuntu-main",
        "backup",
    )

    assert len(registry.running()) == 1

    registry.finish(task.id)

    assert len(registry.running()) == 0
