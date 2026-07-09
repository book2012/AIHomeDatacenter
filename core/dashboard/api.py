from core.brain.status import BrainStatus
from core.datacenter.backup_registry import BackupRegistry
from core.datacenter.storage_registry import StorageRegistry
from core.monitoring.snapshot import MonitoringSnapshot


class DashboardAPI:
    def __init__(
        self,
        snapshot: MonitoringSnapshot | None = None,
        brain: BrainStatus | None = None,
        storage: StorageRegistry | None = None,
        backup: BackupRegistry | None = None,
    ):
        self.snapshot = snapshot or MonitoringSnapshot()
        self.brain = brain or BrainStatus()
        self.storage = storage or StorageRegistry()
        self.backup = backup or BackupRegistry()

    def status(self, workers: list[str] | None = None):
        workers = workers or []

        return {
            "brain": self.brain.status(),
            "storage": self.storage.summary(),
            "backup": self.backup.summary(),
            "workers": self.snapshot.collect(workers) if workers else {},
        }
