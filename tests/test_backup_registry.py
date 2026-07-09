from core.datacenter.backup_registry import BackupRegistry


def test_backup_registry_root_exists():
    registry = BackupRegistry()

    assert registry.exists() is True


def test_backup_registry_summary():
    registry = BackupRegistry()

    summary = registry.summary()

    assert summary["exists"] is True
    assert "ubuntu" in summary["categories"]
    assert "macmini" in summary["categories"]
    assert "databases" in summary["categories"]
