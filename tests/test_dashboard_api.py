from core.dashboard.api import DashboardAPI


def test_dashboard_status():
    api = DashboardAPI()

    data = api.status(["ubuntu-main"])

    assert "brain" in data
    assert "storage" in data
    assert "backup" in data
    assert "workers" in data
    assert "ubuntu-main" in data["workers"]
    assert "worker" in data["workers"]["ubuntu-main"]
    assert "session" in data["workers"]["ubuntu-main"]
    assert "power" in data["workers"]["ubuntu-main"]
