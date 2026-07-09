from core.monitoring.snapshot import MonitoringSnapshot


def test_optional_worker_unavailable():
    snapshot = MonitoringSnapshot()

    data = snapshot.collect(["missing-worker"])

    assert "missing-worker" in data
    assert data["missing-worker"]["worker"]["status"] == "OPTIONAL_UNAVAILABLE"
    assert data["missing-worker"]["worker"]["optional"] is True
