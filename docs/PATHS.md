# AI Home Datacenter Paths

## Runtime Code

/opt/aihomedatacenter

Contains:
- Git repo
- scripts
- compose
- configs
- docs
- reports

## Primary Data

/mnt/storage

Role:
- Cloud
- Immich
- AI data
- Backup
- Plex
- Legacy target

## Backup Disk

/mnt/backupdisk

Role:
- Critical backups
- DB dumps
- config backups
- compose backups

## Temp Disk

/mnt/tempdisk

Role:
- hash
- duplicate logs
- runtime status
- temporary workspace

## Runtime Status

/mnt/tempdisk/runtime

Files:
- worker-ready.json
- worker-heartbeat.json
- worker-recovery.json

## External HDD 1

/mnt/exHDD1

Role:
- Cold Backup
- Disaster Recovery
- future Plex overflow

## External HDD 2

/mnt/exHDD2

Role:
- Legacy Archive
- future secondary archive / Plex overflow
