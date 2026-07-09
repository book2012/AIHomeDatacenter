from core.session.session import SessionManager, WorkerSessionState
from core.task.registry import TaskRegistry


def test_worker_specific_session_state():
    registry = TaskRegistry()

    registry.start("ubuntu-main", "backup")

    session = SessionManager(registry)

    assert session.state("ubuntu-main") == WorkerSessionState.BUSY
    assert session.state("gpu-worker") == WorkerSessionState.IDLE

    assert not session.can_shutdown("ubuntu-main")
    assert session.can_shutdown("gpu-worker")


def test_session_summary():
    registry = TaskRegistry()
    registry.start("ubuntu-main", "backup")

    session = SessionManager(registry)

    summary = session.summary(["ubuntu-main", "gpu-worker"])

    assert summary["ubuntu-main"]["state"] == "BUSY"
    assert summary["ubuntu-main"]["running_tasks"] == 1
    assert summary["gpu-worker"]["state"] == "IDLE"
    assert summary["gpu-worker"]["running_tasks"] == 0
