# AI Home Datacenter Architecture

## Control Plane

Mac mini M4 is the Brain.

It controls the Ubuntu Worker through approved SSH or API commands and consumes JSON reports.

## Worker Plane

Ubuntu Server runs operational workloads only.

- Docker
- Storage
- Backup
- Inventory
- Hash processing
- Immich
- Nextcloud
- Plex

## Runtime Flow

Mac mini
→ Ubuntu Runtime
→ Approved Command
→ JSON or Text Report
→ AI Analysis
→ User Approval

## Storage Flow

Archive
→ Inventory
→ Pending Hash Queue
→ Validation
→ SHA256
→ Incremental Duplicate Index
→ AI Recommendation
→ User Approval

## Safety

- No automatic deletion
- Existing SHA256 values are preserved
- Database changes use transactions
- Database backup is required before write operations
- Immich and Nextcloud remain excluded from current Hash and Duplicate work
