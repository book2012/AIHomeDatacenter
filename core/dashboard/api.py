from core.monitoring.snapshot import MonitoringSnapshot


class DashboardAPI:
    def __init__(self, snapshot: MonitoringSnapshot | None = None):
        self.snapshot = snapshot or MonitoringSnapshot()

    def status(self, workers: list[str]):
        return self.snapshot.collect(workers)
