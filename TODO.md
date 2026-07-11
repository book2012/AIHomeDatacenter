# TODO

## Critical

- Verify exHDD2 Reconcile result
- Audit Archive Other area separately from Immich and Nextcloud
- Confirm all runtime databases and reports are excluded from Git
- Commit Storage Agent core source and tests

## Sprint 5.5

- Rebuild Incremental Duplicate Queue after Storage reconciliation
- Create Incremental Processing Preview
- Add retry and resume state
- Add automated Incremental Duplicate tests
- Keep initial backfill disabled until Storage freshness is verified

## Audit and Stabilization

- Review disk-status.sh changes
- Classify duplicate-rebuild-test.sh as experimental
- Review scripts/deferred
- Remove Runtime WAL, SHM and generated reports from Git tracking
- Synchronize README, MASTER, ARCHITECTURE, ROADMAP and CHANGELOG

## Deferred

- Immich Inventory processing
- Nextcloud Inventory processing
- Automatic Duplicate cleanup
- Archive full scan
- Mac mini Brain integration
