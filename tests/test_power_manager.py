from core.power.manager import PowerManager
from core.task.registry import TaskRegistry


def test_power_manager_can_shutdown_when_idle():
    registry = TaskRegistry()
    power = PowerManager(registry)

    assert power.can_shutdown("ubuntu-main") is True


def test_power_manager_blocks_shutdown_when_busy():
    registry = TaskRegistry()
    registry.start("ubuntu-main", "backup")

    power = PowerManager(registry)

    assert power.can_shutdown("ubuntu-main") is False
    assert power.shutdown_status("ubuntu-main")["running_tasks"] == 1
