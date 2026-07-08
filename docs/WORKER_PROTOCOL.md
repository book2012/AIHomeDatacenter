# Ubuntu Worker Protocol

## Purpose

Ubuntu is a Worker Node.

It does not run AI workloads.

It provides:
- Storage
- Docker
- Nextcloud
- Immich
- Plex
- Backup
- Restore
- Health status

## Control Rule

Control Center must only execute approved scripts under:

/opt/aihomedatacenter/scripts

## Worker Ready

Script:

/opt/aihomedatacenter/scripts/worker-ready.sh

Output:

/mnt/tempdisk/runtime/worker-ready.json

Purpose:
- Created at boot
- Reports whether Worker is ready

## Worker Heartbeat

Script:

/opt/aihomedatacenter/scripts/worker-heartbeat.sh

Output:

/mnt/tempdisk/runtime/worker-heartbeat.json

Purpose:
- Updated periodically
- Reports runtime status

## Worker Recovery

Script:

/opt/aihomedatacenter/scripts/worker-recovery.sh

Output:

/mnt/tempdisk/runtime/worker-recovery.json

Mode:

detect_only

Purpose:
- Detect failed mounts
- Detect Docker health
- Report issues
- No automatic restart yet

## Systemd Services

worker-ready.service

worker-heartbeat.service
worker-heartbeat.timer

worker-recovery.service
worker-recovery.timer

## Control Center Flow

WOL
↓
SSH available
↓
Read worker-ready.json
↓
Wait until ready=true
↓
Run approved script
↓
Track task registry
↓
Read heartbeat/recovery
↓
Safe shutdown when idle
