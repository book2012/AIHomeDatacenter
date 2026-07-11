2026-07-06

Project Created

Ubuntu22 Upgrade Complete

Legacy Snapshot Complete

Windows Docker Development Environment Ready
## 2026-07-06 - Sprint 6-2
- Immich production deployment added.
- Immich version pinned to v2.6.0.
- Photo storage mapped to /mnt/storage/Photos.
- PostgreSQL and Redis/Valkey separated for Immich.
- Immich service verified healthy.

## 2026-07-06 - Sprint 6-2
- Immich production deployment added.
- Immich version pinned to v2.6.0.
- Photo storage mapped to /mnt/storage/Photos.
- PostgreSQL and Redis/Valkey separated for Immich.
- Immich service verified healthy.

Nextcloud data path migrated to:
/mnt/storage/Archive/Nextcloud

## 2026-07-10 — Ubuntu Runtime v0.2

### Added

- Backup status reporting
- Inventory index reporting
- JSON runtime summary
- Runtime health score
- Health status command
- Central runtime configuration

### Safety

- Read-only Runtime commands
- No automatic file deletion
- No service restart
- No large media scan

## 2026-07 — Inventory Stabilization

### Added

- Legacy Inventory read-only analysis
- Hash status migration preview
- Duplicate preview reporting
- Root-to-root duplicate analysis
- Archive-master cleanup preview
- Duplicate candidate reliability validation
- Project audit command
- Sprint gap reporting

### Policy

- Archive remains the Master Repository
- Existing SHA256 results are preserved
- Immich and Nextcloud are excluded from current analysis
- No automatic deletion is allowed
- User approval is required before cleanup

## 2026-07 — Hash Safety Foundation

### Added

- Existing SHA256 inventory audit
- Pending hash queue preview
- Queue path and size validation
- Limited SHA256 dry run
- Database apply preview
- Transaction apply safety gate
- Rollback verification on copied database
- SQLite backup and restore verification
- Limited batch dry run
- Batch apply preview

### Safety

- Existing SHA256 values are never overwritten
- Immich and Nextcloud remain excluded
- Runtime database backups are excluded from Git
- Hash batches have file and byte limits
- Database writes use transactions
- Failures require rollback
- Automatic file deletion remains disabled

## 2026-07 — Sprint 5 — Hash Safety Foundation

### Added

- Existing SHA256 audit
- Pending Hash Queue Preview
- Queue path and size validation
- Limited SHA256 Dry Run
- Database Apply Preview
- Transaction safety gate
- Rollback verification using copied database
- SQLite backup and restore verification
- Limited Batch Dry Run
- Batch Apply Preview

### Architecture Decision

- Full Duplicate rebuild is not used as the normal operating model.
- Duplicate processing will be redesigned as an Incremental Engine.
- Existing SHA256 results are preserved.
- Immich and Nextcloud remain deferred.
- Automatic deletion remains prohibited.
