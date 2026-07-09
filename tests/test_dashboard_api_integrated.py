from core.dashboard.api import DashboardAPI


def test_dashboard_integrated_status_without_workers():
    api = DashboardAPI()

    data = api.status()

    assert data["brain"]["state"] == "ONLINE"
    assert data["brain"]["standalone"] is True
    assert data["storage"]["exists"] is True
    assert data["backup"]["exists"] is True
    assert data["workers"] == {}


def test_dashboard_integrated_status_with_worker():
    api = DashboardAPI()

    data = api.status(["ubuntu-main"])

    assert data["brain"]["state"] == "ONLINE"
    assert "ubuntu-main" in data["workers"]
