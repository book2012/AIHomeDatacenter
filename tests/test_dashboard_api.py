from core.dashboard.api import DashboardAPI


def test_dashboard_status():
    api = DashboardAPI()

    data = api.status(["ubuntu-main"])

    assert "ubuntu-main" in data
    assert "worker" in data["ubuntu-main"]
    assert "session" in data["ubuntu-main"]
    assert "power" in data["ubuntu-main"]
