from core.monitoring.snapshot import MonitoringSnapshot


def test_monitoring_snapshot():
    snapshot = MonitoringSnapshot()

    data = snapshot.collect(["ubuntu-main"])

    assert "ubuntu-main" in data
    assert "worker" in data["ubuntu-main"]
    assert "session" in data["ubuntu-main"]
    assert "power" in data["ubuntu-main"]
