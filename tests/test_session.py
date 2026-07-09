from core.session.session import SessionManager, WorkerSessionState
from core.task.registry import TaskRegistry


def test_idle():
    registry = TaskRegistry()
    session = SessionManager(registry)

    assert session.state() == WorkerSessionState.IDLE
    assert session.can_shutdown()


def test_busy():
    registry = TaskRegistry()

    registry.start(
        "ubuntu-main",
        "backup",
    )

    session = SessionManager(registry)

    assert session.state() == WorkerSessionState.BUSY
    assert not session.can_shutdown()
