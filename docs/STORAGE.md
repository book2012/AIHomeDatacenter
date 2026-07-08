# Storage Policy

Ubuntu is a Storage Node.

Mac mini is the Operator.

## Mounts

- /mnt/storage: Primary storage
- /mnt/backupdisk: Backup disk
- /mnt/tempdisk: Temp workspace
- /mnt/exHDD1: External cold backup
- /mnt/exHDD2: Cleanup/import disk

## Data Classes

### Critical

- Photos
- Family
- Documents
- Nextcloud
- Immich database
- Compose/config/scripts

### Rebuildable

- Plex media
- Cache
- Temporary files

## Rules

- Plex is not backed up.
- Runtime data is not committed to Git.
- Temp work uses /mnt/tempdisk.
- Ubuntu stores. Mac mini operates.
