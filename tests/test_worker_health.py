from core.worker.health import decide_worker_status


def test_worker_online():
    ready = {
        "ready": True,
        "state": "READY",
        "checks": {"storage": "OK", "docker": "OK"},
    }
    heartbeat = {"state": "ONLINE"}
    recovery = {"state": "OK", "issues": []}

    assert decide_worker_status(ready, heartbeat, recovery) == "ONLINE"


def test_worker_warning_when_check_failed():
    ready = {
        "ready": True,
        "state": "READY",
        "checks": {"storage": "OK", "docker": "FAIL"},
    }
    heartbeat = {"state": "ONLINE"}
    recovery = {"state": "OK", "issues": []}

    assert decide_worker_status(ready, heartbeat, recovery) == "WARNING"


def test_worker_recovery_when_issues_exist():
    ready = {
        "ready": True,
        "state": "READY",
        "checks": {"storage": "OK", "docker": "OK"},
    }
    heartbeat = {"state": "ONLINE"}
    recovery = {"state": "OK", "issues": ["disk-error"]}

    assert decide_worker_status(ready, heartbeat, recovery) == "RECOVERY"
