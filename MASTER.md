# AI Home Datacenter Master Status

## Current Phase

Sprint 5 completed.
Sprint 5.5 Incremental Duplicate Engine is next.

## Platform Roles

### Mac mini M4 — Brain

- AI Agent
- OpenAI
- Claude
- Ollama
- Homepage
- WordPress
- n8n
- Notion
- GitHub
- Ubuntu Worker control
- Dashboard and notifications

Mac mini performs decisions and orchestration only.

### Ubuntu Server — Worker

- Docker
- Storage
- Backup
- Immich
- Nextcloud
- Plex
- Runtime Commands
- Storage Agent
- Inventory
- SHA256 processing
- SMART and backup verification

Ubuntu does not perform AI reasoning.

## Completed Foundations

- Ubuntu Runtime
- Runtime health reporting
- Storage Agent
- SQLite Inventory
- Legacy Inventory stabilization
- Hash Queue Preview
- Queue validation
- SHA256 Dry Run
- DB Apply Preview
- Transaction safety gate
- Rollback test
- SQLite backup and restore test
- Limited Batch Dry Run

## Current Inventory

- Total records: approximately 1.53 million
- Existing SHA256 results are preserved
- Archive is the Master Repository
- Immich and Nextcloud are deferred
- Automatic deletion is prohibited

## Next Architecture Decision

Duplicate processing uses an Incremental Engine.

Full Inventory duplicate rebuild is not the normal operating model.
