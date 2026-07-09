from core.power.manager import PowerManager
from core.task.registry import TaskRegistry


def test_safe_shutdown_blocked_when_busy():
    registry = TaskRegistry()
    registry.start("ubuntu-main", "backup")

    power = PowerManager(registry)

    result = power.safe_shutdown_request("ubuntu-main")

    assert result["approved"] is False
    assert result["reason"] == "running_tasks_exist"


def test_safe_shutdown_approved_when_idle():
    registry = TaskRegistry()
    power = PowerManager(registry)

    result = power.safe_shutdown_request("ubuntu-main")

    assert result["approved"] is True
    assert result["reason"] == "no_running_tasks"
