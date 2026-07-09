from core.task.executor import TaskExecutionManager


def test_task_execution_manager_status():
    manager = TaskExecutionManager()

    task = manager.run("ubuntu-main", "status")

    assert task.worker == "ubuntu-main"
    assert task.command == "status"
    assert task.status in ["FINISHED", "FAILED"]

    if task.status == "FINISHED":
        assert task.result["ok"] is True
