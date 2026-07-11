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

## 2026-07 — Project Audit and Stabilization

### Added

- Storage Freshness Audit
- Safe Storage Reconcile commands
- Incremental Duplicate Schema v3
- Incremental Duplicate Queue Preview
- Runtime command discovery audit

### Fixed

- Corrected Runtime registration audit for automatic command discovery
- Fixed nested SQLite transaction in fast Storage Reconcile
- Corrected Archive mount detection to use the parent filesystem
- Added failed-command report existence guards

### Git Safety

- SQLite WAL and SHM files are removed from Git tracking
- Generated reports are excluded from Git
- Runtime databases, backups and test databases are excluded from Git

### Policy

- Automatic deletion remains disabled
- Immich and Nextcloud remain deferred
- Storage freshness must be verified before Hash or Duplicate processing

## 2026-07 — Experimental Duplicate Commands

### Changed

- Moved full Duplicate table preview out of the operational Runtime.
- Moved full Duplicate rebuild test out of the operational Runtime.
- Operational Duplicate processing remains Incremental.
- Long-running full rebuild commands require explicit manual execution.

### Safety

- Automatic deletion remains disabled.
- Experimental commands are not automatically discovered by runtime.sh.

## 2026-07 — Incremental Duplicate automated tests

### Added

- Incremental processing state test
- Hash Batch lifecycle test
- Duplicate Group relationship test
- Retry and Resume test
- Maximum Retry Count test
- Integrated Incremental Duplicate test suite

### Policy

- Maximum automatic retry count is 3.
- Retry-limit failures require manual review.
- Tests operate on copied databases.
- The operating database remains unchanged.
- Automatic file deletion remains disabled.

## 2026-07 — Storage Agent v1.0.0 RC1

### Release Candidate Validation

- Runtime commands and command files are synchronized.
- Schema v3 metadata and database objects are consistent.
- SQLite integrity check passed.
- Foreign key validation passed.
- Incremental Duplicate processing tests passed.
- Retry and Resume tests passed.
- Maximum Retry Count validation passed.
- Operating database remained unchanged during tests.
- Runtime database files and generated reports are excluded from Git.

### Safety

- Incremental Duplicate production processing remains disabled.
- Initial Backfill remains disabled.
- Automatic deletion remains disabled.
- Retry limit failures require manual approval.
