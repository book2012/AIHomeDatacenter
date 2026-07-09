from core.datacenter.storage_registry import StorageRegistry


def test_storage_registry_root_exists():
    registry = StorageRegistry()

    assert registry.exists() is True


def test_storage_registry_summary():
    registry = StorageRegistry()

    summary = registry.summary()

    assert summary["exists"] is True
    assert "ai" in summary["categories"]
    assert "backup" in summary["categories"]
    assert "plex" in summary["categories"]
    assert "inventory" in summary["categories"]
